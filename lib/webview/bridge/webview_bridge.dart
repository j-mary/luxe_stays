import 'dart:async';
import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../../core/analytics/analytics.dart';
import '../../core/logging/app_logger.dart';
import '../../core/utils/ids.dart';
import 'bridge_message.dart';

/// Handler invoked for each validated inbound message.
typedef BridgeHandler = void Function(BridgeMessage message);

/// The native half of the hybrid bridge.
///
/// Responsibilities, in order of importance:
///
/// 1. **Origin enforcement.** Every inbound message is checked against the
///    allowlist *at the moment it arrives*, using the WebView's current URL.
///    A `JavaScriptChannel` is global to the WebView: if the page navigates to
///    an attacker-controlled origin, that origin can post to our channel too.
///    Registering the channel is therefore not the security boundary - this
///    check is.
/// 2. **Handshake and queueing.** Nothing is sent until the page reports
///    [BridgeMessageType.ready]; messages sent before that are queued, so a
///    slow page load cannot lose the init payload.
/// 3. **Payload hygiene.** Everything crossing into JavaScript is JSON-encoded
///    by `jsonEncode`, never string-interpolated. String interpolation into a
///    `runJavaScript` call is a script-injection bug waiting for a guest name
///    with a quote in it.
/// 4. **Timeouts.** A page that never sends `ready` must not leave the user on
///    a spinner forever.
class WebViewBridge {
  WebViewBridge({
    required AppLogger logger,
    required AnalyticsService analytics,
    required List<String> allowedOrigins,
    this.readyTimeout = const Duration(seconds: 12),
  })  : _logger = logger,
        _analytics = analytics,
        _allowedOrigins = allowedOrigins;

  final AppLogger _logger;
  final AnalyticsService _analytics;
  final List<String> _allowedOrigins;
  final Duration readyTimeout;

  final Map<BridgeMessageType, BridgeHandler> _handlers =
      <BridgeMessageType, BridgeHandler>{};
  final List<BridgeMessage> _outboundQueue = <BridgeMessage>[];
  final Completer<void> _readyCompleter = Completer<void>();

  WebViewController? _controller;
  Timer? _readyTimer;
  bool _pageReady = false;
  bool _disposed = false;

  /// Resolves when the page completes the handshake.
  Future<void> get onReady => _readyCompleter.future;

  bool get isReady => _pageReady;

  void on(BridgeMessageType type, BridgeHandler handler) {
    _handlers[type] = handler;
  }

  /// Registers the channel on [controller]. Call before `loadRequest`.
  void attach(WebViewController controller) {
    _controller = controller;
    controller.addJavaScriptChannel(
      BridgeMessage.channelName,
      onMessageReceived: _onChannelMessage,
    );
    _readyTimer = Timer(readyTimeout, () {
      if (!_pageReady && !_disposed) {
        _logger.warn(
          'webview bridge: page did not complete handshake in '
          '${readyTimeout.inSeconds}s',
        );
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.completeError(
            TimeoutException('bridge handshake', readyTimeout),
          );
        }
      }
    });
  }

  /// Injects the page-side shim.
  ///
  /// Sent on `onPageFinished` so it survives in-page navigations. The shim is
  /// tiny on purpose: it defines a listener registry and a `postMessage`
  /// wrapper, and nothing else. Anything more complex belongs in the web app,
  /// where it can be tested and deployed by the team that owns it.
  Future<void> injectShim(WebViewController controller) {
    return controller.runJavaScript(_shimSource);
  }

  /// Sends a message to the page, queueing until the handshake completes.
  Future<void> send(BridgeMessage message) async {
    if (_disposed) {
      return;
    }
    if (!_pageReady) {
      _outboundQueue.add(message);
      return;
    }
    await _deliver(message);
  }

  Future<void> sendInit({
    required String locale,
    required String currency,
    required bool isDarkMode,
    required double topInset,
    required double bottomInset,
    String? sessionToken,
    String? membershipNumber,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    return send(
      BridgeMessage(
        id: Ids.uuidV4(),
        type: BridgeMessageType.init,
        payload: <String, Object?>{
          'locale': locale,
          'currency': currency,
          'theme': isDarkMode ? 'dark' : 'light',
          'platform': 'flutter',
          'safeArea': <String, Object?>{'top': topInset, 'bottom': bottomInset},
          if (sessionToken != null) 'sessionToken': sessionToken,
          if (membershipNumber != null) 'membershipNumber': membershipNumber,
          ...extra,
        },
      ),
    );
  }

  Future<void> _deliver(BridgeMessage message) async {
    final WebViewController? controller = _controller;
    if (controller == null) {
      return;
    }
    // jsonEncode twice: once for the message, once to produce a safely quoted
    // JavaScript string literal. Never interpolate raw text into JS.
    final String literal = jsonEncode(message.encode());
    try {
      await controller.runJavaScript(
        'window.LuxeStaysBridge && window.LuxeStaysBridge._receive($literal);',
      );
    } catch (e) {
      _logger.warn('webview bridge: delivery failed', error: e);
    }
  }

  void _onChannelMessage(JavaScriptMessage jsMessage) {
    if (_disposed) {
      return;
    }
    unawaited(_handleChannelMessage(jsMessage.message));
  }

  Future<void> _handleChannelMessage(String raw) async {
    if (raw.length > _maxMessageBytes) {
      _logger.warn('webview bridge: dropped oversized message '
          '(${raw.length} bytes)');
      return;
    }

    if (!await _isCurrentOriginAllowed()) {
      _analytics.event(AnalyticsEvents.webviewNavigationBlocked);
      return;
    }

    final BridgeMessage? message = BridgeMessage.tryParse(raw);
    if (message == null) {
      _logger.warn('webview bridge: unparseable or unknown message dropped');
      return;
    }
    if (!message.type.isInbound) {
      _logger.warn('webview bridge: outbound-only type ${message.type.wire} '
          'received from page - dropped');
      return;
    }
    if (message.version > BridgeMessage.protocolVersion) {
      _logger.warn('webview bridge: message protocol v${message.version} is '
          'newer than this build (v${BridgeMessage.protocolVersion})');
      // Still dispatched: the fields we know about are, by contract, additive.
    }

    _analytics.event(
      AnalyticsEvents.webviewBridgeMessage,
      parameters: <String, Object?>{'type': message.type.wire},
    );

    if (message.type == BridgeMessageType.ready) {
      _onPageReady();
    }
    if (message.type == BridgeMessageType.log) {
      _logger.debug(
        'webview: ${message.stringField('message')}',
        context: <String, Object?>{'level': message.stringField('level')},
      );
    }

    _handlers[message.type]?.call(message);
  }

  void _onPageReady() {
    _pageReady = true;
    _readyTimer?.cancel();
    if (!_readyCompleter.isCompleted) {
      _readyCompleter.complete();
    }
    _logger.info('webview bridge: handshake complete, flushing '
        '${_outboundQueue.length} queued message(s)');
    final List<BridgeMessage> queued = List<BridgeMessage>.from(_outboundQueue);
    _outboundQueue.clear();
    for (final BridgeMessage message in queued) {
      unawaited(_deliver(message));
    }
  }

  /// Reads the WebView's live URL and checks it against the allowlist.
  Future<bool> _isCurrentOriginAllowed() async {
    final WebViewController? controller = _controller;
    if (controller == null) {
      return false;
    }
    try {
      final String? current = await controller.currentUrl();
      if (current == null) {
        return false;
      }
      final String origin = Uri.parse(current).origin;
      final bool allowed = _allowedOrigins.contains(origin);
      if (!allowed) {
        _logger.warn(
          'webview bridge: message from disallowed origin dropped',
          context: <String, Object?>{'origin': origin},
        );
      }
      return allowed;
    } catch (e) {
      _logger.warn('webview bridge: origin check failed', error: e);
      return false;
    }
  }

  void dispose() {
    _disposed = true;
    _readyTimer?.cancel();
    _outboundQueue.clear();
    _handlers.clear();
  }

  static const int _maxMessageBytes = 256 * 1024;

  /// The page-side shim. Kept in Dart so the host controls the contract.
  static const String _shimSource = '''
(function () {
  if (window.LuxeStaysBridge && window.LuxeStaysBridge.__installed) { return; }
  var listeners = {};
  var api = {
    __installed: true,
    version: 1,
    /** Register a handler for a native → web message type. */
    on: function (type, fn) {
      (listeners[type] = listeners[type] || []).push(fn);
    },
    /** Send a web → native message. */
    post: function (type, payload, replyTo) {
      var msg = {
        v: 1,
        id: 'web_' + Date.now() + '_' + Math.random().toString(36).slice(2, 8),
        type: type,
        payload: payload || {},
      };
      if (replyTo) { msg.replyTo = replyTo; }
      if (window.LuxeStaysBridge_channel) {
        window.LuxeStaysBridge_channel.postMessage(JSON.stringify(msg));
      }
      return msg.id;
    },
    /** Invoked by the host. Not part of the public page API. */
    _receive: function (raw) {
      var msg;
      try { msg = JSON.parse(raw); } catch (e) { return; }
      var fns = listeners[msg.type] || [];
      for (var i = 0; i < fns.length; i++) {
        try { fns[i](msg.payload, msg); } catch (e) {
          api.post('error', { message: String(e), source: 'listener' });
        }
      }
    },
  };
  // The Flutter JavaScriptChannel is installed as a global object with the
  // channel name; alias it so page code has one stable entry point.
  window.LuxeStaysBridge_channel = window.LuxeStaysBridge_channel ||
      window.LuxeStaysBridge;
  window.LuxeStaysBridge = api;
  window.addEventListener('error', function (e) {
    api.post('error', { message: String(e.message), source: 'window' });
  });
  api.post('ready', { href: window.location.href });
})();
''';
}

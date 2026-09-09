import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app/providers.dart';
import '../core/analytics/analytics.dart';
import '../core/config/app_config.dart';
import '../core/logging/app_logger.dart';
import 'bridge/bridge_message.dart';
import 'bridge/webview_bridge.dart';

/// The one WebView widget in the app.
///
/// Every hybrid surface - the SynXis booking engine, the hosted payment page,
/// CMS-authored legal and itinerary pages - is this widget with different
/// handlers. Having exactly one means the hard parts are solved once:
///
///  * navigation allowlisting (a hybrid screen must not become a browser);
///  * deep-link interception (terminal states arrive as `luxestays://` URLs
///    that are consumed, never loaded);
///  * the bridge handshake and shim injection on every `onPageFinished`;
///  * a real error state instead of the WebView's own grey "page not found";
///  * back-button semantics that pop web history before popping the route.
///
/// See `docs/02-WEBVIEW-BRIDGE.md` for the protocol and
/// `docs/07-BOOKING-PAYMENT-FLOW.md` for how it is used in checkout.
class HybridWebView extends ConsumerStatefulWidget {
  const HybridWebView({
    required this.initialUri,
    required this.title,
    this.handlers = const <BridgeMessageType, BridgeHandler>{},
    this.onDeepLink,
    this.onLoadError,
    this.showAppBar = true,
    this.confirmOnExit = false,
    this.exitConfirmationText =
        'Leave this page? Any details you have entered will be lost.',
    super.key,
  });

  final Uri initialUri;
  final String title;

  /// Bridge message handlers, wired before the first load.
  final Map<BridgeMessageType, BridgeHandler> handlers;

  /// Called for any navigation to the app's custom scheme. Return true to
  /// consume it (the WebView will not navigate).
  final bool Function(Uri uri)? onDeepLink;

  final void Function(String description)? onLoadError;
  final bool showAppBar;

  /// Payment and booking flows set this: silently losing a half-filled card
  /// form to a stray back-swipe is a support ticket.
  final bool confirmOnExit;
  final String exitConfirmationText;

  @override
  ConsumerState<HybridWebView> createState() => _HybridWebViewState();
}

class _HybridWebViewState extends ConsumerState<HybridWebView> {
  late final WebViewController _controller;
  late final WebViewBridge _bridge;
  late final AppLogger _logger;
  late final AnalyticsService _analytics;
  late final AppConfig _config;

  int _progress = 0;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _config = ref.read(appConfigProvider);
    _logger = ref.read(loggerProvider);
    _analytics = ref.read(analyticsProvider);

    _bridge = WebViewBridge(
      logger: _logger,
      analytics: _analytics,
      allowedOrigins: _config.webViewAllowedOrigins,
    );
    widget.handlers.forEach(_bridge.on);
    _bridge.on(BridgeMessageType.close, (_) => _popIfMounted());

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('LuxeStays/1.0 (Flutter; hybrid)')
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() => _progress = progress);
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _error = null;
              });
            }
          },
          onPageFinished: (String url) async {
            // Re-injected on every page load: an in-page navigation inside the
            // booking engine would otherwise leave the page with no bridge.
            await _bridge.injectShim(_controller);
            if (mounted) {
              setState(() => _isLoading = false);
            }
            await _sendInit();
          },
          onWebResourceError: (WebResourceError error) {
            // Sub-resource failures (a tracking pixel, a font) are noise. Only
            // a failure of the main document is an error state for the user.
            if (error.isForMainFrame == false) {
              return;
            }
            _logger.warn(
              'webview resource error',
              context: <String, Object?>{
                'code': error.errorCode,
                'type': error.errorType?.name,
                'url': error.url,
              },
            );
            widget.onLoadError?.call(error.description);
            if (mounted) {
              setState(() {
                _isLoading = false;
                _error = error.description;
              });
            }
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      );

    _bridge.attach(_controller);
    _controller.loadRequest(widget.initialUri);
  }

  Future<void> _sendInit() async {
    if (!mounted) {
      return;
    }
    final MediaQueryData media = MediaQuery.of(context);
    await _bridge.sendInit(
      locale: Localizations.localeOf(context).toLanguageTag(),
      currency: 'USD',
      isDarkMode: Theme.of(context).brightness == Brightness.dark,
      topInset: media.padding.top,
      bottomInset: media.padding.bottom,
    );
  }

  /// The security boundary for navigation.
  ///
  /// Three outcomes:
  ///  1. custom scheme  → consumed by [HybridWebView.onDeepLink], never loaded;
  ///  2. allowed origin → navigate;
  ///  3. anything else  → blocked and logged. In production an external link
  ///     would be handed to the system browser rather than silently dropped, so
  ///     that a legitimate "read our privacy policy" link still works - but it
  ///     leaves the hybrid context, which is the point.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final Uri uri = Uri.parse(request.url);

    if (uri.scheme == 'luxestays') {
      final bool consumed = widget.onDeepLink?.call(uri) ?? false;
      _logger.info('webview deep link ${uri.host} '
          '(${consumed ? 'consumed' : 'ignored'})');
      return NavigationDecision.prevent;
    }

    final bool allowed = _config.webViewAllowedOrigins.contains(uri.origin);
    if (!allowed) {
      _analytics.event(
        AnalyticsEvents.webviewNavigationBlocked,
        parameters: <String, Object?>{'origin': uri.origin},
      );
      _logger.warn(
        'blocked webview navigation',
        context: <String, Object?>{'url': request.url},
      );
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  void _popIfMounted() {
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<bool> _handleBack() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      return false;
    }
    if (!widget.confirmOnExit) {
      return true;
    }
    if (!mounted) {
      return true;
    }
    final bool? leave = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Leave this page?'),
        content: Text(widget.exitConfirmationText),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Stay'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) {
          return;
        }
        // Resolved before the await: holding the NavigatorState rather than a
        // BuildContext is what makes this safe across the async gap, and is
        // why `use_build_context_synchronously` is satisfied here.
        final NavigatorState navigator = Navigator.of(context);
        final bool shouldPop = await _handleBack();
        if (shouldPop && navigator.mounted && navigator.canPop()) {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: widget.showAppBar
            ? AppBar(
                title: Text(widget.title),
                bottom: _progress < 100 && _isLoading
                    ? PreferredSize(
                        preferredSize: const Size.fromHeight(2),
                        child: LinearProgressIndicator(
                          value: _progress / 100,
                          minHeight: 2,
                        ),
                      )
                    : null,
              )
            : null,
        body: SafeArea(
          child: Stack(
            children: <Widget>[
              WebViewWidget(controller: _controller),
              if (_error != null)
                _WebViewErrorState(
                  message: _error!,
                  onRetry: () {
                    setState(() => _error = null);
                    _controller.loadRequest(widget.initialUri);
                  },
                ),
              if (_isLoading && _error == null)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x11000000),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WebViewErrorState extends StatelessWidget {
  const _WebViewErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.wifi_off_rounded, size: 48),
                const SizedBox(height: 16),
                Text(
                  'We could not load this page',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 24),
                FilledButton(
                    onPressed: onRetry, child: const Text('Try again')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

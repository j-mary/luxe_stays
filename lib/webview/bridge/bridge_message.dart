import 'dart:convert';

/// The wire protocol between the Flutter host and the web content.
///
/// A hybrid app lives or dies on this contract. The rules it encodes:
///
///  * **Versioned.** [protocolVersion] travels on every message. Web and native
///    ship on different cadences - the web team can deploy at 11am on a Tuesday
///    while the native app in the field is three releases old - so both sides
///    must be able to recognise a message they are too old to understand and
///    ignore it politely instead of throwing.
///  * **Typed, closed set.** [BridgeMessageType] is an enum, not a free string.
///    An unknown type is logged and dropped, never dispatched.
///  * **Correlated.** Every message carries an [id]; replies echo it in
///    [replyTo], so a request/response pair can be matched and timed out.
///  * **Data only.** The payload is JSON. Nothing in this protocol can cause
///    native code to execute an arbitrary name - a bridge that dispatches on a
///    method string supplied by the page is a remote-code-execution primitive.
class BridgeMessage {
  const BridgeMessage({
    required this.id,
    required this.type,
    this.payload = const <String, Object?>{},
    this.replyTo,
    this.version = protocolVersion,
  });

  /// Bump when a breaking change lands. Additive changes do not bump.
  static const int protocolVersion = 1;

  /// The `JavaScriptChannel` name registered on the WebView. The page calls
  /// `LuxeStaysBridge.postMessage(...)`.
  static const String channelName = 'LuxeStaysBridge';

  final String id;
  final BridgeMessageType type;
  final Map<String, Object?> payload;
  final String? replyTo;
  final int version;

  /// Parses a raw channel message. Returns null - rather than throwing - for
  /// anything malformed: the page is untrusted input, and a parse failure must
  /// never take down the host.
  static BridgeMessage? tryParse(String raw) {
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      final BridgeMessageType? type =
          BridgeMessageType.fromWire(decoded['type']?.toString());
      if (type == null) {
        return null;
      }
      final Object? payload = decoded['payload'];
      return BridgeMessage(
        id: decoded['id']?.toString() ?? '',
        type: type,
        payload: payload is Map<String, Object?>
            ? payload
            : const <String, Object?>{},
        replyTo: decoded['replyTo']?.toString(),
        version: decoded['v'] is int ? decoded['v']! as int : 1,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'v': version,
        'id': id,
        'type': type.wire,
        'payload': payload,
        if (replyTo != null) 'replyTo': replyTo,
      };

  String encode() => jsonEncode(toJson());

  /// Typed payload readers. Kept here so screens never index raw maps.
  String? stringField(String key) => payload[key]?.toString();

  int? intField(String key) {
    final Object? value = payload[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  bool boolField(String key, {bool fallback = false}) {
    final Object? value = payload[key];
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }
}

/// Every message the bridge understands, in both directions.
enum BridgeMessageType {
  // ---- web → native -------------------------------------------------------
  /// The page has loaded and installed its listener. Native replies with
  /// [init]. Until this arrives, outbound messages are queued.
  ready('ready'),

  /// The page asks for a fresh session/auth token (its own expired).
  authRequest('auth.request'),

  /// Terminal payment state from the hosted PSP page.
  paymentResult('payment.result'),

  /// Terminal state from the SynXis booking engine.
  bookingResult('booking.result'),

  /// The page wants the host to navigate natively (e.g. "open the loyalty
  /// screen"). The host decides whether to honour it.
  navigate('navigate'),

  /// The page wants to be dismissed.
  close('close'),

  /// Content height changed - used to size an embedded (non-full-screen)
  /// WebView to its content without an internal scroll view.
  resize('resize'),

  /// Forward an analytics event so web and native funnels share one stream.
  analytics('analytics'),

  /// Structured log line from the page, surfaced in our own logs.
  log('log'),

  /// The page hit an error it wants the host to know about.
  error('error'),

  // ---- native → web -------------------------------------------------------
  /// Host context: locale, currency, theme, safe-area insets, session token.
  init('init'),

  /// Response to [authRequest].
  authToken('auth.token'),

  /// Push the current cart/loyalty state into the page.
  state('state'),

  /// Ask the page to do something (e.g. `{"action":"submit"}`).
  command('command');

  const BridgeMessageType(this.wire);

  final String wire;

  static BridgeMessageType? fromWire(String? wire) {
    if (wire == null) {
      return null;
    }
    for (final BridgeMessageType type in BridgeMessageType.values) {
      if (type.wire == wire) {
        return type;
      }
    }
    return null;
  }

  /// Messages the host will act on. Anything else arriving from the page is
  /// dropped - an allowlist, not a denylist.
  bool get isInbound => switch (this) {
        BridgeMessageType.ready ||
        BridgeMessageType.authRequest ||
        BridgeMessageType.paymentResult ||
        BridgeMessageType.bookingResult ||
        BridgeMessageType.navigate ||
        BridgeMessageType.close ||
        BridgeMessageType.resize ||
        BridgeMessageType.analytics ||
        BridgeMessageType.log ||
        BridgeMessageType.error =>
          true,
        _ => false,
      };
}

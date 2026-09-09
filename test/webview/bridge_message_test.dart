import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:luxe_stays/webview/bridge/bridge_message.dart';

void main() {
  group('BridgeMessage.tryParse', () {
    test('parses a well-formed payment result', () {
      final BridgeMessage? message = BridgeMessage.tryParse(
        jsonEncode(<String, Object?>{
          'v': 1,
          'id': 'web_1',
          'type': 'payment.result',
          'payload': <String, Object?>{
            'intentId': 'pi_1',
            'status': 'authorized',
            'threeDsPerformed': true,
            'last4': '4242',
          },
        }),
      );

      expect(message, isNotNull);
      expect(message!.type, BridgeMessageType.paymentResult);
      expect(message.stringField('intentId'), 'pi_1');
      expect(message.boolField('threeDsPerformed'), isTrue);
      expect(message.stringField('last4'), '4242');
    });

    // The page is untrusted input. Every one of these must return null rather
    // than throw, or a malformed message takes down the host.
    test('returns null for malformed input', () {
      expect(BridgeMessage.tryParse('not json'), isNull);
      expect(BridgeMessage.tryParse('[]'), isNull);
      expect(BridgeMessage.tryParse('{}'), isNull);
      expect(BridgeMessage.tryParse('null'), isNull);
      expect(
        BridgeMessage.tryParse(jsonEncode(<String, Object?>{'type': 'evil'})),
        isNull,
      );
    });

    test('tolerates a missing or non-object payload', () {
      final BridgeMessage? message = BridgeMessage.tryParse(
        jsonEncode(<String, Object?>{'type': 'ready', 'payload': 'nope'}),
      );
      expect(message, isNotNull);
      expect(message!.payload, isEmpty);
    });

    test('accepts a newer protocol version without failing', () {
      // Web deploys ahead of the app store. A v2 message must still parse; the
      // host logs the mismatch and reads the fields it knows.
      final BridgeMessage? message = BridgeMessage.tryParse(
        jsonEncode(<String, Object?>{
          'v': 2,
          'type': 'booking.result',
          'payload': <String, Object?>{'status': 'completed'},
        }),
      );
      expect(message!.version, 2);
      expect(message.type, BridgeMessageType.bookingResult);
    });
  });

  group('direction', () {
    test('host-only message types are rejected when sent by the page', () {
      // `init`, `auth.token`, `state` and `command` travel host → web only.
      expect(BridgeMessageType.init.isInbound, isFalse);
      expect(BridgeMessageType.authToken.isInbound, isFalse);
      expect(BridgeMessageType.state.isInbound, isFalse);
      expect(BridgeMessageType.command.isInbound, isFalse);
    });

    test('page-originated types are accepted', () {
      for (final BridgeMessageType type in <BridgeMessageType>[
        BridgeMessageType.ready,
        BridgeMessageType.paymentResult,
        BridgeMessageType.bookingResult,
        BridgeMessageType.navigate,
        BridgeMessageType.close,
        BridgeMessageType.log,
        BridgeMessageType.error,
      ]) {
        expect(type.isInbound, isTrue, reason: type.wire);
      }
    });
  });

  test('round-trips through encode/parse', () {
    const BridgeMessage original = BridgeMessage(
      id: 'abc',
      type: BridgeMessageType.navigate,
      payload: <String, Object?>{'route': '/loyalty'},
    );
    final BridgeMessage? parsed = BridgeMessage.tryParse(original.encode());
    expect(parsed!.id, 'abc');
    expect(parsed.type, BridgeMessageType.navigate);
    expect(parsed.stringField('route'), '/loyalty');
  });

  test('wire names are stable - changing one is a breaking change', () {
    // Pinned deliberately: these strings are a published contract with the web
    // team. A rename here must be a protocol version bump.
    expect(BridgeMessageType.ready.wire, 'ready');
    expect(BridgeMessageType.paymentResult.wire, 'payment.result');
    expect(BridgeMessageType.bookingResult.wire, 'booking.result');
    expect(BridgeMessageType.authRequest.wire, 'auth.request');
    expect(BridgeMessage.channelName, 'LuxeStaysBridge');
    expect(BridgeMessage.protocolVersion, 1);
  });
}

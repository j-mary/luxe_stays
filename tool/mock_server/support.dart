import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';

/// Shared helpers for the mock vendors.

final Random rng = Random(20260908);

Response jsonResponse(Object? body,
    {int status = 200, Map<String, String>? headers}) {
  return Response(
    status,
    body: jsonEncode(body),
    headers: <String, String>{
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      ...?headers,
    },
  );
}

Response html(String body, {int status = 200}) {
  return Response(
    status,
    body: body,
    headers: const <String, String>{
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
    },
  );
}

Future<Map<String, Object?>> readJson(Request request) async {
  final String body = await request.readAsString();
  if (body.isEmpty) {
    return <String, Object?>{};
  }
  final Object? decoded = jsonDecode(body);
  return decoded is Map<String, Object?> ? decoded : <String, Object?>{};
}

/// Fault-injection knobs, driven by `--latency` / `--fail-rate` on the command
/// line or by the `x-mock-fail` header on an individual request.
///
/// A mock that only ever returns 200 in 5 ms teaches you nothing about how the
/// app behaves when SynXis is slow or Salesforce is down - which is exactly the
/// behaviour the retry, timeout and degradation logic exists for.
class ChaosSettings {
  ChaosSettings({
    this.latency = Duration.zero,
    this.failureRate = 0,
  });

  Duration latency;
  double failureRate;
}

final ChaosSettings chaos = ChaosSettings();

/// Middleware applying the chaos settings plus CORS (the hosted payment page
/// and booking engine are served from the same origin, but a browser-based
/// Flutter web build calls the APIs cross-origin).
Middleware chaosMiddleware() {
  return (Handler inner) {
    return (Request request) async {
      if (chaos.latency > Duration.zero) {
        await Future<void>.delayed(chaos.latency);
      }

      final String? forced = request.headers['x-mock-fail'];
      if (forced != null) {
        final int status = int.tryParse(forced) ?? 500;
        return jsonResponse(
          <String, Object?>{
            'Errors': <Map<String, String>>[
              <String, String>{
                'Code': 'FORCED_FAILURE',
                'Message': 'Injected by x-mock-fail header',
              },
            ],
          },
          status: status,
        );
      }

      if (chaos.failureRate > 0 && rng.nextDouble() < chaos.failureRate) {
        return jsonResponse(
          <String, Object?>{
            'Errors': <Map<String, String>>[
              <String, String>{
                'Code': 'UPSTREAM_UNAVAILABLE',
                'Message': 'Injected failure',
              },
            ],
          },
          status: 503,
        );
      }

      final Response response = await inner(request);
      return response.change(
        headers: <String, String>{
          'access-control-allow-origin': '*',
          'access-control-allow-headers': '*',
          'access-control-allow-methods': 'GET,POST,PATCH,DELETE,OPTIONS',
        },
      );
    };
  };
}

/// Idempotency store, shared by reservation creation, payment intents and
/// loyalty processes.
///
/// This is the server side of the contract the app relies on: replaying a
/// request with the same `Idempotency-Key` returns the original response
/// instead of performing the action twice. Without it, the retry interceptor
/// would be a double-booking machine.
class IdempotencyStore {
  final Map<String, Object?> _responses = <String, Object?>{};

  Object? get(String? key) => key == null ? null : _responses[key];

  void put(String? key, Object? value) {
    if (key != null) {
      _responses[key] = value;
    }
  }
}

final IdempotencyStore idempotency = IdempotencyStore();

/// The origin the client actually used to reach this server.
///
/// Every URL the mock hands back — media, hosted payment pages, CMS pages,
/// itineraries — has to be reachable *from the client*, and the client is not
/// necessarily on this machine. An Android emulator reaches the host at
/// 10.0.2.2 and a physical device at a LAN address, so a hard-coded
/// "http://localhost:8080" in a response body points the app back at itself and
/// every image silently fails while the JSON around it loads fine.
///
/// `requestedUri` carries the Host header the client sent, which is exactly the
/// address it can reach us on.
String originOf(Request request) {
  final Uri uri = request.requestedUri;
  if (uri.host.isEmpty) {
    return 'http://localhost:8080';
  }
  return uri.origin;
}

String isoDate(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

DateTime parseDate(String? value, {DateTime? fallback}) {
  if (value == null) {
    return fallback ?? DateTime.now();
  }
  return DateTime.tryParse(value) ?? (fallback ?? DateTime.now());
}

String reference(String prefix) {
  const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final String body = List<String>.generate(
    6,
    (_) => alphabet[rng.nextInt(alphabet.length)],
  ).join();
  return '$prefix$body';
}

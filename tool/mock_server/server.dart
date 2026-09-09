import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

import 'cms_routes.dart';
import 'fixtures.dart';
import 'leonardo_routes.dart';
import 'payment_routes.dart';
import 'salesforce_routes.dart';
import 'support.dart';
import 'synxis_routes.dart';
import 'web_pages.dart';

/// LuxeStays mock back end.
///
/// One process standing in for four vendors plus our own BFF, so the whole app
/// - search, cart, loyalty, the WebView booking engine and the hosted payment
/// page - runs on a laptop with no credentials and no network.
///
/// ```
///   dart run tool/mock_server/server.dart
///   dart run tool/mock_server/server.dart --port 8080 --latency 400 --fail-rate 0.15
/// ```
///
/// Mount points (they match the `--dart-define`s in the Makefile):
///
/// | Prefix         | Stands in for                                   |
/// |----------------|-------------------------------------------------|
/// | `/synxis`      | Sabre SynXis central reservations               |
/// | `/salesforce`  | Salesforce OAuth + Loyalty + Service Cloud      |
/// | `/cms`         | Headless CMS (Contentful-shaped)                |
/// | `/leonardo`    | Leonardo hotel media (serves real PNGs)         |
/// | `/leonardo-ai` | Leonardo.Ai generative images                   |
/// | `/payments`    | Our BFF's payment-intent endpoints              |
/// | `/pay`         | The PSP's hosted payment page (WebView)         |
/// | `/be`          | The SynXis booking engine (WebView)             |
Future<void> main(List<String> args) async {
  final int port = _intArg(args, '--port') ?? 8080;
  chaos.latency = Duration(milliseconds: _intArg(args, '--latency') ?? 0);
  chaos.failureRate = _doubleArg(args, '--fail-rate') ?? 0;

  final Router root = Router();

  root.mount('/synxis/', synxisRouter().call);
  root.mount('/salesforce/', salesforceRouter().call);
  root.mount('/cms/', cmsRouter().call);
  root.mount('/leonardo/', leonardoRouter().call);
  root.mount('/leonardo-ai/', leonardoAiRouter().call);
  root.mount('/payments/', paymentRouter().call);

  root.get('/pay', hostedPaymentHandler());

  /// The SynXis booking engine page. Query parameters are the ones
  /// `SynxisBookingEngine.bookingUrl` produces.
  root.get('/be', (Request request) {
    final Map<String, String> q = request.url.queryParameters;
    final String hotelId = q['hotel'] ?? mockHotels.first.id;
    final MockHotel hotel = mockHotels.firstWhere(
      (MockHotel h) => h.id == hotelId,
      orElse: () => mockHotels.first,
    );
    return html(
      bookingEnginePage(
        hotelId: hotel.id,
        hotelName: hotel.name,
        arrive: q['arrive'] ?? '',
        depart: q['depart'] ?? '',
        currency: q['currency'] ?? hotel.currency,
        nightlyMinor: hotel.baseNightlyMinor,
        promotionCode: q['promo'],
        membershipNumber: q['member'],
      ),
    );
  });

  root.get(
      '/health',
      (Request request) => jsonResponse(<String, Object?>{
            'status': 'ok',
            'latencyMs': chaos.latency.inMilliseconds,
            'failureRate': chaos.failureRate,
            'hotels': mockHotels.length,
            'members': mockMembers.length,
          }));

  root.get('/', (Request request) => html(_indexPage(port)));

  final Handler handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(chaosMiddleware())
      .addHandler(root.call);

  final HttpServer server = await shelf_io.serve(
    handler,
    InternetAddress.anyIPv4,
    port,
  );
  server.autoCompress = true;

  stdout.writeln('LuxeStays mock back end listening on '
      'http://localhost:${server.port}');
  stdout.writeln('  latency=${chaos.latency.inMilliseconds}ms  '
      'failRate=${chaos.failureRate}');
  stdout
      .writeln('  open http://localhost:${server.port}/ for the endpoint map');
}

int? _intArg(List<String> args, String name) {
  final int index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return int.tryParse(args[index + 1]);
}

double? _doubleArg(List<String> args, String name) {
  final int index = args.indexOf(name);
  if (index == -1 || index + 1 >= args.length) {
    return null;
  }
  return double.tryParse(args[index + 1]);
}

String _indexPage(int port) => '''
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>LuxeStays mock back end</title>
<style>
  body { font: 15px/1.6 -apple-system, "Segoe UI", Roboto, sans-serif;
         margin: 0; padding: 28px; max-width: 820px; }
  code { background: #f3f3f3; padding: 1px 5px; border-radius: 4px; }
  table { border-collapse: collapse; width: 100%; margin-top: 12px; }
  td, th { border-bottom: 1px solid #eee; padding: 8px 6px; text-align: left;
           vertical-align: top; }
</style>
</head>
<body>
<h1>LuxeStays mock back end</h1>
<p>Standing in for SynXis, Salesforce, the CMS, Leonardo and the payment
provider. Fault injection: <code>--latency</code>, <code>--fail-rate</code>, or
the <code>x-mock-fail: 503</code> header on any single request.</p>
<table>
  <tr><th>Endpoint</th><th>Vendor</th></tr>
  <tr><td><code>POST /synxis/v1/api/availability</code></td><td>SynXis shopping</td></tr>
  <tr><td><code>POST /synxis/v1/api/reservations</code></td><td>SynXis booking (idempotent)</td></tr>
  <tr><td><code>GET /salesforce/services/data/v62.0/connect/loyalty/programs/LuxeStaysRewards/members?membershipNumber=LS-100042</code></td><td>Loyalty member</td></tr>
  <tr><td><code>GET /cms/spaces/luxestays/environments/master/entries?content_type=offer</code></td><td>CMS offers</td></tr>
  <tr><td><code>GET /leonardo/v1/properties/H-PAR-001/media</code></td><td>Leonardo media</td></tr>
  <tr><td><code>GET /leonardo/img/H-PAR-001-hero.png?w=720&amp;h=480</code></td><td>Leonardo rendition</td></tr>
  <tr><td><code>POST /leonardo-ai/generations</code></td><td>Leonardo.Ai</td></tr>
  <tr><td><code>GET /pay?intent=...</code></td><td>Hosted payment page (WebView)</td></tr>
  <tr><td><code>GET /be?hotel=H-PAR-001</code></td><td>SynXis booking engine (WebView)</td></tr>
  <tr><td><code>GET /health</code></td><td>This server</td></tr>
</table>
<p>Members to sign in with: <code>LS-100042</code> (Gold),
<code>LS-100077</code> (Platinum), <code>LS-100901</code> (Silver).</p>
<p>Running on port $port.</p>
</body>
</html>
''';

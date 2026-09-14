import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'support.dart';

/// Public 4.29.0 Property Hub retrieval subset. Fictional data; no live auth.
/// Validation beyond explicit header requirements is a local mock assumption.
Router propertyHubRouter() {
  final Router router = Router();
  router.post('/reservations/outbound/data/reservations-details', (
    Request request,
  ) async {
    if (!['1', '2'].contains(request.headers['tenantid'])) {
      return Response(400);
    }
    if (!(request.headers['content-type'] ?? '').startsWith(
      'application/json',
    )) {
      return Response(400);
    }
    final Map<String, Object?> body = await readJson(request);
    if (body['hotelId'] is! int || body['chainId'] is! int) {
      return Response(400);
    }
    final DateTime? start = DateTime.tryParse(
      body['startDateTime']?.toString() ?? '',
    );
    final DateTime? end = DateTime.tryParse(
      body['endDateTime']?.toString() ?? '',
    );
    if (start == null || end == null || !end.isAfter(start)) {
      return Response(400);
    }
    // Local fixture matches only this fictional hotel. Delta persistence is not simulated.
    final List<Map<String, Object?>> reservations = body['hotelId'] == 1234
        ? <Map<String, Object?>>[
            <String, Object?>{
              'chainId': body['chainId'],
              'hotelId': 1234,
              'propertyName': 'LuxeStays Demonstration Hotel',
              'confirmationNumber': 'DEMO1234',
              'status': 'Confirmed',
              'roomTypeCode': 'DLX',
            },
          ]
        : <Map<String, Object?>>[];
    return jsonResponse(<String, Object?>{
      'errors': <Object?>[],
      'currencyCode': 'USD',
      'status': 'SUCCESS',
      'reservations': reservations,
      'total': reservations.length,
    });
  });
  return router;
}

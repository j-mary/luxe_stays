import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'fixtures.dart';
import 'png.dart';
import 'support.dart';

/// Mock **Leonardo** (hotel media platform) plus **Leonardo.Ai** (generative).
///
/// The media endpoint returns a catalogue of assets per property; the image
/// endpoint renders a real PNG at whatever rendition the client asked for, so
/// the `w`/`h`/`q`/`fmt` parameters `LeonardoUrlBuilder` appends are visibly
/// honoured (check the response headers - the served size changes with the
/// device pixel ratio).
Router leonardoRouter() {
  final Router router = Router();

  router.get('/v1/properties/<hotelId>/media',
      (Request request, String hotelId) {
    final Map<String, String> q = request.url.queryParameters;
    final String? roomTypeCode = q['roomTypeCode'];
    final String? category = q['category'];

    final List<Map<String, Object?>> assets = <Map<String, Object?>>[];

    if (roomTypeCode != null) {
      for (int i = 1; i <= 3; i++) {
        assets.add(
          _asset(
            hotelId: hotelId,
            id: '$hotelId-$roomTypeCode-$i',
            category: 'Guest Room',
            caption: 'Room $roomTypeCode, view $i',
            roomTypeCodes: <String>[roomTypeCode],
            primary: i == 1,
          ),
        );
      }
    } else {
      assets.add(
        _asset(
          hotelId: hotelId,
          id: '$hotelId-hero',
          category: 'Exterior',
          caption: 'Exterior',
          primary: true,
        ),
      );
      for (final String cat in mockMediaCategories) {
        if (category != null && category != cat) {
          continue;
        }
        assets.add(
          _asset(
            hotelId: hotelId,
            id: '$hotelId-${cat.toLowerCase().replaceAll(' ', '-')}',
            category: cat,
            caption: cat,
            roomTypeCodes: cat == 'Guest Room'
                ? <String>['DLX']
                : cat == 'Suite'
                    ? <String>['STE', 'JRSTE']
                    : const <String>[],
          ),
        );
      }
      // One asset with a lapsed licence, so the client-side filter is exercised.
      assets.add(
        _asset(
          hotelId: hotelId,
          id: '$hotelId-archive',
          category: 'Lobby',
          caption: 'Archive image (licence expired)',
          licenceExpired: true,
        ),
      );
    }

    return jsonResponse(<String, Object?>{
      'propertyId': hotelId,
      'total': assets.length,
      'assets': assets,
    });
  });

  /// Renders the actual bitmap.
  router.get('/img/<name>', (Request request, String name) {
    final Map<String, String> q = request.url.queryParameters;
    final int width = int.tryParse(q['w'] ?? '') ?? 800;
    final int height = int.tryParse(q['h'] ?? '') ?? 533;
    final Uint8List bytes = gradientPng(
      width: width,
      height: height,
      seed: seedFrom(name),
    );
    return Response.ok(
      bytes,
      headers: <String, String>{
        'content-type': 'image/png',
        'content-length': '${bytes.length}',
        // Media is immutable per rendition, so it is safe to cache hard. This
        // is what makes the app's image traffic collapse on a second launch.
        'cache-control': 'public, max-age=86400',
        'x-rendition': '${width}x$height q=${q['q'] ?? '-'} '
            'fmt=${q['fmt'] ?? '-'}',
      },
    );
  });

  return router;
}

Map<String, Object?> _asset({
  required String hotelId,
  required String id,
  required String category,
  required String caption,
  List<String> roomTypeCodes = const <String>[],
  bool primary = false,
  bool licenceExpired = false,
}) {
  return <String, Object?>{
    'mediaId': id,
    'deliveryUrl': 'http://localhost:8080/leonardo/img/$id.png',
    'category': category,
    'caption': caption,
    'credit': 'Property photography',
    'width': 1600,
    'height': 1067,
    'isPrimary': primary,
    'roomTypeCodes': roomTypeCodes,
    'tags': <String>[hotelId, category],
    'licenceExpiresAt': licenceExpired
        ? DateTime.now().subtract(const Duration(days: 30)).toIso8601String()
        : DateTime.now().add(const Duration(days: 400)).toIso8601String(),
  };
}

/// Mock Leonardo.Ai: submit a generation, poll it, get URLs back.
Router leonardoAiRouter() {
  final Router router = Router();
  final Map<String, DateTime> jobs = <String, DateTime>{};

  router.post('/generations', (Request request) async {
    final Map<String, Object?> body = await readJson(request);
    final String id = 'gen_${DateTime.now().millisecondsSinceEpoch}';
    jobs[id] = DateTime.now();
    return jsonResponse(<String, Object?>{
      'sdGenerationJob': <String, Object?>{
        'generationId': id,
        'apiCreditCost': 8,
        'prompt': body['prompt'],
      },
    });
  });

  router.get('/generations/<id>', (Request request, String id) {
    final DateTime? started = jobs[id];
    if (started == null) {
      return jsonResponse(
        <String, Object?>{'error': 'Unknown generation', 'code': 'NOT_FOUND'},
        status: 404,
      );
    }
    // Generative image APIs are slow; completing only after ~3 s keeps the
    // client's polling and timeout logic honest.
    final bool ready = DateTime.now().difference(started).inSeconds >= 3;
    return jsonResponse(<String, Object?>{
      'generations_by_pk': <String, Object?>{
        'id': id,
        'status': ready ? 'COMPLETE' : 'PENDING',
        'generated_images': ready
            ? <Map<String, Object?>>[
                <String, Object?>{
                  'id': '${id}_0',
                  'url':
                      'http://localhost:8080/leonardo/img/$id.png?w=1024&h=640',
                },
              ]
            : <Map<String, Object?>>[],
      },
    });
  });

  return router;
}

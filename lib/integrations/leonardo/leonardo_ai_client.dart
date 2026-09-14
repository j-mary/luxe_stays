import 'dart:async';

import '../../core/error/failure.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/result.dart';
import '../../domain/media.dart';

/// Client for **Leonardo.Ai** - the generative image API
/// (`https://cloud.leonardo.ai/api/rest/v1`).
///
/// ### Why both Leonardo platforms are in this POC
/// "Leonardo" in a hospitality context almost always means Leonardo Worldwide,
/// the hotel media platform ([LeonardoClient]). Leonardo.Ai is a different
/// company with a similar name and a public generative-image API. Both are
/// wired up here behind the same `MediaProvider` interface, which incidentally
/// demonstrates the point the architecture is making: the app asks for
/// *pictures*, and where they come from is a swappable detail.
///
/// ### Where generative imagery is and is not acceptable
/// Never for a room, a property or an amenity: a guest booking a 1,200/night
/// suite must see that suite. It is used here only for **destination mood
/// imagery** on editorial/inspiration surfaces, and every such asset is tagged
/// [MediaSource.leonardoAi] so the UI can label it. That labelling is a product
/// requirement, not a nicety.
///
/// ### Where the key lives
/// Not in the app. Leonardo.Ai's own docs are explicit that the API key must
/// not be embedded client side, and generation is billed per credit - a key
/// extracted from an APK is somebody else's GPU budget. The handset calls our
/// BFF, which holds the key and enforces per-user quotas. [LeonardoAiClient]
/// therefore points at the BFF by default; pointing it straight at
/// `cloud.leonardo.ai` is supported only for local experimentation.
class LeonardoAiClient {
  LeonardoAiClient({
    required this._client,
    required this._logger,
    this.pollInterval = const Duration(seconds: 2),
    this.pollTimeout = const Duration(seconds: 45),
  });

  final ApiClient _client;
  final AppLogger _logger;
  final Duration pollInterval;
  final Duration pollTimeout;

  /// Submits a generation job. Leonardo.Ai is asynchronous: this returns a
  /// generation id which must then be polled.
  Future<Result<String>> submitGeneration({
    required String prompt,
    int width = 1024,
    int height = 640,
    int numImages = 1,
    String? modelId,
    String? negativePrompt,
  }) {
    return _client.postJson<String>(
      '/generations',
      body: <String, Object?>{
        'prompt': prompt,
        'width': width,
        'height': height,
        'num_images': numImages,
        'modelId': ?modelId,
        'negative_prompt': ?negativePrompt,
        // Never let a generated asset leak into the public gallery of the
        // vendor's community feed - hotel briefs are commercially sensitive.
        'public': false,
      },
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        final Object job = root['sdGenerationJob'] ?? root;
        return JsonRead.string(
          JsonRead.object(job, 'sdGenerationJob'),
          'generationId',
        );
      },
    );
  }

  /// Fetches a generation, whatever state it is in.
  Future<Result<GenerationState>> generation(String generationId) {
    return _client.getJson<GenerationState>(
      '/generations/$generationId',
      decode: (Object? json) {
        final Map<String, Object?> root = JsonRead.object(json, 'root');
        final Map<String, Object?> generation = JsonRead.object(
          root['generations_by_pk'] ?? root,
          'generations_by_pk',
        );
        final String status =
            JsonRead.stringOrNull(generation, 'status') ?? 'PENDING';
        final List<Map<String, Object?>> images =
            generation['generated_images'] == null
            ? const <Map<String, Object?>>[]
            : JsonRead.objectList(
                generation['generated_images'],
                'generated_images',
              );
        return GenerationState(
          id: generationId,
          status: status,
          imageUrls: images
              .map((Map<String, Object?> i) => JsonRead.string(i, 'url'))
              .toList(growable: false),
        );
      },
    );
  }

  /// Submit + poll to completion, with a hard timeout.
  ///
  /// The timeout matters: this runs on a UI-adjacent path, and an unbounded
  /// poll loop against a busy GPU queue is how you get a spinner that never
  /// stops. On timeout the caller falls back to curated imagery.
  Future<Result<List<MediaAsset>>> generateDestinationImagery({
    required String prompt,
    required String destinationId,
    int numImages = 1,
  }) async {
    final Result<String> submitted = await submitGeneration(
      prompt: prompt,
      numImages: numImages,
    );

    final String? generationId = submitted.valueOrNull;
    if (generationId == null) {
      return Err<List<MediaAsset>>(submitted.failureOrNull!);
    }

    final DateTime deadline = DateTime.now().add(pollTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      final Result<GenerationState> polled = await generation(generationId);
      final GenerationState? state = polled.valueOrNull;
      if (state == null) {
        return Err<List<MediaAsset>>(polled.failureOrNull!);
      }
      if (state.isFailed) {
        return Err<List<MediaAsset>>(
          ServerFailure(
            userMessage: 'We could not create that image right now.',
            developerMessage: 'leonardo.ai generation $generationId failed',
            statusCode: 200,
          ),
        );
      }
      if (state.isComplete) {
        _logger.info(
          'leonardo.ai: generation $generationId complete '
          '(${state.imageUrls.length} image(s))',
        );
        return Ok<List<MediaAsset>>(
          state.imageUrls
              .map(
                (String url) => MediaAsset(
                  id: '$generationId:${state.imageUrls.indexOf(url)}',
                  baseUrl: url,
                  category: MediaCategory.destination,
                  altText: 'AI-generated impression of $destinationId',
                  source: MediaSource.leonardoAi,
                  credit: 'AI-generated image',
                ),
              )
              .toList(growable: false),
        );
      }
    }

    _logger.warn('leonardo.ai: generation $generationId timed out');
    return Err<List<MediaAsset>>(
      NetworkFailure(
        userMessage:
            'That is taking longer than expected. Showing our '
            'curated photography instead.',
        developerMessage:
            'leonardo.ai generation $generationId exceeded ${pollTimeout.inSeconds}s',
      ),
    );
  }
}

class GenerationState {
  const GenerationState({
    required this.id,
    required this.status,
    this.imageUrls = const <String>[],
  });

  final String id;
  final String status;
  final List<String> imageUrls;

  bool get isComplete =>
      status.toUpperCase() == 'COMPLETE' && imageUrls.isNotEmpty;
  bool get isFailed => status.toUpperCase() == 'FAILED';
}

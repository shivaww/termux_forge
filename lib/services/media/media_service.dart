/// Media generation service for images and videos.
///
/// [MediaService] provides a unified interface for generating media
/// through various providers (DALL-E, Stable Diffusion, Runway, etc.),
/// tracking job status, and linking outputs to the artifact system.
library;

import 'package:nexon/data/models/media_model.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// MediaProvider
// ---------------------------------------------------------------------------

/// A registered media generation provider.
class MediaProvider {
  const MediaProvider({
    required this.id,
    required this.name,
    this.supportedTypes = const [MediaType.image],
    this.models = const [],
    this.isAvailable = true,
  });

  /// Unique provider identifier.
  final String id;

  /// Human-readable name (e.g. "DALL-E", "Stable Diffusion").
  final String name;

  /// Types of media this provider can generate.
  final List<MediaType> supportedTypes;

  /// Available model identifiers.
  final List<String> models;

  /// Whether the provider is currently available.
  final bool isAvailable;
}

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for media job persistence.
abstract class MediaJobRepository {
  Future<void> save(MediaJob job);
  Future<MediaJob?> get(String id);
  Future<List<MediaJob>> getAll();
  Future<void> delete(String id);
  Future<List<MediaJob>> query(bool Function(MediaJob) predicate);
}

/// In-memory [MediaJobRepository] for development.
class InMemoryMediaJobRepository implements MediaJobRepository {
  final Map<String, MediaJob> _store = {};

  @override
  Future<void> save(MediaJob job) async => _store[job.id] = job;

  @override
  Future<MediaJob?> get(String id) async => _store[id];

  @override
  Future<List<MediaJob>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<MediaJob>> query(bool Function(MediaJob) predicate) async {
    return _store.values.where(predicate).toList();
  }
}

// ---------------------------------------------------------------------------
// MediaGenerationHandler
// ---------------------------------------------------------------------------

/// Callback that performs the actual media generation.
///
/// Receives the job and returns the path to the generated output file.
typedef MediaGenerationHandler = Future<String> Function(MediaJob job);

// ---------------------------------------------------------------------------
// MediaService
// ---------------------------------------------------------------------------

/// Service for generating and managing media assets.
class MediaService {
  /// Creates a [MediaService] backed by the given [repository].
  MediaService({
    MediaJobRepository? repository,
    this.generationHandler,
  }) : _repo = repository ?? InMemoryMediaJobRepository();

  final MediaJobRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// Optional handler that performs the actual generation.
  final MediaGenerationHandler? generationHandler;

  /// Registered providers.
  final List<MediaProvider> _providers = [];

  /// Register a media provider.
  void registerProvider(MediaProvider provider) {
    _providers.add(provider);
    _log.d('Media provider registered: ${provider.name}');
  }

  /// Generate an image.
  Future<MediaJob> generateImage({
    required String prompt,
    required String provider,
    required String model,
    Map<String, dynamic> metadata = const {},
  }) async {
    return _generate(
      type: MediaType.image,
      prompt: prompt,
      provider: provider,
      model: model,
      metadata: metadata,
    );
  }

  /// Generate a video.
  Future<MediaJob> generateVideo({
    required String prompt,
    required String provider,
    required String model,
    Map<String, dynamic> metadata = const {},
  }) async {
    return _generate(
      type: MediaType.video,
      prompt: prompt,
      provider: provider,
      model: model,
      metadata: metadata,
    );
  }

  /// List all registered providers.
  List<MediaProvider> listProviders() => List.unmodifiable(_providers);

  /// List models for a specific provider.
  List<String> listModels(String providerId) {
    final provider = _providers.where((p) => p.id == providerId).firstOrNull;
    return provider?.models ?? [];
  }

  /// Select the best model for a given media type.
  String? selectModel(MediaType type) {
    for (final provider in _providers) {
      if (provider.isAvailable && provider.supportedTypes.contains(type)) {
        return provider.models.isNotEmpty ? provider.models.first : null;
      }
    }
    return null;
  }

  /// Get job history.
  Future<List<MediaJob>> getHistory({MediaType? type}) async {
    if (type != null) {
      return _repo.query((j) => j.type == type);
    }
    return _repo.getAll();
  }

  /// Get the output artifact path for a completed job.
  Future<String?> getArtifact(String jobId) async {
    final job = await _repo.get(jobId);
    return job?.outputPath;
  }

  // ---- Private ------------------------------------------------------------

  Future<MediaJob> _generate({
    required MediaType type,
    required String prompt,
    required String provider,
    required String model,
    Map<String, dynamic> metadata = const {},
  }) async {
    var job = MediaJob(
      id: _uuid.v4(),
      type: type,
      prompt: prompt,
      provider: provider,
      model: model,
      metadata: metadata,
      createdAt: DateTime.now(),
    );
    await _repo.save(job);
    _log.i('Media job created: ${job.id} (${type.name})');

    if (generationHandler != null) {
      try {
        job = job.copyWith(status: MediaJobStatus.processing);
        await _repo.save(job);

        final outputPath = await generationHandler!(job);
        job = job.copyWith(
          status: MediaJobStatus.completed,
          outputPath: outputPath,
          completedAt: DateTime.now(),
        );
        _log.i('Media job completed: ${job.id} → $outputPath');
      } catch (e) {
        job = job.copyWith(
          status: MediaJobStatus.failed,
          error: e.toString(),
          completedAt: DateTime.now(),
        );
        _log.e('Media job failed: ${job.id}', error: e);
      }
      await _repo.save(job);
    }

    return job;
  }
}

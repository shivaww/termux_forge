/// Artifact management service.
///
/// [ArtifactService] tracks generated outputs (APKs, reports, images, etc.)
/// with provenance, versioning, history, and linking to tasks and workflows.
library;

import 'package:nexon/data/models/artifact_model.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for the artifact persistence layer.
abstract class ArtifactRepository {
  Future<void> save(ArtifactModel artifact);
  Future<ArtifactModel?> get(String id);
  Future<List<ArtifactModel>> getAll();
  Future<void> delete(String id);
  Future<List<ArtifactModel>> query(
    bool Function(ArtifactModel) predicate,
  );
}

/// In-memory [ArtifactRepository] for development.
class InMemoryArtifactRepository implements ArtifactRepository {
  final Map<String, ArtifactModel> _store = {};

  @override
  Future<void> save(ArtifactModel artifact) async {
    _store[artifact.id] = artifact;
  }

  @override
  Future<ArtifactModel?> get(String id) async => _store[id];

  @override
  Future<List<ArtifactModel>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<ArtifactModel>> query(
    bool Function(ArtifactModel) predicate,
  ) async {
    return _store.values.where(predicate).toList();
  }
}

// ---------------------------------------------------------------------------
// ArtifactService
// ---------------------------------------------------------------------------

/// High-level service for managing build artifacts and generated outputs.
class ArtifactService {
  /// Creates an [ArtifactService] backed by the given [repository].
  ArtifactService({ArtifactRepository? repository})
      : _repo = repository ?? InMemoryArtifactRepository();

  final ArtifactRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// Register a new artifact.
  Future<ArtifactModel> register({
    required String name,
    required ArtifactType type,
    required String path,
    int size = 0,
    String? taskId,
    String? workflowId,
    Map<String, dynamic> provenance = const {},
    String version = '1.0.0',
    List<String> tags = const [],
  }) async {
    final artifact = ArtifactModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      path: path,
      size: size,
      taskId: taskId,
      workflowId: workflowId,
      provenance: provenance,
      createdAt: DateTime.now(),
      version: version,
      tags: tags,
    );
    await _repo.save(artifact);
    _log.i('Artifact registered: ${artifact.id} — $name');
    return artifact;
  }

  /// List all artifacts.
  Future<List<ArtifactModel>> list() => _repo.getAll();

  /// Get a single artifact by [id].
  Future<ArtifactModel?> getById(String id) => _repo.get(id);

  /// Get artifacts filtered by [type].
  Future<List<ArtifactModel>> getByType(ArtifactType type) {
    return _repo.query((a) => a.type == type);
  }

  /// Export artifact metadata as JSON (the file itself stays on disk).
  Future<Map<String, dynamic>?> export(String id) async {
    final artifact = await _repo.get(id);
    return artifact?.toJson();
  }

  /// Mark an artifact for sharing (returns the artifact with updated metadata).
  Future<ArtifactModel?> share(String id) async {
    final artifact = await _repo.get(id);
    if (artifact == null) return null;
    final updated = artifact.copyWith(
      provenance: {
        ...artifact.provenance,
        'shared': true,
        'sharedAt': DateTime.now().toIso8601String(),
      },
    );
    await _repo.save(updated);
    _log.i('Artifact shared: $id');
    return updated;
  }

  /// Delete an artifact record (does not delete the file from disk).
  Future<void> delete(String id) async {
    await _repo.delete(id);
    _log.d('Artifact deleted: $id');
  }

  /// Get version history of an artifact by [name] (all versions with the
  /// same name).
  Future<List<ArtifactModel>> getHistory(String name) {
    return _repo.query((a) => a.name == name);
  }

  /// Link an artifact to a task.
  Future<ArtifactModel?> linkToTask(String id, String taskId) async {
    final artifact = await _repo.get(id);
    if (artifact == null) return null;
    final updated = artifact.copyWith(taskId: taskId);
    await _repo.save(updated);
    return updated;
  }

  /// Remove stale artifact records whose files no longer exist.
  ///
  /// The [fileExists] callback checks whether a path is still valid.
  /// Returns the number of cleaned-up records.
  Future<int> cleanup(Future<bool> Function(String path) fileExists) async {
    final all = await _repo.getAll();
    var cleaned = 0;
    for (final artifact in all) {
      if (!await fileExists(artifact.path)) {
        await _repo.delete(artifact.id);
        cleaned++;
      }
    }
    _log.i('Artifact cleanup: removed $cleaned stale records');
    return cleaned;
  }
}

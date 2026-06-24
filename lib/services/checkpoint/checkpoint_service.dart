/// Checkpoint and rollback service.
///
/// [CheckpointService] creates, compares, and restores project state
/// snapshots. Checkpoints capture the git hash, file content hashes, and
/// memory state so the system can roll back to a known-good point.
library;

import 'package:nexon/data/models/checkpoint_model.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for checkpoint persistence.
abstract class CheckpointRepository {
  Future<void> save(CheckpointModel checkpoint);
  Future<CheckpointModel?> get(String id);
  Future<List<CheckpointModel>> getAll();
  Future<void> delete(String id);
  Future<List<CheckpointModel>> query(
    bool Function(CheckpointModel) predicate,
  );
}

/// In-memory [CheckpointRepository] for development.
class InMemoryCheckpointRepository implements CheckpointRepository {
  final Map<String, CheckpointModel> _store = {};

  @override
  Future<void> save(CheckpointModel checkpoint) async {
    _store[checkpoint.id] = checkpoint;
  }

  @override
  Future<CheckpointModel?> get(String id) async => _store[id];

  @override
  Future<List<CheckpointModel>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<CheckpointModel>> query(
    bool Function(CheckpointModel) predicate,
  ) async {
    return _store.values.where(predicate).toList();
  }
}

// ---------------------------------------------------------------------------
// CheckpointDiff
// ---------------------------------------------------------------------------

/// Describes differences between two checkpoints.
class CheckpointDiff {
  const CheckpointDiff({
    required this.addedFiles,
    required this.removedFiles,
    required this.modifiedFiles,
    required this.gitHashChanged,
  });

  /// Files present in the newer checkpoint but not the older.
  final List<String> addedFiles;

  /// Files present in the older checkpoint but not the newer.
  final List<String> removedFiles;

  /// Files present in both but with different hashes.
  final List<String> modifiedFiles;

  /// Whether the git hash changed between the two checkpoints.
  final bool gitHashChanged;

  @override
  String toString() =>
      'CheckpointDiff(added=${addedFiles.length}, removed=${removedFiles.length}, modified=${modifiedFiles.length})';
}

// ---------------------------------------------------------------------------
// CheckpointService
// ---------------------------------------------------------------------------

/// Service for creating, comparing, and restoring project checkpoints.
class CheckpointService {
  /// Creates a [CheckpointService] backed by the given [repository].
  CheckpointService({CheckpointRepository? repository})
      : _repo = repository ?? InMemoryCheckpointRepository();

  final CheckpointRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// Create a new checkpoint.
  Future<CheckpointModel> create({
    required String name,
    required String projectId,
    String? gitHash,
    Map<String, String> fileSnapshots = const {},
    Map<String, dynamic> memorySnapshot = const {},
    bool autoCreated = false,
    String? linkedTaskId,
  }) async {
    final checkpoint = CheckpointModel(
      id: _uuid.v4(),
      name: name,
      projectId: projectId,
      gitHash: gitHash,
      fileSnapshots: fileSnapshots,
      memorySnapshot: memorySnapshot,
      createdAt: DateTime.now(),
      autoCreated: autoCreated,
      linkedTaskId: linkedTaskId,
    );
    await _repo.save(checkpoint);
    _log.i('Checkpoint created: ${checkpoint.id} — $name');
    return checkpoint;
  }

  /// List all checkpoints, optionally filtered by [projectId].
  Future<List<CheckpointModel>> list({String? projectId}) async {
    if (projectId != null) {
      return _repo.query((c) => c.projectId == projectId);
    }
    return _repo.getAll();
  }

  /// Compare two checkpoints and return their diff.
  Future<CheckpointDiff?> compare(String oldId, String newId) async {
    final oldCp = await _repo.get(oldId);
    final newCp = await _repo.get(newId);
    if (oldCp == null || newCp == null) return null;

    final oldFiles = oldCp.fileSnapshots;
    final newFiles = newCp.fileSnapshots;

    final added = newFiles.keys
        .where((f) => !oldFiles.containsKey(f))
        .toList();
    final removed = oldFiles.keys
        .where((f) => !newFiles.containsKey(f))
        .toList();
    final modified = newFiles.keys
        .where((f) =>
            oldFiles.containsKey(f) && oldFiles[f] != newFiles[f])
        .toList();

    return CheckpointDiff(
      addedFiles: added,
      removedFiles: removed,
      modifiedFiles: modified,
      gitHashChanged: oldCp.gitHash != newCp.gitHash,
    );
  }

  /// Rollback to a checkpoint.
  ///
  /// The [restoreFile] callback is responsible for restoring each file from
  /// the checkpoint's snapshots. [restoreMemory] restores the memory state.
  /// Returns `true` if the rollback completed successfully.
  Future<bool> rollback(
    String checkpointId, {
    required Future<void> Function(Map<String, String> fileSnapshots)
        restoreFiles,
    required Future<void> Function(Map<String, dynamic> memorySnapshot)
        restoreMemory,
  }) async {
    final checkpoint = await _repo.get(checkpointId);
    if (checkpoint == null) {
      _log.w('Checkpoint not found: $checkpointId');
      return false;
    }

    try {
      _log.i('Rolling back to checkpoint: ${checkpoint.name}');
      await restoreFiles(checkpoint.fileSnapshots);
      await restoreMemory(checkpoint.memorySnapshot);
      _log.i('Rollback complete: ${checkpoint.name}');
      return true;
    } catch (e, st) {
      _log.e('Rollback failed', error: e, stackTrace: st);
      return false;
    }
  }

  /// Create an automatic checkpoint before a potentially destructive action.
  Future<CheckpointModel> autoCheckpoint({
    required String projectId,
    String? gitHash,
    Map<String, String> fileSnapshots = const {},
    Map<String, dynamic> memorySnapshot = const {},
    String? linkedTaskId,
  }) async {
    return create(
      name: 'auto-${DateTime.now().millisecondsSinceEpoch}',
      projectId: projectId,
      gitHash: gitHash,
      fileSnapshots: fileSnapshots,
      memorySnapshot: memorySnapshot,
      autoCreated: true,
      linkedTaskId: linkedTaskId,
    );
  }

  /// Link a checkpoint to a git commit hash.
  Future<CheckpointModel?> linkToGit(
    String checkpointId,
    String gitHash,
  ) async {
    final checkpoint = await _repo.get(checkpointId);
    if (checkpoint == null) return null;
    final updated = checkpoint.copyWith(gitHash: gitHash);
    await _repo.save(updated);
    return updated;
  }

  /// Get all file snapshots from a checkpoint.
  Future<Map<String, String>> getSnapshots(String checkpointId) async {
    final checkpoint = await _repo.get(checkpointId);
    return checkpoint?.fileSnapshots ?? {};
  }
}

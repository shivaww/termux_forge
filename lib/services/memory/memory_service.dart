/// Project Memory service — the central read/write interface for the
/// TermuxForge agentic memory system.
///
/// [MemoryService] provides CRUD, querying, keyword search, semantic search
/// delegation, bulk import/export, and pruning. It operates against an
/// abstract [MemoryRepository] so the backing store (Isar, JSON, SQLite)
/// can be swapped without touching business logic.
library;

import 'package:nexon/data/models/project_memory_model.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for the persistence layer backing [MemoryService].
///
/// Implementations can use Isar, a JSON file store, SQLite, or any other
/// mechanism that satisfies these operations.
abstract class MemoryRepository {
  /// Persist a single [entry]. Upserts by [MemoryEntry.id].
  Future<void> save(MemoryEntry entry);

  /// Retrieve a single entry by [id], or `null` if not found.
  Future<MemoryEntry?> get(String id);

  /// Return all entries that match [predicate].
  Future<List<MemoryEntry>> query(bool Function(MemoryEntry) predicate);

  /// Return all entries.
  Future<List<MemoryEntry>> getAll();

  /// Delete the entry with the given [id].
  Future<void> delete(String id);

  /// Delete all entries older than [cutoff].
  Future<int> deleteOlderThan(DateTime cutoff);

  /// Persist a batch of entries.
  Future<void> saveAll(List<MemoryEntry> entries);
}

// ---------------------------------------------------------------------------
// In-Memory Repository (default / development)
// ---------------------------------------------------------------------------

/// A simple in-memory [MemoryRepository] useful for development and testing.
class InMemoryMemoryRepository implements MemoryRepository {
  final Map<String, MemoryEntry> _store = {};

  @override
  Future<void> save(MemoryEntry entry) async {
    _store[entry.id] = entry;
  }

  @override
  Future<MemoryEntry?> get(String id) async => _store[id];

  @override
  Future<List<MemoryEntry>> query(
    bool Function(MemoryEntry) predicate,
  ) async {
    return _store.values.where(predicate).toList();
  }

  @override
  Future<List<MemoryEntry>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async {
    _store.remove(id);
  }

  @override
  Future<int> deleteOlderThan(DateTime cutoff) async {
    final before = _store.length;
    _store.removeWhere((_, e) => e.updatedAt.isBefore(cutoff));
    return before - _store.length;
  }

  @override
  Future<void> saveAll(List<MemoryEntry> entries) async {
    for (final e in entries) {
      _store[e.id] = e;
    }
  }
}

// ---------------------------------------------------------------------------
// MemoryStats
// ---------------------------------------------------------------------------

/// Aggregate statistics about the memory store.
class MemoryStats {
  const MemoryStats({
    required this.totalEntries,
    required this.entriesByType,
    required this.totalFileRefs,
    required this.oldestEntry,
    required this.newestEntry,
  });

  /// Total number of entries.
  final int totalEntries;

  /// Count of entries grouped by [MemoryType].
  final Map<MemoryType, int> entriesByType;

  /// Total number of file references across all entries.
  final int totalFileRefs;

  /// Timestamp of the oldest entry (null if store is empty).
  final DateTime? oldestEntry;

  /// Timestamp of the newest entry (null if store is empty).
  final DateTime? newestEntry;

  @override
  String toString() =>
      'MemoryStats(total=$totalEntries, types=$entriesByType)';
}

// ---------------------------------------------------------------------------
// MemoryService
// ---------------------------------------------------------------------------

/// High-level service for interacting with the project memory system.
///
/// Any agent, tool, or UI component can read from and write to the memory
/// through this service. Search is keyword-based here; semantic (vector)
/// search is delegated to [VectorMemoryService].
class MemoryService {
  /// Creates a [MemoryService] backed by the given [repository].
  MemoryService({MemoryRepository? repository})
      : _repo = repository ?? InMemoryMemoryRepository();

  final MemoryRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  // ---- CRUD ---------------------------------------------------------------

  /// Persist a [MemoryEntry]. If [entry.id] already exists it is overwritten.
  Future<MemoryEntry> save(MemoryEntry entry) async {
    await _repo.save(entry);
    _log.d('Memory saved: ${entry.id} (${entry.type.name})');
    return entry;
  }

  /// Create and persist a new [MemoryEntry] with an auto-generated ID.
  Future<MemoryEntry> create({
    required MemoryType type,
    required String content,
    Map<String, dynamic> metadata = const {},
    List<String> tags = const [],
    String? projectId,
    String? agentId,
    String? taskId,
    List<String> fileRefs = const [],
  }) async {
    final now = DateTime.now();
    final entry = MemoryEntry(
      id: _uuid.v4(),
      type: type,
      content: content,
      metadata: metadata,
      tags: tags,
      projectId: projectId,
      agentId: agentId,
      taskId: taskId,
      fileRefs: fileRefs,
      createdAt: now,
      updatedAt: now,
    );
    return save(entry);
  }

  /// Retrieve a single entry by [id].
  Future<MemoryEntry?> get(String id) => _repo.get(id);

  /// Update an existing entry, merging [updates] via [MemoryEntry.copyWith].
  Future<MemoryEntry?> update(
    String id, {
    String? content,
    Map<String, dynamic>? metadata,
    List<String>? tags,
    List<String>? fileRefs,
    double? relevanceScore,
  }) async {
    final existing = await _repo.get(id);
    if (existing == null) {
      _log.w('Memory update failed — id not found: $id');
      return null;
    }
    final updated = existing.copyWith(
      content: content,
      metadata: metadata,
      tags: tags,
      fileRefs: fileRefs,
      relevanceScore: relevanceScore,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    _log.d('Memory updated: $id');
    return updated;
  }

  /// Delete the entry with the given [id].
  Future<void> delete(String id) async {
    await _repo.delete(id);
    _log.d('Memory deleted: $id');
  }

  // ---- Queries -------------------------------------------------------------

  /// Return entries matching a custom [predicate].
  Future<List<MemoryEntry>> query(
    bool Function(MemoryEntry) predicate,
  ) {
    return _repo.query(predicate);
  }

  /// Return all entries of the given [type].
  Future<List<MemoryEntry>> getByType(MemoryType type) {
    return _repo.query((e) => e.type == type);
  }

  /// Return all entries for the given [projectId].
  Future<List<MemoryEntry>> getByProject(String projectId) {
    return _repo.query((e) => e.projectId == projectId);
  }

  /// Return all entries created by the given [agentId].
  Future<List<MemoryEntry>> getByAgent(String agentId) {
    return _repo.query((e) => e.agentId == agentId);
  }

  /// Return all entries linked to the given [taskId].
  Future<List<MemoryEntry>> getByTask(String taskId) {
    return _repo.query((e) => e.taskId == taskId);
  }

  // ---- Search --------------------------------------------------------------

  /// Simple keyword search across [content] and [tags].
  ///
  /// Returns entries sorted by relevance (number of keyword hits).
  Future<List<MemoryEntry>> search(String keyword) async {
    if (keyword.trim().isEmpty) return [];

    final lowerKeyword = keyword.toLowerCase();
    final results = await _repo.query((entry) {
      final inContent = entry.content.toLowerCase().contains(lowerKeyword);
      final inTags = entry.tags
          .any((tag) => tag.toLowerCase().contains(lowerKeyword));
      return inContent || inTags;
    });

    // Sort by number of occurrences in content (rough relevance).
    results.sort((a, b) {
      final aHits = lowerKeyword
          .allMatches(a.content.toLowerCase())
          .length;
      final bHits = lowerKeyword
          .allMatches(b.content.toLowerCase())
          .length;
      return bHits.compareTo(aHits);
    });

    return results;
  }

  /// Placeholder for semantic / vector search.
  ///
  /// In production, delegate to [VectorMemoryService]. The default
  /// implementation falls back to keyword search.
  Future<List<MemoryEntry>> semanticSearch(
    String query, {
    int topK = 10,
  }) async {
    // Fallback: keyword search. Override or compose with VectorMemoryService.
    final results = await search(query);
    return results.take(topK).toList();
  }

  // ---- Maintenance ---------------------------------------------------------

  /// Remove entries older than [maxAge].
  ///
  /// Returns the number of entries pruned.
  Future<int> pruneOldEntries({
    Duration maxAge = const Duration(days: 90),
  }) async {
    final cutoff = DateTime.now().subtract(maxAge);
    final count = await _repo.deleteOlderThan(cutoff);
    _log.i('Pruned $count memory entries older than $cutoff');
    return count;
  }

  // ---- Import / Export -----------------------------------------------------

  /// Export all memory entries as a list of JSON maps.
  Future<List<Map<String, dynamic>>> exportMemory() async {
    final all = await _repo.getAll();
    return all.map((e) => e.toJson()).toList();
  }

  /// Import memory entries from a list of JSON maps.
  ///
  /// Existing entries with the same ID are overwritten.
  Future<int> importMemory(List<Map<String, dynamic>> data) async {
    final entries = data.map((d) => MemoryEntry.fromJson(d)).toList();
    await _repo.saveAll(entries);
    _log.i('Imported ${entries.length} memory entries');
    return entries.length;
  }

  // ---- Stats ---------------------------------------------------------------

  /// Compute aggregate statistics about the memory store.
  Future<MemoryStats> getStats() async {
    final all = await _repo.getAll();

    final byType = <MemoryType, int>{};
    var totalFileRefs = 0;
    DateTime? oldest;
    DateTime? newest;

    for (final entry in all) {
      byType[entry.type] = (byType[entry.type] ?? 0) + 1;
      totalFileRefs += entry.fileRefs.length;

      if (oldest == null || entry.createdAt.isBefore(oldest)) {
        oldest = entry.createdAt;
      }
      if (newest == null || entry.createdAt.isAfter(newest)) {
        newest = entry.createdAt;
      }
    }

    return MemoryStats(
      totalEntries: all.length,
      entriesByType: byType,
      totalFileRefs: totalFileRefs,
      oldestEntry: oldest,
      newestEntry: newest,
    );
  }
}

/// Todo tracking service for managing lightweight to-do items.
///
/// [TodoService] provides full CRUD, progress tracking, filtering by
/// status / priority / agent, timeline views, and linking to files,
/// memory entries, and artifacts. Completion percentages are auto-calculated
/// from progress notes when subtask granularity is available.
library;

import 'package:nexon/data/models/todo_model.dart';
import 'package:uuid/uuid.dart';
import 'package:logger/logger.dart';

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for the todo persistence layer.
abstract class TodoRepository {
  Future<void> save(TodoModel todo);
  Future<TodoModel?> get(String id);
  Future<List<TodoModel>> getAll();
  Future<void> delete(String id);
  Future<List<TodoModel>> query(bool Function(TodoModel) predicate);
}

// ---------------------------------------------------------------------------
// In-Memory Repository
// ---------------------------------------------------------------------------

/// Default in-memory [TodoRepository] for development and testing.
class InMemoryTodoRepository implements TodoRepository {
  final Map<String, TodoModel> _store = {};

  @override
  Future<void> save(TodoModel todo) async => _store[todo.id] = todo;

  @override
  Future<TodoModel?> get(String id) async => _store[id];

  @override
  Future<List<TodoModel>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);

  @override
  Future<List<TodoModel>> query(bool Function(TodoModel) predicate) async {
    return _store.values.where(predicate).toList();
  }
}

// ---------------------------------------------------------------------------
// TodoService
// ---------------------------------------------------------------------------

/// High-level service for managing todo items.
class TodoService {
  /// Creates a [TodoService] backed by the given [repository].
  TodoService({TodoRepository? repository})
      : _repo = repository ?? InMemoryTodoRepository();

  final TodoRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  // ---- CRUD ---------------------------------------------------------------

  /// Create a new todo item and persist it.
  Future<TodoModel> create({
    required String title,
    String description = '',
    String priority = 'medium',
    String? agentOwner,
    DateTime? dueDate,
    String? workflowTemplateId,
  }) async {
    final now = DateTime.now();
    final todo = TodoModel(
      id: _uuid.v4(),
      title: title,
      description: description,
      priority: priority,
      agentOwner: agentOwner,
      dueDate: dueDate,
      workflowTemplateId: workflowTemplateId,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.save(todo);
    _log.d('Todo created: ${todo.id} — $title');
    return todo;
  }

  /// Update an existing todo by [id].
  Future<TodoModel?> update(
    String id, {
    String? title,
    String? description,
    int? percentage,
    String? priority,
    String? agentOwner,
    DateTime? dueDate,
    TodoStatus? status,
    String? modelUsed,
    String? toolUsed,
  }) async {
    final existing = await _repo.get(id);
    if (existing == null) {
      _log.w('Todo not found: $id');
      return null;
    }

    // Build completion history entry if percentage changed.
    final history = List<Map<String, dynamic>>.from(existing.completionHistory);
    if (percentage != null && percentage != existing.percentage) {
      history.add({
        'from': existing.percentage,
        'to': percentage,
        'timestamp': DateTime.now().toIso8601String(),
      });
    }

    // Auto-set status based on percentage.
    var newStatus = status ?? existing.status;
    if (percentage != null) {
      if (percentage >= 100) {
        newStatus = TodoStatus.completed;
      } else if (percentage > 0 && newStatus == TodoStatus.notStarted) {
        newStatus = TodoStatus.inProgress;
      }
    }

    final updated = existing.copyWith(
      title: title,
      description: description,
      percentage: percentage,
      priority: priority,
      agentOwner: agentOwner,
      dueDate: dueDate,
      status: newStatus,
      modelUsed: modelUsed,
      toolUsed: toolUsed,
      completionHistory: history,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    _log.d('Todo updated: $id');
    return updated;
  }

  /// Delete a todo by [id].
  Future<void> delete(String id) async {
    await _repo.delete(id);
    _log.d('Todo deleted: $id');
  }

  /// List all todos.
  Future<List<TodoModel>> list() => _repo.getAll();

  /// Get a single todo by [id].
  Future<TodoModel?> getById(String id) => _repo.get(id);

  // ---- Progress -----------------------------------------------------------

  /// Update the completion percentage of a todo.
  Future<TodoModel?> updateProgress(String id, int percentage) async {
    return update(id, percentage: percentage.clamp(0, 100));
  }

  /// Get the current completion percentage.
  Future<int> getCompletionPercentage(String id) async {
    final todo = await _repo.get(id);
    return todo?.percentage ?? 0;
  }

  // ---- Filters ------------------------------------------------------------

  /// Get todos filtered by [status].
  Future<List<TodoModel>> getByStatus(TodoStatus status) {
    return _repo.query((t) => t.status == status);
  }

  /// Get todos filtered by [priority].
  Future<List<TodoModel>> getByPriority(String priority) {
    return _repo.query((t) => t.priority == priority);
  }

  /// Get todos owned by [agentId].
  Future<List<TodoModel>> getByAgent(String agentId) {
    return _repo.query((t) => t.agentOwner == agentId);
  }

  /// Get all blocked todos.
  Future<List<TodoModel>> getBlocked() {
    return _repo.query((t) => t.status == TodoStatus.blocked);
  }

  // ---- Timeline -----------------------------------------------------------

  /// Get todos sorted by due date (ascending, nulls last).
  Future<List<TodoModel>> getTimeline() async {
    final all = await _repo.getAll();
    all.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    return all;
  }

  // ---- Linking ------------------------------------------------------------

  /// Link a file path to an existing todo.
  Future<TodoModel?> linkToFile(String id, String filePath) async {
    final existing = await _repo.get(id);
    if (existing == null) return null;
    final files = List<String>.from(existing.linkedFiles)..add(filePath);
    final updated = existing.copyWith(
      linkedFiles: files,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    return updated;
  }

  /// Link a memory entry to an existing todo.
  Future<TodoModel?> linkToMemory(String id, String memoryId) async {
    final existing = await _repo.get(id);
    if (existing == null) return null;
    final refs = List<String>.from(existing.linkedMemoryRefs)..add(memoryId);
    final updated = existing.copyWith(
      linkedMemoryRefs: refs,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    return updated;
  }

  /// Link an artifact to an existing todo.
  Future<TodoModel?> linkToArtifact(String id, String artifactId) async {
    final existing = await _repo.get(id);
    if (existing == null) return null;
    final links = List<String>.from(existing.artifactLinks)..add(artifactId);
    final updated = existing.copyWith(
      artifactLinks: links,
      updatedAt: DateTime.now(),
    );
    await _repo.save(updated);
    return updated;
  }
}

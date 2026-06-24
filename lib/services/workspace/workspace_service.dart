/// Multi-project workspace management service.
///
/// [WorkspaceService] allows users to create workspaces that group projects
/// together with shared configuration, switch between them, and manage
/// project membership.
library;

import 'package:nexon/data/models/workspace_model.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for workspace persistence.
abstract class WorkspaceRepository {
  Future<void> save(WorkspaceModel workspace);
  Future<WorkspaceModel?> get(String id);
  Future<List<WorkspaceModel>> getAll();
  Future<void> delete(String id);
}

/// In-memory [WorkspaceRepository] for development.
class InMemoryWorkspaceRepository implements WorkspaceRepository {
  final Map<String, WorkspaceModel> _store = {};

  @override
  Future<void> save(WorkspaceModel workspace) async {
    _store[workspace.id] = workspace;
  }

  @override
  Future<WorkspaceModel?> get(String id) async => _store[id];

  @override
  Future<List<WorkspaceModel>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);
}

// ---------------------------------------------------------------------------
// WorkspaceService
// ---------------------------------------------------------------------------

/// Service for managing multi-project workspaces.
class WorkspaceService {
  /// Creates a [WorkspaceService] backed by the given [repository].
  WorkspaceService({WorkspaceRepository? repository})
      : _repo = repository ?? InMemoryWorkspaceRepository();

  final WorkspaceRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// The currently active workspace ID.
  String? _activeWorkspaceId;

  /// Create a new workspace.
  Future<WorkspaceModel> create({
    required String name,
    String? activePath,
  }) async {
    final workspace = WorkspaceModel(
      id: _uuid.v4(),
      name: name,
      activePath: activePath,
      createdAt: DateTime.now(),
    );
    await _repo.save(workspace);
    _log.i('Workspace created: ${workspace.id} — $name');
    return workspace;
  }

  /// Switch to a different workspace by [id].
  Future<WorkspaceModel?> switchWorkspace(String id) async {
    final workspace = await _repo.get(id);
    if (workspace == null) {
      _log.w('Workspace not found: $id');
      return null;
    }
    _activeWorkspaceId = id;
    _log.i('Switched to workspace: ${workspace.name}');
    return workspace;
  }

  /// List all workspaces.
  Future<List<WorkspaceModel>> list() => _repo.getAll();

  /// Add a project to a workspace.
  Future<WorkspaceModel?> addProject(
    String workspaceId,
    String projectId,
  ) async {
    final workspace = await _repo.get(workspaceId);
    if (workspace == null) return null;
    if (workspace.projects.contains(projectId)) return workspace;

    final updated = workspace.copyWith(
      projects: [...workspace.projects, projectId],
    );
    await _repo.save(updated);
    _log.d('Added project $projectId to workspace $workspaceId');
    return updated;
  }

  /// Remove a project from a workspace.
  Future<WorkspaceModel?> removeProject(
    String workspaceId,
    String projectId,
  ) async {
    final workspace = await _repo.get(workspaceId);
    if (workspace == null) return null;

    final updated = workspace.copyWith(
      projects: workspace.projects.where((p) => p != projectId).toList(),
    );
    await _repo.save(updated);
    _log.d('Removed project $projectId from workspace $workspaceId');
    return updated;
  }

  /// Get the currently active workspace.
  Future<WorkspaceModel?> getActive() async {
    if (_activeWorkspaceId == null) return null;
    return _repo.get(_activeWorkspaceId!);
  }

  /// Update workspace configuration.
  Future<WorkspaceModel?> configure(
    String workspaceId, {
    String? name,
    Map<String, dynamic>? modelConfigs,
    List<String>? mcpServers,
    List<String>? knowledgeBases,
    String? activePath,
  }) async {
    final workspace = await _repo.get(workspaceId);
    if (workspace == null) return null;

    final updated = workspace.copyWith(
      name: name,
      modelConfigs: modelConfigs,
      mcpServers: mcpServers,
      knowledgeBases: knowledgeBases,
      activePath: activePath,
    );
    await _repo.save(updated);
    _log.d('Workspace configured: $workspaceId');
    return updated;
  }
}

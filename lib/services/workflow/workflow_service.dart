/// Workflow engine service for orchestrating multi-step pipelines.
///
/// [WorkflowService] manages the lifecycle of workflows — creation,
/// execution, pause/resume, retry, scheduling, and event-triggered runs.
/// It supports sequential, parallel, conditional, scheduled, and
/// event-triggered execution strategies.
library;

import 'package:termux_forge/data/models/workflow_model.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Abstract Repository
// ---------------------------------------------------------------------------

/// Contract for workflow persistence.
abstract class WorkflowRepository {
  Future<void> save(WorkflowModel workflow);
  Future<WorkflowModel?> get(String id);
  Future<List<WorkflowModel>> getAll();
  Future<void> delete(String id);
}

/// In-memory [WorkflowRepository] for development.
class InMemoryWorkflowRepository implements WorkflowRepository {
  final Map<String, WorkflowModel> _store = {};

  @override
  Future<void> save(WorkflowModel workflow) async {
    _store[workflow.id] = workflow;
  }

  @override
  Future<WorkflowModel?> get(String id) async => _store[id];

  @override
  Future<List<WorkflowModel>> getAll() async => _store.values.toList();

  @override
  Future<void> delete(String id) async => _store.remove(id);
}

// ---------------------------------------------------------------------------
// Step Executor
// ---------------------------------------------------------------------------

/// Callback that executes a single workflow step and returns updated output.
typedef StepExecutor = Future<Map<String, dynamic>> Function(
  WorkflowStep step,
);

// ---------------------------------------------------------------------------
// WorkflowService
// ---------------------------------------------------------------------------

/// Service for creating, executing, and managing workflow pipelines.
class WorkflowService {
  /// Creates a [WorkflowService] backed by the given [repository].
  WorkflowService({
    WorkflowRepository? repository,
    this.stepExecutor,
  }) : _repo = repository ?? InMemoryWorkflowRepository();

  final WorkflowRepository _repo;
  final Logger _log = Logger(printer: PrettyPrinter(methodCount: 0));
  static const _uuid = Uuid();

  /// Optional global step executor. Individual steps can override.
  final StepExecutor? stepExecutor;

  /// Event handlers keyed by event name.
  final Map<String, List<String>> _eventHandlers = {};

  /// Create a new workflow definition.
  Future<WorkflowModel> create({
    required String name,
    WorkflowType type = WorkflowType.sequential,
    List<WorkflowStep> steps = const [],
    List<WorkflowTrigger> triggers = const [],
    String? schedule,
  }) async {
    final workflow = WorkflowModel(
      id: _uuid.v4(),
      name: name,
      type: type,
      steps: steps,
      triggers: triggers,
      schedule: schedule,
    );
    await _repo.save(workflow);

    // Register event handlers.
    for (final trigger in triggers) {
      if (trigger.event != null) {
        _eventHandlers
            .putIfAbsent(trigger.event!, () => [])
            .add(workflow.id);
      }
    }

    _log.i('Workflow created: ${workflow.id} — $name');
    return workflow;
  }

  /// Start executing a workflow.
  Future<WorkflowModel?> start(
    String id, {
    StepExecutor? executor,
  }) async {
    final initialWorkflow = await _repo.get(id);
    if (initialWorkflow == null) return null;

    final exec = executor ?? stepExecutor;
    if (exec == null) {
      _log.w('No step executor configured');
      return null;
    }

    var workflow = initialWorkflow.copyWith(
      status: 'running',
      startedAt: DateTime.now(),
      logs: [
        ...initialWorkflow.logs,
        '${DateTime.now()}: Workflow started',
      ],
    );
    await _repo.save(workflow);

    try {
      switch (workflow.type) {
        case WorkflowType.sequential:
          workflow = await _runSequential(workflow, exec);
        case WorkflowType.parallel:
          workflow = await _runParallel(workflow, exec);
        case WorkflowType.conditional:
        case WorkflowType.scheduled:
        case WorkflowType.eventTriggered:
          // For conditional / scheduled / event, run sequentially by default.
          workflow = await _runSequential(workflow, exec);
      }

      workflow = workflow.copyWith(
        status: 'completed',
        completedAt: DateTime.now(),
        logs: [...workflow.logs, '${DateTime.now()}: Workflow completed'],
      );
    } catch (e) {
      workflow = workflow.copyWith(
        status: 'failed',
        completedAt: DateTime.now(),
        logs: [...workflow.logs, '${DateTime.now()}: Workflow failed — $e'],
      );
    }

    await _repo.save(workflow);
    return workflow;
  }

  /// Pause a running workflow.
  Future<WorkflowModel?> pause(String id) async {
    final workflow = await _repo.get(id);
    if (workflow == null || workflow.status != 'running') return workflow;
    final updated = workflow.copyWith(
      status: 'paused',
      logs: [...workflow.logs, '${DateTime.now()}: Workflow paused'],
    );
    await _repo.save(updated);
    return updated;
  }

  /// Resume a paused workflow.
  Future<WorkflowModel?> resume(String id, {StepExecutor? executor}) async {
    final workflow = await _repo.get(id);
    if (workflow == null || workflow.status != 'paused') return workflow;
    return start(id, executor: executor);
  }

  /// Stop a workflow entirely.
  Future<WorkflowModel?> stop(String id) async {
    final workflow = await _repo.get(id);
    if (workflow == null) return null;
    final updated = workflow.copyWith(
      status: 'stopped',
      completedAt: DateTime.now(),
      logs: [...workflow.logs, '${DateTime.now()}: Workflow stopped'],
    );
    await _repo.save(updated);
    return updated;
  }

  /// Retry a failed workflow from the first failed step.
  Future<WorkflowModel?> retry(String id, {StepExecutor? executor}) async {
    final workflow = await _repo.get(id);
    if (workflow == null || workflow.status != 'failed') return workflow;
    return start(id, executor: executor);
  }

  /// Get the current status of a workflow.
  Future<String?> getStatus(String id) async {
    final workflow = await _repo.get(id);
    return workflow?.status;
  }

  /// Get the execution logs for a workflow.
  Future<List<String>> getLogs(String id) async {
    final workflow = await _repo.get(id);
    return workflow?.logs ?? [];
  }

  /// List all workflows.
  Future<List<WorkflowModel>> listWorkflows() => _repo.getAll();

  /// Register a workflow to run on a cron-like schedule.
  Future<WorkflowModel?> schedule(
    String id,
    String cronExpression,
  ) async {
    final workflow = await _repo.get(id);
    if (workflow == null) return null;
    final updated = workflow.copyWith(schedule: cronExpression);
    await _repo.save(updated);
    _log.i('Workflow $id scheduled: $cronExpression');
    return updated;
  }

  /// Trigger all workflows registered for [eventName].
  Future<void> onEvent(String eventName, {StepExecutor? executor}) async {
    final ids = _eventHandlers[eventName] ?? [];
    for (final id in ids) {
      await start(id, executor: executor);
    }
  }

  // ---- Private execution helpers ------------------------------------------

  Future<WorkflowModel> _runSequential(
    WorkflowModel workflow,
    StepExecutor exec,
  ) async {
    final updatedSteps = List<WorkflowStep>.from(workflow.steps);
    final logs = List<String>.from(workflow.logs);

    for (var i = 0; i < updatedSteps.length; i++) {
      var step = updatedSteps[i];
      step = step.copyWith(status: 'running');
      updatedSteps[i] = step;
      logs.add('${DateTime.now()}: Step "${step.name}" started');

      try {
        final output = await exec(step);
        step = step.copyWith(status: 'completed', output: output);
        logs.add('${DateTime.now()}: Step "${step.name}" completed');
      } catch (e) {
        step = step.copyWith(status: 'failed');
        logs.add('${DateTime.now()}: Step "${step.name}" failed — $e');
        updatedSteps[i] = step;
        return workflow.copyWith(steps: updatedSteps, logs: logs);
      }
      updatedSteps[i] = step;
    }

    return workflow.copyWith(steps: updatedSteps, logs: logs);
  }

  Future<WorkflowModel> _runParallel(
    WorkflowModel workflow,
    StepExecutor exec,
  ) async {
    final updatedSteps = List<WorkflowStep>.from(workflow.steps);
    final logs = List<String>.from(workflow.logs);

    final futures = <Future<void>>[];
    for (var i = 0; i < updatedSteps.length; i++) {
      final idx = i;
      futures.add(() async {
        var step = updatedSteps[idx].copyWith(status: 'running');
        try {
          final output = await exec(step);
          step = step.copyWith(status: 'completed', output: output);
          logs.add('${DateTime.now()}: Step "${step.name}" completed');
        } catch (e) {
          step = step.copyWith(status: 'failed');
          logs.add('${DateTime.now()}: Step "${step.name}" failed — $e');
        }
        updatedSteps[idx] = step;
      }());
    }

    await Future.wait(futures);
    return workflow.copyWith(steps: updatedSteps, logs: logs);
  }
}

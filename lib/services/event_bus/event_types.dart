// ============================================================================
// TermuxForge — Event Bus Types
// All domain event classes used throughout the application.
// ============================================================================

import 'package:nexon/services/event_bus/event_bus.dart';

// ---------------------------------------------------------------------------
// Task Events
// ---------------------------------------------------------------------------

/// Emitted when a new task is created in the system.
class TaskCreated extends AppEvent {
  /// The unique identifier assigned to the new task.
  final String taskId;

  /// A human-readable description of the task.
  final String description;

  /// Optional priority level (1 = highest).
  final int priority;

  TaskCreated({
    required this.taskId,
    required this.description,
    this.priority = 3,
    required super.source,
  }) : super(type: 'TaskCreated');
}

/// Emitted when a task is assigned to a specific agent.
class TaskAssigned extends AppEvent {
  final String taskId;

  /// The agent ID the task was assigned to.
  final String agentId;

  TaskAssigned({
    required this.taskId,
    required this.agentId,
    required super.source,
  }) : super(type: 'TaskAssigned');
}

/// Emitted when an agent claims an available task.
class TaskClaimed extends AppEvent {
  final String taskId;
  final String agentId;

  TaskClaimed({
    required this.taskId,
    required this.agentId,
    required super.source,
  }) : super(type: 'TaskClaimed');
}

/// Emitted when a task reaches successful completion.
class TaskCompleted extends AppEvent {
  final String taskId;

  /// The serializable result of the completed task.
  final Map<String, dynamic>? result;

  TaskCompleted({
    required this.taskId,
    this.result,
    required super.source,
  }) : super(type: 'TaskCompleted');
}

/// Emitted when a task fails with an error.
class TaskFailed extends AppEvent {
  final String taskId;

  /// A human-readable error message.
  final String errorMessage;

  /// Whether the task is eligible for retry.
  final bool retryable;

  TaskFailed({
    required this.taskId,
    required this.errorMessage,
    this.retryable = true,
    required super.source,
  }) : super(type: 'TaskFailed');
}

// ---------------------------------------------------------------------------
// File Events
// ---------------------------------------------------------------------------

/// Emitted when a file is read from disk.
class FileRead extends AppEvent {
  /// The absolute path of the file that was read.
  final String filePath;

  /// The byte size of the file.
  final int sizeBytes;

  FileRead({
    required this.filePath,
    required this.sizeBytes,
    required super.source,
  }) : super(type: 'FileRead');
}

/// Emitted when a file is written to disk.
class FileWritten extends AppEvent {
  final String filePath;
  final int sizeBytes;

  /// Whether the file was newly created or overwritten.
  final bool isNew;

  FileWritten({
    required this.filePath,
    required this.sizeBytes,
    this.isNew = false,
    required super.source,
  }) : super(type: 'FileWritten');
}

// ---------------------------------------------------------------------------
// Shell Events
// ---------------------------------------------------------------------------

/// Emitted when a shell command execution is requested.
class ShellCommandRequested extends AppEvent {
  /// The command string to execute.
  final String command;

  /// Working directory for execution.
  final String? workingDirectory;

  /// The required permission level for this command.
  final int permissionLevel;

  ShellCommandRequested({
    required this.command,
    this.workingDirectory,
    this.permissionLevel = 3,
    required super.source,
  }) : super(type: 'ShellCommandRequested');
}

/// Emitted after a shell command has been executed.
class ShellCommandExecuted extends AppEvent {
  final String command;

  /// The process exit code.
  final int exitCode;

  /// Standard output content.
  final String stdout;

  /// Standard error content.
  final String stderr;

  /// How long the command took to execute.
  final Duration duration;

  ShellCommandExecuted({
    required this.command,
    required this.exitCode,
    this.stdout = '',
    this.stderr = '',
    required this.duration,
    required super.source,
  }) : super(type: 'ShellCommandExecuted');
}

// ---------------------------------------------------------------------------
// Memory Events
// ---------------------------------------------------------------------------

/// Emitted when the project/agent memory store is updated.
class MemoryUpdated extends AppEvent {
  /// The memory key that was updated.
  final String key;

  /// The namespace of the memory entry (e.g., 'project', 'agent', 'user').
  final String namespace;

  MemoryUpdated({
    required this.key,
    this.namespace = 'project',
    required super.source,
  }) : super(type: 'MemoryUpdated');
}

// ---------------------------------------------------------------------------
// MCP Events
// ---------------------------------------------------------------------------

/// Emitted when an MCP server health check completes.
class MCPServerChecked extends AppEvent {
  final String serverId;

  /// Whether the server responded successfully.
  final bool healthy;

  /// Response latency in milliseconds.
  final int latencyMs;

  MCPServerChecked({
    required this.serverId,
    required this.healthy,
    this.latencyMs = 0,
    required super.source,
  }) : super(type: 'MCPServerChecked');
}

/// Emitted when a new MCP server is registered.
class MCPServerAdded extends AppEvent {
  final String serverId;
  final String serverName;
  final String transport;

  MCPServerAdded({
    required this.serverId,
    required this.serverName,
    required this.transport,
    required super.source,
  }) : super(type: 'MCPServerAdded');
}

/// Emitted when an MCP server is removed from the registry.
class MCPServerRemoved extends AppEvent {
  final String serverId;

  MCPServerRemoved({
    required this.serverId,
    required super.source,
  }) : super(type: 'MCPServerRemoved');
}

/// Emitted when tools are discovered on an MCP server.
class MCPToolDiscovered extends AppEvent {
  final String serverId;

  /// The number of tools discovered.
  final int toolCount;

  /// Names of the discovered tools.
  final List<String> toolNames;

  MCPToolDiscovered({
    required this.serverId,
    required this.toolCount,
    required this.toolNames,
    required super.source,
  }) : super(type: 'MCPToolDiscovered');
}

/// Emitted when an MCP tool is invoked.
class MCPToolInvoked extends AppEvent {
  final String serverId;
  final String toolName;

  /// Whether the invocation succeeded.
  final bool success;

  /// Duration of the tool invocation.
  final Duration? duration;

  MCPToolInvoked({
    required this.serverId,
    required this.toolName,
    required this.success,
    this.duration,
    required super.source,
  }) : super(type: 'MCPToolInvoked');
}

// ---------------------------------------------------------------------------
// Review Events
// ---------------------------------------------------------------------------

/// Emitted when a code review is requested.
class ReviewRequested extends AppEvent {
  /// Identifier for the review subject (e.g., file path or PR id).
  final String subjectId;

  /// The type of review: 'code', 'security', 'architecture', etc.
  final String reviewType;

  ReviewRequested({
    required this.subjectId,
    this.reviewType = 'code',
    required super.source,
  }) : super(type: 'ReviewRequested');
}

/// Emitted when a code review is completed.
class ReviewCompleted extends AppEvent {
  final String subjectId;

  /// Number of issues found.
  final int issueCount;

  /// Severity of the most critical issue found.
  final String maxSeverity;

  ReviewCompleted({
    required this.subjectId,
    this.issueCount = 0,
    this.maxSeverity = 'none',
    required super.source,
  }) : super(type: 'ReviewCompleted');
}

// ---------------------------------------------------------------------------
// Tool Events
// ---------------------------------------------------------------------------

/// Emitted when any registered tool is invoked.
class ToolInvoked extends AppEvent {
  /// The tool's unique identifier.
  final String toolId;

  /// The parameters passed to the tool.
  final Map<String, dynamic> parameters;

  /// The agent that invoked the tool.
  final String? invokingAgentId;

  ToolInvoked({
    required this.toolId,
    this.parameters = const {},
    this.invokingAgentId,
    required super.source,
  }) : super(type: 'ToolInvoked');
}

/// Emitted when a tool returns its result.
class ToolResultReceived extends AppEvent {
  final String toolId;

  /// Whether the tool execution succeeded.
  final bool success;

  /// Duration of the tool execution.
  final Duration duration;

  ToolResultReceived({
    required this.toolId,
    required this.success,
    required this.duration,
    required super.source,
  }) : super(type: 'ToolResultReceived');
}

// ---------------------------------------------------------------------------
// Model Events
// ---------------------------------------------------------------------------

/// Emitted when a user or system selects a specific LLM model.
class ModelSelected extends AppEvent {
  /// The model identifier (e.g., 'gpt-4o', 'claude-sonnet-4-20250514').
  final String modelId;

  /// The provider that hosts this model.
  final String providerId;

  /// The task type this model was selected for.
  final String? taskType;

  ModelSelected({
    required this.modelId,
    required this.providerId,
    this.taskType,
    required super.source,
  }) : super(type: 'ModelSelected');
}

/// Emitted when models are compared in battle mode.
class ModelCompared extends AppEvent {
  /// The model identifiers being compared.
  final List<String> modelIds;

  /// The winning model, if any.
  final String? winnerId;

  /// The prompt used for comparison.
  final String prompt;

  ModelCompared({
    required this.modelIds,
    this.winnerId,
    required this.prompt,
    required super.source,
  }) : super(type: 'ModelCompared');
}

// ---------------------------------------------------------------------------
// Progress & Todo Events
// ---------------------------------------------------------------------------

/// Emitted to update UI progress indicators.
class ProgressUpdated extends AppEvent {
  /// A label for this progress (e.g., 'Build', 'Test Suite').
  final String label;

  /// Current progress value (0.0 to 1.0).
  final double progress;

  /// Optional message describing the current step.
  final String? message;

  ProgressUpdated({
    required this.label,
    required this.progress,
    this.message,
    required super.source,
  }) : super(type: 'ProgressUpdated');
}

/// Emitted when a todo/checklist item is updated.
class TodoUpdated extends AppEvent {
  /// The todo item identifier.
  final String todoId;

  /// Whether the item is now complete.
  final bool completed;

  /// The todo item text.
  final String text;

  TodoUpdated({
    required this.todoId,
    required this.completed,
    required this.text,
    required super.source,
  }) : super(type: 'TodoUpdated');
}

// ---------------------------------------------------------------------------
// Workflow Events
// ---------------------------------------------------------------------------

/// Emitted when a multi-step workflow begins.
class WorkflowStarted extends AppEvent {
  /// The workflow's unique identifier.
  final String workflowId;

  /// A human-readable name for the workflow.
  final String workflowName;

  /// Total number of steps in the workflow.
  final int totalSteps;

  WorkflowStarted({
    required this.workflowId,
    required this.workflowName,
    required this.totalSteps,
    required super.source,
  }) : super(type: 'WorkflowStarted');
}

/// Emitted when a workflow step completes successfully.
class WorkflowStepCompleted extends AppEvent {
  final String workflowId;

  /// Zero-indexed step number.
  final int stepIndex;

  /// Name of the completed step.
  final String stepName;

  WorkflowStepCompleted({
    required this.workflowId,
    required this.stepIndex,
    required this.stepName,
    required super.source,
  }) : super(type: 'WorkflowStepCompleted');
}

/// Emitted when a workflow step fails.
class WorkflowStepFailed extends AppEvent {
  final String workflowId;
  final int stepIndex;
  final String stepName;
  final String errorMessage;

  WorkflowStepFailed({
    required this.workflowId,
    required this.stepIndex,
    required this.stepName,
    required this.errorMessage,
    required super.source,
  }) : super(type: 'WorkflowStepFailed');
}

// ---------------------------------------------------------------------------
// Background Agent Events
// ---------------------------------------------------------------------------

/// Emitted when a background agent process starts.
class BackgroundAgentStarted extends AppEvent {
  final String agentId;
  final String agentName;

  /// The type of background work (e.g., 'linter', 'watcher', 'builder').
  final String agentType;

  BackgroundAgentStarted({
    required this.agentId,
    required this.agentName,
    required this.agentType,
    required super.source,
  }) : super(type: 'BackgroundAgentStarted');
}

/// Emitted when a background agent process stops.
class BackgroundAgentStopped extends AppEvent {
  final String agentId;

  /// Reason for stopping: 'completed', 'killed', 'error'.
  final String reason;

  BackgroundAgentStopped({
    required this.agentId,
    this.reason = 'completed',
    required super.source,
  }) : super(type: 'BackgroundAgentStopped');
}

// ---------------------------------------------------------------------------
// Artifact Events
// ---------------------------------------------------------------------------

/// Emitted when a build or generation artifact is created.
class ArtifactCreated extends AppEvent {
  /// The artifact's file path.
  final String artifactPath;

  /// The type of artifact: 'apk', 'aab', 'report', 'screenshot', etc.
  final String artifactType;

  /// Byte size of the artifact.
  final int sizeBytes;

  ArtifactCreated({
    required this.artifactPath,
    required this.artifactType,
    required this.sizeBytes,
    required super.source,
  }) : super(type: 'ArtifactCreated');
}

// ---------------------------------------------------------------------------
// Cost Events
// ---------------------------------------------------------------------------

/// Emitted when the running cost total changes.
class CostUpdated extends AppEvent {
  /// The provider whose cost changed.
  final String providerId;

  /// The cumulative cost in USD.
  final double totalCostUsd;

  /// Number of tokens consumed in this update.
  final int tokensUsed;

  CostUpdated({
    required this.providerId,
    required this.totalCostUsd,
    required this.tokensUsed,
    required super.source,
  }) : super(type: 'CostUpdated');
}

// ---------------------------------------------------------------------------
// Checkpoint Events
// ---------------------------------------------------------------------------

/// Emitted when a project checkpoint (snapshot) is created.
class CheckpointCreated extends AppEvent {
  /// The checkpoint identifier.
  final String checkpointId;

  /// Human-readable label for the checkpoint.
  final String label;

  CheckpointCreated({
    required this.checkpointId,
    required this.label,
    required super.source,
  }) : super(type: 'CheckpointCreated');
}

/// Emitted after a rollback to a prior checkpoint completes.
class RollbackCompleted extends AppEvent {
  /// The checkpoint identifier that was rolled back to.
  final String checkpointId;

  /// Number of changes that were reverted.
  final int changesReverted;

  RollbackCompleted({
    required this.checkpointId,
    this.changesReverted = 0,
    required super.source,
  }) : super(type: 'RollbackCompleted');
}

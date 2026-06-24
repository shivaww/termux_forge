// ============================================================================
// TermuxForge — Cost Service
// Tracks token usage, monetary cost, and generates usage dashboards across
// providers, projects, agents, tasks, workflows, and media jobs.
// ============================================================================

import 'dart:async';

import 'package:nexon/services/event_bus/event_bus.dart';
import 'package:nexon/services/event_bus/event_types.dart';

// ---------------------------------------------------------------------------
// Data Models
// ---------------------------------------------------------------------------

/// A single usage record for a billable event.
class UsageRecord {
  /// Unique record identifier.
  final String id;

  /// The LLM provider that processed the request.
  final String providerId;

  /// The model used.
  final String modelId;

  /// Number of input (prompt) tokens.
  final int inputTokens;

  /// Number of output (completion) tokens.
  final int outputTokens;

  /// Estimated cost in USD.
  final double costUsd;

  /// The agent that incurred this cost, if any.
  final String? agentId;

  /// The task ID this cost is associated with, if any.
  final String? taskId;

  /// The workflow ID, if part of a workflow.
  final String? workflowId;

  /// The project identifier.
  final String? projectId;

  /// The type of usage: 'chat', 'embedding', 'image', 'video'.
  final String usageType;

  /// When this usage occurred (UTC).
  final DateTime timestamp;

  UsageRecord({
    required this.id,
    required this.providerId,
    required this.modelId,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.costUsd = 0.0,
    this.agentId,
    this.taskId,
    this.workflowId,
    this.projectId,
    this.usageType = 'chat',
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().toUtc();

  /// Total tokens (input + output).
  int get totalTokens => inputTokens + outputTokens;

  /// Converts to a JSON-serializable map.
  Map<String, dynamic> toJson() => {
        'id': id,
        'providerId': providerId,
        'modelId': modelId,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'costUsd': costUsd,
        'agentId': agentId,
        'taskId': taskId,
        'workflowId': workflowId,
        'projectId': projectId,
        'usageType': usageType,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Aggregated cost summary for a dashboard view.
class CostSummary {
  /// Total cost in USD.
  final double totalCostUsd;

  /// Total tokens consumed.
  final int totalTokens;

  /// Total input tokens.
  final int totalInputTokens;

  /// Total output tokens.
  final int totalOutputTokens;

  /// Number of requests made.
  final int requestCount;

  /// Cost broken down by provider.
  final Map<String, double> costByProvider;

  /// Cost broken down by model.
  final Map<String, double> costByModel;

  /// Cost broken down by agent.
  final Map<String, double> costByAgent;

  /// Cost broken down by usage type.
  final Map<String, double> costByType;

  const CostSummary({
    this.totalCostUsd = 0.0,
    this.totalTokens = 0,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    this.requestCount = 0,
    this.costByProvider = const {},
    this.costByModel = const {},
    this.costByAgent = const {},
    this.costByType = const {},
  });

  Map<String, dynamic> toJson() => {
        'totalCostUsd': totalCostUsd,
        'totalTokens': totalTokens,
        'totalInputTokens': totalInputTokens,
        'totalOutputTokens': totalOutputTokens,
        'requestCount': requestCount,
        'costByProvider': costByProvider,
        'costByModel': costByModel,
        'costByAgent': costByAgent,
        'costByType': costByType,
      };
}

/// A cost warning threshold.
class CostThreshold {
  /// The threshold amount in USD.
  final double amountUsd;

  /// A label for this threshold (e.g., 'daily', 'session', 'project').
  final String label;

  /// Whether this threshold has been breached.
  bool breached;

  /// When the threshold was last breached (UTC).
  DateTime? breachedAt;

  CostThreshold({
    required this.amountUsd,
    required this.label,
    this.breached = false,
    this.breachedAt,
  });
}

// ---------------------------------------------------------------------------
// Cost Service
// ---------------------------------------------------------------------------

/// Tracks all token and cost usage across the application.
///
/// Listens to [CostUpdated] events from the [EventBus] and accumulates
/// usage records. Provides dashboard-style summaries and warning thresholds.
///
/// ## Example
///
/// ```dart
/// final costService = CostService.instance;
///
/// costService.addThreshold(CostThreshold(
///   amountUsd: 5.0,
///   label: 'session',
/// ));
///
/// costService.recordUsage(UsageRecord(
///   id: 'usage-1',
///   providerId: 'openai',
///   modelId: 'gpt-4o',
///   inputTokens: 1500,
///   outputTokens: 500,
///   costUsd: 0.035,
/// ));
///
/// final dashboard = costService.getDashboard();
/// print('Total cost: \$${dashboard.totalCostUsd}');
/// ```
class CostService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  CostService._internal() {
    _listenToEvents();
  }

  /// The global [CostService] instance.
  static final CostService instance = CostService._internal();

  /// Factory constructor that returns the singleton [instance].
  factory CostService() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// All usage records.
  final List<UsageRecord> _records = [];

  /// Maximum records retained in memory.
  static const int _maxRecords = 10000;

  /// Cost warning thresholds.
  final List<CostThreshold> _thresholds = [];

  /// Event bus reference.
  final EventBus _eventBus = EventBus.instance;

  /// Event bus subscription ID.
  String? _eventSubId;

  /// Stream controller for threshold breach notifications.
  final StreamController<CostThreshold> _thresholdController =
      StreamController<CostThreshold>.broadcast();

  // ---------------------------------------------------------------------------
  // Event Listening
  // ---------------------------------------------------------------------------

  /// Subscribes to [CostUpdated] events and auto-records usage.
  void _listenToEvents() {
    _eventSubId = _eventBus.subscribe<CostUpdated>((event) {
      recordUsage(UsageRecord(
        id: 'auto_${DateTime.now().millisecondsSinceEpoch}',
        providerId: event.providerId,
        modelId: 'unknown', // CostUpdated doesn't carry model; callers should use recordUsage directly for precise tracking.
        inputTokens: event.tokensUsed,
        outputTokens: 0,
        costUsd: event.totalCostUsd,
      ));
    });
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------

  /// Records a [UsageRecord] and checks thresholds.
  void recordUsage(UsageRecord record) {
    _records.add(record);

    // Enforce bounded history.
    if (_records.length > _maxRecords) {
      _records.removeAt(0);
    }

    // Check thresholds.
    _checkThresholds();

    // TODO: Persist to Isar for long-term analytics.
  }

  // ---------------------------------------------------------------------------
  // Dashboard
  // ---------------------------------------------------------------------------

  /// Generates a [CostSummary] aggregating all recorded usage.
  ///
  /// Optionally filter by [providerId], [agentId], [taskId], [projectId],
  /// or a [since] timestamp.
  CostSummary getDashboard({
    String? providerId,
    String? agentId,
    String? taskId,
    String? projectId,
    DateTime? since,
  }) {
    Iterable<UsageRecord> filtered = _records;

    if (providerId != null) {
      filtered = filtered.where((r) => r.providerId == providerId);
    }
    if (agentId != null) {
      filtered = filtered.where((r) => r.agentId == agentId);
    }
    if (taskId != null) {
      filtered = filtered.where((r) => r.taskId == taskId);
    }
    if (projectId != null) {
      filtered = filtered.where((r) => r.projectId == projectId);
    }
    if (since != null) {
      filtered = filtered.where((r) => r.timestamp.isAfter(since));
    }

    final records = filtered.toList();

    double totalCost = 0;
    int totalInput = 0;
    int totalOutput = 0;
    final byProvider = <String, double>{};
    final byModel = <String, double>{};
    final byAgent = <String, double>{};
    final byType = <String, double>{};

    for (final r in records) {
      totalCost += r.costUsd;
      totalInput += r.inputTokens;
      totalOutput += r.outputTokens;
      byProvider[r.providerId] = (byProvider[r.providerId] ?? 0) + r.costUsd;
      byModel[r.modelId] = (byModel[r.modelId] ?? 0) + r.costUsd;
      if (r.agentId != null) {
        byAgent[r.agentId!] = (byAgent[r.agentId!] ?? 0) + r.costUsd;
      }
      byType[r.usageType] = (byType[r.usageType] ?? 0) + r.costUsd;
    }

    return CostSummary(
      totalCostUsd: totalCost,
      totalTokens: totalInput + totalOutput,
      totalInputTokens: totalInput,
      totalOutputTokens: totalOutput,
      requestCount: records.length,
      costByProvider: byProvider,
      costByModel: byModel,
      costByAgent: byAgent,
      costByType: byType,
    );
  }

  // ---------------------------------------------------------------------------
  // Thresholds
  // ---------------------------------------------------------------------------

  /// Adds a cost warning threshold.
  void addThreshold(CostThreshold threshold) {
    _thresholds.add(threshold);
  }

  /// Removes a threshold by [label].
  bool removeThreshold(String label) {
    return _thresholds.removeWhere((t) => t.label == label) > 0;
  }

  /// Returns all registered thresholds.
  List<CostThreshold> get thresholds => List.unmodifiable(_thresholds);

  /// A broadcast stream that emits when a threshold is breached.
  Stream<CostThreshold> get thresholdBreaches => _thresholdController.stream;

  void _checkThresholds() {
    final totalCost = _records.fold<double>(0, (sum, r) => sum + r.costUsd);

    for (final threshold in _thresholds) {
      if (!threshold.breached && totalCost >= threshold.amountUsd) {
        threshold.breached = true;
        threshold.breachedAt = DateTime.now().toUtc();

        if (!_thresholdController.isClosed) {
          _thresholdController.add(threshold);
        }

        // TODO: Integrate with notification service to alert user.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Returns all usage records.
  List<UsageRecord> getRecords({int? limit}) {
    if (limit != null && _records.length > limit) {
      return _records.sublist(_records.length - limit);
    }
    return List.unmodifiable(_records);
  }

  /// Total cost across all records.
  double get totalCostUsd =>
      _records.fold<double>(0, (sum, r) => sum + r.costUsd);

  /// Total tokens across all records.
  int get totalTokens => _records.fold<int>(0, (sum, r) => sum + r.totalTokens);

  /// Number of recorded usage events.
  int get recordCount => _records.length;

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /// Clears all records and resets thresholds.
  void reset() {
    _records.clear();
    for (final t in _thresholds) {
      t.breached = false;
      t.breachedAt = null;
    }
    _thresholds.clear();
  }

  /// Releases resources. Call only during app shutdown.
  Future<void> dispose() async {
    if (_eventSubId != null) {
      _eventBus.unsubscribe(_eventSubId!);
    }
    await _thresholdController.close();
  }
}

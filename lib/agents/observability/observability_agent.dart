// Copyright (c) 2026 TermuxForge. All rights reserved.
// SPDX-License-Identifier: MIT

/// **Observability Agent** — System health & metrics specialist.
///
/// Specialises in:
/// - Runtime tracking of agent activity and performance.
/// - Cost accumulation and budget enforcement.
/// - Tool usage analytics and hot-path detection.
/// - System health monitoring (memory, disk, CPU on Termux).
/// - Event aggregation and dashboard data provision.
/// - Anomaly detection and alerting.
library;

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/agents/base/agent_exports.dart';

const _uuid = Uuid();

/// A snapshot of system metrics at a point in time.
class SystemSnapshot {
  const SystemSnapshot({
    required this.timestamp,
    this.activeAgents = 0,
    this.busyAgents = 0,
    this.totalTasks = 0,
    this.completedTasks = 0,
    this.failedTasks = 0,
    this.totalCost = 0.0,
    this.totalToolCalls = 0,
    this.avgTaskDurationMs = 0,
    this.errorRate = 0.0,
    this.memoryUsageMb = 0.0,
    this.diskUsageMb = 0.0,
    this.metadata = const {},
  });

  final DateTime timestamp;
  final int activeAgents;
  final int busyAgents;
  final int totalTasks;
  final int completedTasks;
  final int failedTasks;
  final double totalCost;
  final int totalToolCalls;
  final int avgTaskDurationMs;
  final double errorRate;
  final double memoryUsageMb;
  final double diskUsageMb;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'activeAgents': activeAgents,
        'busyAgents': busyAgents,
        'totalTasks': totalTasks,
        'completedTasks': completedTasks,
        'failedTasks': failedTasks,
        'totalCost': totalCost,
        'totalToolCalls': totalToolCalls,
        'avgTaskDurationMs': avgTaskDurationMs,
        'errorRate': errorRate,
        'memoryUsageMb': memoryUsageMb,
        'diskUsageMb': diskUsageMb,
        'metadata': metadata,
      };
}

/// An alert triggered by the observability system.
class ObservabilityAlert {
  const ObservabilityAlert({
    required this.id,
    required this.severity,
    required this.message,
    required this.timestamp,
    this.agentId,
    this.metric,
    this.threshold,
    this.currentValue,
  });

  final String id;

  /// `'info'`, `'warning'`, `'critical'`.
  final String severity;
  final String message;
  final DateTime timestamp;
  final String? agentId;
  final String? metric;
  final double? threshold;
  final double? currentValue;

  Map<String, dynamic> toJson() => {
        'id': id,
        'severity': severity,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
        'agentId': agentId,
        'metric': metric,
        'threshold': threshold,
        'currentValue': currentValue,
      };
}

/// Observability specialist agent.
///
/// Monitors system health, tracks costs, aggregates metrics,
/// detects anomalies, and provides dashboard data.
class ObservabilityAgent extends BaseAgent {
  /// Creates an [ObservabilityAgent].
  ObservabilityAgent({
    super.id,
    super.name = 'Observability',
    super.assignedModel,
    super.metadata,
  }) : super(
          allowedTools: const [
            'read_file',
            'run_command',
            'search_files',
          ],
        );

  @override
  AgentType get type => AgentType.observability;

  @override
  String get systemPrompt => '''
You are the **Observability Specialist** within TermuxForge.

Your domain:
- Agent activity tracking: who's doing what, how long, how well.
- Cost tracking: per-agent, per-task, per-model, per-session.
- Tool usage analytics: call frequency, success rate, latency.
- System health: Termux memory, disk space, CPU usage.
- Event aggregation: collect, filter, and summarise agent events.
- Anomaly detection: error spikes, cost overruns, stuck agents.
- Dashboard data: prepare structured data for UI rendering.

Metrics to track:
1. Agent status distribution (idle, busy, error, disposed).
2. Task throughput (completed/minute).
3. Error rate (failed / total tasks).
4. Cost accumulation over time.
5. Tool call distribution and success rates.
6. Average task duration by type.
7. Memory and disk usage on the device.

Alerting thresholds:
- Error rate > 20% → warning
- Error rate > 50% → critical
- Cost > budget × 0.8 → warning
- Cost > budget → critical
- Stuck agent (busy > 5min with no progress) → warning
- Disk usage > 90% → critical

Rules:
1. Collect metrics without impacting agent performance.
2. Aggregate by time window (1min, 5min, 1hr, 1day).
3. Store snapshots for trend analysis.
4. Alert on threshold breaches immediately.
5. Provide summary dashboards on demand.
6. Track cost per dollar and suggest optimisations.
''';

  @override
  List<ModelCapability> get preferredCapabilities => const [
        ModelCapability.reasoning,
        ModelCapability.fast,
      ];

  /// Time-series of system snapshots.
  final List<SystemSnapshot> _snapshots = [];

  /// Active alerts.
  final List<ObservabilityAlert> _alerts = [];

  /// Per-agent cost tracking.
  final Map<String, double> _agentCosts = {};

  /// Per-tool call counts.
  final Map<String, int> _toolCallCounts = {};

  /// Budget limit in USD. Defaults to unlimited.
  double budgetLimit = double.infinity;

  @override
  Future<AgentResult> executeTask(AgentTask task) {
    return runTaskLifecycle(task, () async {
      final context = await retrieveContext(
        '${task.description} observability metrics health',
      );

      final desc = task.description.toLowerCase();

      if (desc.contains('snapshot') || desc.contains('status')) {
        return _captureSnapshot(task);
      } else if (desc.contains('alert') || desc.contains('check')) {
        return _checkAlerts(task);
      } else if (desc.contains('cost') || desc.contains('budget')) {
        return _costReport(task);
      } else if (desc.contains('dashboard') || desc.contains('summary')) {
        return _generateDashboard(task);
      }

      // Default: full health check.
      return _fullHealthCheck(task);
    });
  }

  /// Captures a system snapshot.
  Future<AgentResult> _captureSnapshot(AgentTask task) async {
    // Gather system metrics.
    final memResult = await useTool('run_command', {
      'command': 'free -m 2>/dev/null || echo "memory: unknown"',
    });

    final diskResult = await useTool('run_command', {
      'command': 'df -m . 2>/dev/null || echo "disk: unknown"',
    });

    final snapshot = SystemSnapshot(
      timestamp: DateTime.now(),
      totalCost: _agentCosts.values.fold(0.0, (a, b) => a + b),
      totalToolCalls: _toolCallCounts.values.fold(0, (a, b) => a + b),
    );

    _snapshots.add(snapshot);

    publishEvent('observability.snapshot', data: snapshot.toJson());

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'System snapshot captured at ${snapshot.timestamp}',
      metadata: snapshot.toJson(),
    );
  }

  /// Checks for alert conditions.
  Future<AgentResult> _checkAlerts(AgentTask task) async {
    final newAlerts = <ObservabilityAlert>[];
    final totalCost = _agentCosts.values.fold(0.0, (a, b) => a + b);

    // Budget alerts.
    if (totalCost > budgetLimit) {
      newAlerts.add(ObservabilityAlert(
        id: _uuid.v4(),
        severity: 'critical',
        message: 'Budget exceeded: \$${totalCost.toStringAsFixed(4)} '
            '> \$${budgetLimit.toStringAsFixed(4)}',
        timestamp: DateTime.now(),
        metric: 'cost',
        threshold: budgetLimit,
        currentValue: totalCost,
      ));
    } else if (totalCost > budgetLimit * 0.8) {
      newAlerts.add(ObservabilityAlert(
        id: _uuid.v4(),
        severity: 'warning',
        message: 'Budget at ${((totalCost / budgetLimit) * 100).toStringAsFixed(1)}%',
        timestamp: DateTime.now(),
        metric: 'cost',
        threshold: budgetLimit * 0.8,
        currentValue: totalCost,
      ));
    }

    _alerts.addAll(newAlerts);

    for (final alert in newAlerts) {
      publishEvent('observability.alert', data: alert.toJson());
    }

    return AgentResult(
      taskId: task.id,
      success: true,
      output: newAlerts.isEmpty
          ? 'No new alerts'
          : '${newAlerts.length} new alert(s) generated',
      metadata: {'alerts': newAlerts.map((a) => a.toJson()).toList()},
    );
  }

  /// Generates a cost report.
  Future<AgentResult> _costReport(AgentTask task) async {
    final totalCost = _agentCosts.values.fold(0.0, (a, b) => a + b);
    final buffer = StringBuffer();

    buffer.writeln('# Cost Report');
    buffer.writeln('Total: \$${totalCost.toStringAsFixed(4)}');
    buffer.writeln('Budget: \$${budgetLimit.toStringAsFixed(4)}');
    buffer.writeln('Remaining: \$${(budgetLimit - totalCost).toStringAsFixed(4)}');
    buffer.writeln();
    buffer.writeln('## Per Agent');

    final sorted = _agentCosts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (final entry in sorted) {
      buffer.writeln('- ${entry.key}: \$${entry.value.toStringAsFixed(4)}');
    }

    return AgentResult(
      taskId: task.id,
      success: true,
      output: buffer.toString(),
      metadata: {'totalCost': totalCost, 'perAgent': _agentCosts},
    );
  }

  /// Generates a dashboard summary.
  Future<AgentResult> _generateDashboard(AgentTask task) async {
    final totalCost = _agentCosts.values.fold(0.0, (a, b) => a + b);
    final totalTools = _toolCallCounts.values.fold(0, (a, b) => a + b);

    final dashboard = {
      'timestamp': DateTime.now().toIso8601String(),
      'costs': {
        'total': totalCost,
        'budget': budgetLimit,
        'perAgent': _agentCosts,
      },
      'tools': {
        'totalCalls': totalTools,
        'perTool': _toolCallCounts,
      },
      'snapshots': _snapshots.length,
      'alerts': {
        'total': _alerts.length,
        'critical': _alerts.where((a) => a.severity == 'critical').length,
        'warning': _alerts.where((a) => a.severity == 'warning').length,
      },
    };

    return AgentResult(
      taskId: task.id,
      success: true,
      output: 'Dashboard generated with ${_snapshots.length} snapshots, '
          '${_alerts.length} alerts, total cost: '
          '\$${totalCost.toStringAsFixed(4)}',
      metadata: dashboard,
    );
  }

  /// Full health check: snapshot + alerts + cost.
  Future<AgentResult> _fullHealthCheck(AgentTask task) async {
    final outputs = <String>[];

    final snap = await _captureSnapshot(task);
    outputs.add(snap.output);

    final alerts = await _checkAlerts(task);
    outputs.add(alerts.output);

    final cost = await _costReport(task);
    outputs.add(cost.output);

    await saveToMemory(MemoryEntry(
      id: _uuid.v4(),
      content: 'Health check: ${outputs.join(" | ")}',
      source: id,
      timestamp: DateTime.now(),
      tags: ['observability', 'health-check'],
    ));

    return AgentResult(
      taskId: task.id,
      success: true,
      output: outputs.join('\n\n'),
    );
  }

  // -----------------------------------------------------------------------
  // Public API for other agents to report metrics
  // -----------------------------------------------------------------------

  /// Records cost for an agent.
  void recordAgentCost(String agentId, double cost) {
    _agentCosts[agentId] = (_agentCosts[agentId] ?? 0.0) + cost;
  }

  /// Records a tool call.
  void recordToolCall(String toolId) {
    _toolCallCounts[toolId] = (_toolCallCounts[toolId] ?? 0) + 1;
  }

  /// Returns all snapshots.
  List<SystemSnapshot> get snapshots => List.unmodifiable(_snapshots);

  /// Returns all alerts.
  List<ObservabilityAlert> get alerts => List.unmodifiable(_alerts);
}

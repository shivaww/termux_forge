// ============================================================================
// TermuxForge — Permission Service
// Gates all tool and command execution behind a permission approval system.
// ============================================================================

import 'dart:async';

import 'package:uuid/uuid.dart';

import 'package:nexon/services/permission/permission_types.dart';
import 'package:nexon/services/event_bus/event_bus.dart';

/// Gates tool execution through a multi-level permission approval system.
///
/// The service automatically approves low-risk actions (levels 0–1 by
/// default) and requires explicit user approval for higher levels. Every
/// decision is logged in an audit trail.
///
/// ## Flow
///
/// 1. A tool or agent calls [requestPermission] with the action details.
/// 2. If the action's level ≤ [_autoApproveLevel], it is auto-approved.
/// 3. Otherwise the request is queued as [PermissionDecision.pending].
/// 4. The UI presents the request; the user calls [approvePermission] or
///    [denyPermission].
/// 5. The waiting [Completer] resolves and the caller proceeds or aborts.
///
/// ```dart
/// final service = PermissionService.instance;
/// final granted = await service.requestPermission(PermissionRequest(
///   id: 'req-1',
///   toolId: 'execute_shell',
///   level: PermissionLevel.dangerous,
///   description: 'Run: npm install',
///   commandPreview: 'npm install',
///   requester: 'agent_abc',
/// ));
/// if (granted) { /* execute */ }
/// ```
class PermissionService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  PermissionService._internal();

  /// The global [PermissionService] instance.
  static final PermissionService instance = PermissionService._internal();

  /// Factory constructor that returns the singleton [instance].
  factory PermissionService() => instance;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  /// The maximum level that is auto-approved without user interaction.
  int _autoApproveLevel = 1;

  /// Pending requests waiting for user decision, keyed by request ID.
  final Map<String, _PendingRequest> _pending = {};

  /// Complete audit log of all permission decisions.
  final List<PermissionAuditEntry> _auditLog = [];

  /// Event bus reference for publishing events.
  // ignore: unused_field
  final EventBus _eventBus = EventBus.instance;

  /// UUID generator.
  static const _uuid = Uuid();

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Sets the auto-approve threshold.
  ///
  /// Actions with [PermissionLevel.level] ≤ [level] are approved
  /// automatically. Default is 1 (low risk).
  ///
  /// Throws [RangeError] if [level] is outside 0–8.
  void setAutoApproveLevel(int level) {
    if (level < 0 || level > 8) {
      throw RangeError.range(level, 0, 8, 'autoApproveLevel');
    }
    _autoApproveLevel = level;
  }

  /// Returns the current auto-approve level.
  int get autoApproveLevel => _autoApproveLevel;

  // ---------------------------------------------------------------------------
  // Request / Approve / Deny
  // ---------------------------------------------------------------------------

  /// Requests permission for the given action.
  ///
  /// Returns a [Future] that completes with `true` if approved, `false` if
  /// denied. For auto-approved actions the future resolves immediately.
  Future<bool> requestPermission(PermissionRequest request) async {
    // Auto-approve low-risk actions.
    if (isAutoApproved(request.level)) {
      request.decision = PermissionDecision.approved;
      request.decidedAt = DateTime.now().toUtc();
      request.decidedBy = 'auto';
      _log(request, PermissionDecision.approved);
      return true;
    }

    // Queue for user decision.
    final completer = Completer<bool>();
    _pending[request.id] = _PendingRequest(
      request: request,
      completer: completer,
    );

    // TODO: Publish a UI notification event so the permission dialog
    // can be shown to the user. E.g.:
    // _eventBus.publish(PermissionRequested(request: request, source: 'PermissionService'));

    return completer.future;
  }

  /// Creates and submits a permission request in one call.
  ///
  /// Convenience wrapper that generates the request ID automatically.
  Future<bool> requestToolPermission({
    required String toolId,
    required int level,
    required String description,
    String? commandPreview,
    required String requester,
  }) {
    final request = PermissionRequest(
      id: _uuid.v4(),
      toolId: toolId,
      level: PermissionLevel.fromLevel(level),
      description: description,
      commandPreview: commandPreview,
      requester: requester,
    );
    return requestPermission(request);
  }

  /// Approves the pending request identified by [requestId].
  ///
  /// The waiting future resolves with `true`.
  /// Returns `false` if no such pending request exists.
  bool approvePermission(String requestId, {String decidedBy = 'user'}) {
    final pending = _pending.remove(requestId);
    if (pending == null) return false;

    pending.request.decision = PermissionDecision.approved;
    pending.request.decidedAt = DateTime.now().toUtc();
    pending.request.decidedBy = decidedBy;
    _log(pending.request, PermissionDecision.approved);
    pending.completer.complete(true);
    return true;
  }

  /// Denies the pending request identified by [requestId].
  ///
  /// The waiting future resolves with `false`.
  /// Returns `false` if no such pending request exists.
  bool denyPermission(String requestId, {String decidedBy = 'user'}) {
    final pending = _pending.remove(requestId);
    if (pending == null) return false;

    pending.request.decision = PermissionDecision.denied;
    pending.request.decidedAt = DateTime.now().toUtc();
    pending.request.decidedBy = decidedBy;
    _log(pending.request, PermissionDecision.denied);
    pending.completer.complete(false);
    return true;
  }

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Whether the given [level] is auto-approved under current settings.
  bool isAutoApproved(PermissionLevel level) {
    return level.level <= _autoApproveLevel;
  }

  /// Returns all pending permission requests.
  List<PermissionRequest> getPendingRequests() {
    return _pending.values.map((p) => p.request).toList();
  }

  /// Returns the full audit log.
  ///
  /// Optionally filter by [toolId] or limit to the last [limit] entries.
  List<PermissionAuditEntry> getApprovalHistory({
    String? toolId,
    int? limit,
  }) {
    Iterable<PermissionAuditEntry> results = _auditLog;
    if (toolId != null) {
      results = results.where((e) => e.request.toolId == toolId);
    }
    final list = results.toList();
    if (limit != null && list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return List.unmodifiable(list);
  }

  /// Number of entries in the audit log.
  int get auditLogLength => _auditLog.length;

  /// Number of currently pending requests.
  int get pendingCount => _pending.length;

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  void _log(PermissionRequest request, PermissionDecision decision) {
    _auditLog.add(PermissionAuditEntry(
      request: request,
      decision: decision,
      timestamp: DateTime.now().toUtc(),
    ));

    // TODO: Persist audit log to memory service / Isar for long-term storage.
  }

  /// Resets all internal state. Intended for testing only.
  void reset() {
    // Deny all pending requests so their futures resolve.
    for (final entry in _pending.values) {
      entry.completer.complete(false);
    }
    _pending.clear();
    _auditLog.clear();
    _autoApproveLevel = 1;
  }
}

/// Internal wrapper that pairs a request with its [Completer].
class _PendingRequest {
  final PermissionRequest request;
  final Completer<bool> completer;

  const _PendingRequest({required this.request, required this.completer});
}

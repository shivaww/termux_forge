/// TermuxForge — Todo Dashboard Screen
///
/// Todo list with progress bars, completion percentages, priority
/// color coding, status/agent filters, timeline view, and
/// create/edit todo dialogs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/forge_app_bar.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';
import 'package:nexon/presentation/widgets/progress_indicator.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// Priority levels for todos.
enum _Priority { low, medium, high, critical }

/// A demo todo item.
class _TodoItem {
  _TodoItem({
    required this.title,
    required this.priority,
    this.description,
    this.assignedAgent,
    this.subtasks = const [],
    this.completedSubtasks = 0,
    this.status = 'pending',
    this.isBlocked = false,
  });

  final String title;
  final String? description;
  final _Priority priority;
  final String? assignedAgent;
  final List<String> subtasks;
  final int completedSubtasks;
  String status; // pending, in_progress, completed, blocked
  final bool isBlocked;

  double get progress =>
      subtasks.isEmpty ? 0 : completedSubtasks / subtasks.length;

  Color get priorityColor => switch (priority) {
    _Priority.low => AppColors.success,
    _Priority.medium => AppColors.warning,
    _Priority.high => AppColors.permissionModerate,
    _Priority.critical => AppColors.error,
  };

  String get priorityLabel => switch (priority) {
    _Priority.low => 'Low',
    _Priority.medium => 'Medium',
    _Priority.high => 'High',
    _Priority.critical => 'Critical',
  };
}

/// The todo dashboard screen.
class TodoDashboardScreen extends StatefulWidget {
  const TodoDashboardScreen({super.key});

  @override
  State<TodoDashboardScreen> createState() => _TodoDashboardScreenState();
}

class _TodoDashboardScreenState extends State<TodoDashboardScreen> {
  String _statusFilter = 'all';
  String _agentFilter = 'all';

  final List<_TodoItem> _todos = [
    _TodoItem(
      title: 'Set up project architecture',
      priority: _Priority.critical,
      assignedAgent: 'architect',
      subtasks: [
        'Define folder structure',
        'Create base classes',
        'Set up dependency injection',
        'Configure routing',
      ],
      completedSubtasks: 4,
      status: 'completed',
    ),
    _TodoItem(
      title: 'Implement authentication flow',
      priority: _Priority.high,
      assignedAgent: 'coder',
      subtasks: [
        'Login screen UI',
        'Register screen UI',
        'Auth service',
        'Token management',
        'Biometric auth',
      ],
      completedSubtasks: 3,
      status: 'in_progress',
    ),
    _TodoItem(
      title: 'Design database schema',
      priority: _Priority.high,
      assignedAgent: 'architect',
      subtasks: [
        'User entity',
        'Chat entity',
        'Project entity',
        'Migration strategy',
      ],
      completedSubtasks: 2,
      status: 'in_progress',
    ),
    _TodoItem(
      title: 'Write unit tests for auth',
      priority: _Priority.medium,
      assignedAgent: 'tester',
      subtasks: ['Login tests', 'Register tests', 'Token tests'],
      completedSubtasks: 0,
      status: 'pending',
    ),
    _TodoItem(
      title: 'Security audit on auth flow',
      priority: _Priority.high,
      assignedAgent: 'security',
      subtasks: ['Input validation', 'Token security', 'Rate limiting'],
      completedSubtasks: 0,
      status: 'blocked',
      isBlocked: true,
    ),
    _TodoItem(
      title: 'Create API documentation',
      priority: _Priority.low,
      assignedAgent: 'documenter',
      subtasks: ['Auth API docs', 'Chat API docs'],
      completedSubtasks: 0,
      status: 'pending',
    ),
  ];

  List<_TodoItem> get _filteredTodos {
    return _todos.where((t) {
      if (_statusFilter != 'all' && t.status != _statusFilter) return false;
      if (_agentFilter != 'all' && t.assignedAgent != _agentFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  int get _totalSubtasks =>
      _todos.fold(0, (sum, t) => sum + t.subtasks.length);

  int get _completedSubtasks =>
      _todos.fold(0, (sum, t) => sum + t.completedSubtasks);

  double get _overallProgress =>
      _totalSubtasks == 0 ? 0 : _completedSubtasks / _totalSubtasks;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Todo Dashboard',
        showBackButton: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _showCreateDialog(context),
            tooltip: 'New Todo',
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Overall Progress ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary,
              border: Border(
                bottom: BorderSide(color: AppColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                ForgeCircularProgress(
                  progress: _overallProgress,
                  size: 52,
                  strokeWidth: 5,
                  color: AppColors.accentBlue,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Overall Progress',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_completedSubtasks / $_totalSubtasks subtasks completed',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                // Stats.
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _MiniStat(
                      label: 'Done',
                      count: _todos.where((t) => t.status == 'completed').length,
                      color: AppColors.success,
                    ),
                    _MiniStat(
                      label: 'Active',
                      count: _todos.where((t) => t.status == 'in_progress').length,
                      color: AppColors.accentBlue,
                    ),
                    _MiniStat(
                      label: 'Blocked',
                      count: _todos.where((t) => t.isBlocked).length,
                      color: AppColors.error,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Filters ──
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  isActive: _statusFilter == 'all',
                  onTap: () => setState(() => _statusFilter = 'all'),
                ),
                _FilterChip(
                  label: 'In Progress',
                  isActive: _statusFilter == 'in_progress',
                  color: AppColors.accentBlue,
                  onTap: () => setState(() => _statusFilter = 'in_progress'),
                ),
                _FilterChip(
                  label: 'Pending',
                  isActive: _statusFilter == 'pending',
                  color: AppColors.warning,
                  onTap: () => setState(() => _statusFilter = 'pending'),
                ),
                _FilterChip(
                  label: 'Completed',
                  isActive: _statusFilter == 'completed',
                  color: AppColors.success,
                  onTap: () => setState(() => _statusFilter = 'completed'),
                ),
                _FilterChip(
                  label: 'Blocked',
                  isActive: _statusFilter == 'blocked',
                  color: AppColors.error,
                  onTap: () => setState(() => _statusFilter = 'blocked'),
                ),
              ],
            ),
          ),

          // ── Todo list ──
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _filteredTodos.length,
              itemBuilder: (_, i) {
                final todo = _filteredTodos[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _TodoCard(todo: todo),
                ).animate().fadeIn(
                  delay: Duration(milliseconds: i * 50),
                  duration: 200.ms,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Todo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TextField(
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'Enter todo title...',
              ),
            ),
            const SizedBox(height: 12),
            const TextField(
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Optional description...',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<_Priority>(
              value: _Priority.medium,
              decoration: const InputDecoration(labelText: 'Priority'),
              items: _Priority.values
                  .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.name),
                      ))
                  .toList(),
              onChanged: (_) {},
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}

class _TodoCard extends StatelessWidget {
  const _TodoCard({required this.todo});

  final _TodoItem todo;

  String get _statusLabel => switch (todo.status) {
    'completed' => 'Done',
    'in_progress' => 'In Progress',
    'blocked' => 'Blocked',
    _ => 'Pending',
  };

  Color get _statusColor => switch (todo.status) {
    'completed' => AppColors.success,
    'in_progress' => AppColors.accentBlue,
    'blocked' => AppColors.error,
    _ => AppColors.warning,
  };

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      borderColor: todo.isBlocked
          ? AppColors.error.withValues(alpha: 0.3)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  todo.title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: todo.status == 'completed'
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
              ),
              StatusBadge(
                label: _statusLabel,
                color: _statusColor,
                pulsing: todo.status == 'in_progress',
                size: BadgeSize.small,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              StatusBadge(
                label: todo.priorityLabel,
                color: todo.priorityColor,
                size: BadgeSize.small,
              ),
              if (todo.assignedAgent != null) ...[
                const SizedBox(width: 6),
                StatusBadge(
                  label: todo.assignedAgent!,
                  color: AppColors.agentColor(todo.assignedAgent!),
                  size: BadgeSize.small,
                  icon: Icons.smart_toy_rounded,
                ),
              ],
              if (todo.isBlocked) ...[
                const SizedBox(width: 6),
                StatusBadge(
                  label: 'Blocked',
                  color: AppColors.error,
                  size: BadgeSize.small,
                  icon: Icons.block_rounded,
                ),
              ],
            ],
          ),
          if (todo.subtasks.isNotEmpty) ...[
            const SizedBox(height: 10),
            ForgeLinearProgress(
              progress: todo.progress,
              height: 4,
              color: _statusColor,
              showPercentage: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? AppColors.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: isActive,
        onSelected: (_) => onTap(),
        selectedColor: effectiveColor.withValues(alpha: 0.15),
        checkmarkColor: effectiveColor,
        side: BorderSide(
          color: isActive ? effectiveColor.withValues(alpha: 0.3) : AppColors.borderSubtle,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

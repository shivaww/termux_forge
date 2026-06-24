/// TermuxForge — Agent Observability Screen
///
/// Dashboard showing active agents, their current tasks, models,
/// tool call counts, runtime, cost, error counts, and message logs.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/agent_avatar.dart';
import 'package:nexon/presentation/widgets/forge_app_bar.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';
import 'package:nexon/presentation/widgets/progress_indicator.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// Demo agent data for display.
class _AgentInfo {
  const _AgentInfo({
    required this.name,
    required this.type,
    required this.status,
    required this.model,
    this.currentTask,
    this.toolCalls = 0,
    this.runtime = '0s',
    this.cost = 0.0,
    this.errorCount = 0,
    this.isBackground = false,
  });

  final String name;
  final String type;
  final String status; // active, idle, error, paused
  final String model;
  final String? currentTask;
  final int toolCalls;
  final String runtime;
  final double cost;
  final int errorCount;
  final bool isBackground;

  Color get statusColor => switch (status) {
    'active' => AppColors.success,
    'idle' => AppColors.textTertiary,
    'error' => AppColors.error,
    'paused' => AppColors.warning,
    _ => AppColors.textTertiary,
  };
}

/// The agent observability screen.
class AgentObservabilityScreen extends StatefulWidget {
  const AgentObservabilityScreen({super.key});

  @override
  State<AgentObservabilityScreen> createState() =>
      _AgentObservabilityScreenState();
}

class _AgentObservabilityScreenState extends State<AgentObservabilityScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final List<_AgentInfo> _agents = const [
    _AgentInfo(
      name: 'Orchestrator',
      type: 'orchestrator',
      status: 'active',
      model: 'Claude 4 Sonnet',
      currentTask: 'Coordinating code generation task',
      toolCalls: 24,
      runtime: '12m 34s',
      cost: 0.0145,
    ),
    _AgentInfo(
      name: 'Coder',
      type: 'coder',
      status: 'active',
      model: 'Claude 4 Sonnet',
      currentTask: 'Writing login_screen.dart',
      toolCalls: 18,
      runtime: '8m 12s',
      cost: 0.0098,
    ),
    _AgentInfo(
      name: 'Architect',
      type: 'architect',
      status: 'idle',
      model: 'Claude 4 Opus',
      toolCalls: 6,
      runtime: '2m 45s',
      cost: 0.0234,
    ),
    _AgentInfo(
      name: 'Debugger',
      type: 'debugger',
      status: 'idle',
      model: 'Claude 4 Sonnet',
      toolCalls: 0,
      runtime: '0s',
      cost: 0.0,
    ),
    _AgentInfo(
      name: 'Reviewer',
      type: 'reviewer',
      status: 'paused',
      model: 'GPT-4.1',
      currentTask: 'Waiting for code completion',
      toolCalls: 3,
      runtime: '1m 10s',
      cost: 0.0032,
    ),
    _AgentInfo(
      name: 'Background Worker',
      type: 'background',
      status: 'active',
      model: 'GPT-4.1 mini',
      currentTask: 'Indexing project files',
      toolCalls: 42,
      runtime: '15m 22s',
      cost: 0.0012,
      isBackground: true,
    ),
    _AgentInfo(
      name: 'Security',
      type: 'security',
      status: 'error',
      model: 'Claude 4 Sonnet',
      currentTask: 'Scan failed: timeout',
      toolCalls: 1,
      runtime: '30s',
      cost: 0.0005,
      errorCount: 1,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ForgeAppBar(
        title: 'Agent Observatory',
        showBackButton: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'Activity Log'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverview(context),
          _buildActivityLog(context),
        ],
      ),
    );
  }

  Widget _buildOverview(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // ── Summary cards ──
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    label: 'Active',
                    value: '${_agents.where((a) => a.status == "active").length}',
                    icon: Icons.play_arrow_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'Total Cost',
                    value: '\$${_agents.fold<double>(0, (s, a) => s + a.cost).toStringAsFixed(4)}',
                    icon: Icons.attach_money_rounded,
                    color: AppColors.accentBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'Tool Calls',
                    value: '${_agents.fold<int>(0, (s, a) => s + a.toolCalls)}',
                    icon: Icons.build_rounded,
                    color: AppColors.accentPurple,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SummaryCard(
                    label: 'Errors',
                    value: '${_agents.fold<int>(0, (s, a) => s + a.errorCount)}',
                    icon: Icons.error_outline_rounded,
                    color: AppColors.error,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Agent grid ──
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, i) => _AgentCard(agent: _agents[i]).animate().fadeIn(
                delay: Duration(milliseconds: i * 60),
                duration: 250.ms,
              ),
              childCount: _agents.length,
            ),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 400,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
            ),
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildActivityLog(BuildContext context) {
    final logs = [
      ('12:34:56', 'orchestrator', 'Dispatched coder for login_screen.dart'),
      ('12:34:58', 'coder', 'Reading project structure...'),
      ('12:35:02', 'coder', 'Tool call: read_file (lib/main.dart)'),
      ('12:35:05', 'coder', 'Tool call: write_file (lib/screens/login_screen.dart)'),
      ('12:35:10', 'background', 'Indexing: 142 files processed'),
      ('12:35:15', 'reviewer', 'Queued review for login_screen.dart'),
      ('12:35:20', 'security', 'ERROR: Scan timeout after 30s'),
      ('12:35:25', 'orchestrator', 'Task progress: 60% complete'),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: logs.length,
      itemBuilder: (_, i) {
        final (time, agent, message) = logs[i];
        final isError = message.contains('ERROR');
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: AppColors.borderSubtle),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                time,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
              const SizedBox(width: 10),
              AgentAvatar(agentType: agent, size: AvatarSize.small),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: isError ? AppColors.error : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(
          delay: Duration(milliseconds: i * 30),
          duration: 200.ms,
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});

  final _AgentInfo agent;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      borderColor: agent.status == 'error'
          ? AppColors.error.withValues(alpha: 0.3)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AgentAvatar(
                agentType: agent.type,
                size: AvatarSize.medium,
                showStatus: true,
                isActive: agent.status == 'active',
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    StatusBadge(
                      label: agent.status,
                      color: agent.statusColor,
                      pulsing: agent.status == 'active',
                      size: BadgeSize.small,
                    ),
                  ],
                ),
              ),
              if (agent.isBackground)
                const Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: AppColors.accentPurple,
                ),
            ],
          ),
          if (agent.currentTask != null) ...[
            const SizedBox(height: 8),
            Text(
              agent.currentTask!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const Spacer(),
          Row(
            children: [
              _MiniMetric(
                icon: Icons.auto_awesome_rounded,
                value: agent.model.split(' ').last,
              ),
              _MiniMetric(
                icon: Icons.build_rounded,
                value: '${agent.toolCalls}',
              ),
              _MiniMetric(
                icon: Icons.timer_rounded,
                value: agent.runtime,
              ),
              _MiniMetric(
                icon: Icons.attach_money_rounded,
                value: '\$${agent.cost.toStringAsFixed(3)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.textTertiary),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

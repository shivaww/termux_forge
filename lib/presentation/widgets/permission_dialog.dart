/// TermuxForge — Permission Approval Dialog
///
/// A modal dialog that shows pending permission requests from agents.
/// Displays command preview, risk level color coding, affected files,
/// and approve / deny actions. Critical for the security model.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexon/core/theme/app_colors.dart';
import 'package:nexon/presentation/widgets/glass_card.dart';
import 'package:nexon/presentation/widgets/status_badge.dart';

/// Result of a permission dialog interaction.
enum PermissionResult { approved, denied, alwaysApprove }

/// Shows the [PermissionDialog] and returns the user's decision.
Future<PermissionResult?> showPermissionDialog(
  BuildContext context, {
  required String agentName,
  required String command,
  required int riskLevel,
  String? description,
  List<String>? affectedFiles,
}) {
  return showGeneralDialog<PermissionResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Permission Dialog',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    transitionBuilder: (_, anim, __, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutBack,
          ).drive(Tween(begin: 0.9, end: 1.0)),
          child: child,
        ),
      );
    },
    pageBuilder: (context, _, __) => PermissionDialog(
      agentName: agentName,
      command: command,
      riskLevel: riskLevel,
      description: description,
      affectedFiles: affectedFiles,
    ),
  );
}

/// Dialog body for permission requests.
class PermissionDialog extends StatelessWidget {
  /// Creates a [PermissionDialog].
  const PermissionDialog({
    required this.agentName,
    required this.command,
    required this.riskLevel,
    super.key,
    this.description,
    this.affectedFiles,
  });

  /// Name of the requesting agent.
  final String agentName;

  /// The command / action to approve.
  final String command;

  /// Risk level 1-10.
  final int riskLevel;

  /// Optional explanation of what the command does.
  final String? description;

  /// List of files that will be modified.
  final List<String>? affectedFiles;

  String get _riskLabel {
    if (riskLevel <= 3) return 'Low Risk';
    if (riskLevel <= 5) return 'Moderate';
    if (riskLevel <= 7) return 'Elevated';
    return 'High Risk';
  }

  @override
  Widget build(BuildContext context) {
    final riskColor = AppColors.permissionLevel(riskLevel);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Material(
          color: Colors.transparent,
          child: GlassCard(
            blurAmount: 20,
            borderRadius: 24,
            borderColor: riskColor.withValues(alpha: 0.3),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: riskColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shield_outlined,
                        color: riskColor,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Permission Request',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'from $agentName',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    StatusBadge(label: _riskLabel, color: riskColor),
                  ],
                ).animate().fadeIn(duration: 200.ms),

                const SizedBox(height: 20),

                // ── Command Preview ──
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundPrimary,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: riskColor.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    command,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                    maxLines: 8,
                    overflow: TextOverflow.ellipsis,
                  ),
                ).animate().fadeIn(delay: 100.ms, duration: 200.ms),

                if (description != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    description!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],

                // ── Affected Files ──
                if (affectedFiles != null && affectedFiles!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Affected Files',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: affectedFiles!
                        .map(
                          (f) => Chip(
                            avatar: Icon(
                              Icons.insert_drive_file_outlined,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            label: Text(
                              f.split('/').last,
                              style: const TextStyle(fontSize: 11),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                        )
                        .toList(),
                  ),
                ],

                // ── Risk Meter ──
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(
                      'Risk Level',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const Spacer(),
                    Text(
                      '$riskLevel / 10',
                      style: TextStyle(
                        color: riskColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: riskLevel / 10,
                    minHeight: 6,
                    backgroundColor: AppColors.borderSubtle,
                    valueColor: AlwaysStoppedAnimation(riskColor),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Actions ──
                Row(
                  children: [
                    // Always approve
                    TextButton(
                      onPressed: () => Navigator.of(context)
                          .pop(PermissionResult.alwaysApprove),
                      child: const Text(
                        'Always Allow',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                    const Spacer(),
                    // Deny
                    OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop(PermissionResult.denied),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                      child: const Text('Deny'),
                    ),
                    const SizedBox(width: 10),
                    // Approve
                    ElevatedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(PermissionResult.approved),
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: riskColor,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ).animate().fadeIn(delay: 200.ms, duration: 200.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

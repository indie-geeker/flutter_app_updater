import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

import '../demo/update_demo_controller.dart';
import 'update_progress_dialog.dart';

class UpdateResultDialog extends StatelessWidget {
  final UpdateDemoController controller;
  final VoidCallback onLater;
  final VoidCallback onUpdate;
  final VoidCallback onReset;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  const UpdateResultDialog({
    super.key,
    required this.controller,
    required this.onLater,
    required this.onUpdate,
    required this.onReset,
    required this.onCancel,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              return switch (controller.phase) {
                DemoPhase.updateAvailable => _UpdateDecision(
                    controller: controller,
                    onLater: onLater,
                    onUpdate: onUpdate,
                    onReset: onReset,
                  ),
                DemoPhase.executing => UpdateProgressDialogContent(
                    controller: controller,
                    onCancel: onCancel,
                  ),
                DemoPhase.succeeded ||
                DemoPhase.failed ||
                DemoPhase.canceled =>
                  _TerminalResult(
                    controller: controller,
                    onRetry: onRetry,
                    onOpenSettings: onOpenSettings,
                    onClose: onClose,
                  ),
                _ => const SizedBox.shrink(),
              };
            },
          ),
        ),
      ),
    );
  }
}

class _UpdateDecision extends StatelessWidget {
  final UpdateDemoController controller;
  final VoidCallback onLater;
  final VoidCallback onUpdate;
  final VoidCallback onReset;

  const _UpdateDecision({
    required this.controller,
    required this.onLater,
    required this.onUpdate,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final update = controller.preparedUpdate!;
    final required = update.isRequired;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: required
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.primaryContainer,
              child: Icon(
                required ? Icons.priority_high : Icons.system_update_alt,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    required
                        ? 'Required update'
                        : 'Update ${update.candidate.version} available',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    required
                        ? 'This update cannot be deferred in a real app.'
                        : 'Choose when to run the simulated update.',
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(update.candidate.releaseNotes),
        ),
        const SizedBox(height: 12),
        Text(
          'Manifest action order',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 6),
        for (final (index, action) in update.actions.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${index + 1}. ${_actionLabel(action)}'
              '${identical(action, update.recommendedAction) ? ' · Recommended' : ''}',
            ),
          ),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            if (required)
              TextButton(
                onPressed: onReset,
                child: const Text('Reset simulation'),
              )
            else
              TextButton(onPressed: onLater, child: const Text('Later')),
            FilledButton.icon(
              onPressed: onUpdate,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Update now'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TerminalResult extends StatelessWidget {
  final UpdateDemoController controller;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback onClose;

  const _TerminalResult({
    required this.controller,
    required this.onRetry,
    required this.onOpenSettings,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final succeeded = controller.phase == DemoPhase.succeeded;
    final permissionRequired = controller.errorCode ==
        UpdateErrorCode.packageInstallPermissionRequired;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          succeeded ? Icons.check_circle_outline : Icons.error_outline,
          size: 48,
          color: succeeded
              ? const Color(0xFF2E7D55)
              : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 14),
        Text(
          succeeded
              ? 'Simulation complete'
              : controller.phase == DemoPhase.canceled
                  ? 'Simulation canceled'
                  : 'Simulation failed',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          succeeded
              ? 'No external action was performed.'
              : controller.message ?? 'The simulated update did not complete.',
          textAlign: TextAlign.center,
        ),
        if (controller.errorCode case final code?) ...[
          const SizedBox(height: 14),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                code.value,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: 10,
          runSpacing: 10,
          children: [
            if (permissionRequired)
              OutlinedButton(
                onPressed: onOpenSettings,
                child: const Text('Open settings (simulated)'),
              ),
            if (controller.phase == DemoPhase.failed)
              FilledButton(onPressed: onRetry, child: const Text('Retry')),
            TextButton(onPressed: onClose, child: const Text('Close')),
          ],
        ),
      ],
    );
  }
}

String _actionLabel(UpdateAction action) {
  return switch (action) {
    OpenStoreAction() => 'Open official store',
    OpenAndroidMarketAction() => 'Open Android market',
    DownloadPackageAction() => 'Download package',
    InstallPackageAction() => 'Install package',
    DownloadAndInstallPackageAction() => 'Download and install package',
    OpenInstallerAction() => 'Download desktop installer',
  };
}

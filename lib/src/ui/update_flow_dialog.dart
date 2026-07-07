import 'dart:async';

import 'package:flutter/material.dart';

import '../channel/flutter_app_updater_platform_interface.dart';
import '../core/app_updater.dart';
import '../platform/update_action_executor.dart';
import 'update_flow_controller.dart';

export 'update_flow_controller.dart' show UpdateFlowState;

typedef UpdateFlowDialogBuilder = Widget Function(
  BuildContext context,
  UpdateFlowState state,
);

Future<UpdateActionResult?> showUpdateFlowDialog({
  required BuildContext context,
  required AppUpdater updater,
  required PreparedUpdateAvailable update,
  UpdateFlowDialogBuilder? builder,
}) {
  return showDialog<UpdateActionResult>(
    context: context,
    barrierDismissible: !update.isRequired,
    builder: (context) {
      return UpdateFlowDialog(
        updater: updater,
        update: update,
        builder: builder,
      );
    },
  );
}

class UpdateFlowDialog extends StatefulWidget {
  final AppUpdater? updater;
  final PreparedUpdateAvailable? update;
  final UpdateFlowController? controller;
  final UpdateFlowDialogBuilder? builder;

  const UpdateFlowDialog({
    super.key,
    this.updater,
    this.update,
    this.controller,
    this.builder,
  }) : assert(
          controller != null || (updater != null && update != null),
          'Either controller or updater + update must be provided.',
        );

  @override
  State<UpdateFlowDialog> createState() => _UpdateFlowDialogState();
}

class _UpdateFlowDialogState extends State<UpdateFlowDialog>
    with WidgetsBindingObserver {
  late final UpdateFlowController _controller;
  late final bool _ownsController;
  late UpdateFlowState _state;
  StreamSubscription<UpdateFlowState>? _stateSubscription;
  var _didPop = false;
  var _waitingForInstallPermission = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ??
        UpdateFlowController(
          updater: widget.updater!,
          update: widget.update!,
        );
    _state = _controller.state;
    _stateSubscription = _controller.changes.listen((state) {
      if (!mounted) {
        return;
      }
      setState(() {
        _state = state;
      });
      if (!_didPop && state.phase == UpdateFlowPhase.completed) {
        _didPop = true;
        Navigator.of(context).pop(state.result);
      }
    });
    unawaited(_controller.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stateSubscription?.cancel());
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _waitingForInstallPermission &&
        mounted) {
      unawaited(_resumeAfterInstallPermission());
    }
  }

  @override
  Widget build(BuildContext context) {
    final customBuilder = widget.builder;
    if (customBuilder != null) {
      return customBuilder(context, _state);
    }

    final update = _state.update;
    final candidate = update.candidate;
    final canDismiss = !update.isRequired;

    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async => canDismiss,
      child: AlertDialog(
        title: Text('Update ${candidate.version}'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (candidate.releaseNotes.trim().isNotEmpty) ...[
                Text(candidate.releaseNotes.trim()),
                const SizedBox(height: 16),
              ],
              if (_state.hasProgress) ...[
                LinearProgressIndicator(value: _state.progress),
                const SizedBox(height: 8),
                Text(_progressLabel(_state)),
              ],
              if (!_state.hasProgress) Text(_state.statusLabel),
              if (_state.phase == UpdateFlowPhase.permissionRequired) ...[
                const SizedBox(height: 8),
                const Text('Install permission is required.'),
              ],
              if (_state.phase == UpdateFlowPhase.failed) ...[
                const SizedBox(height: 8),
                Text(_failureLabel(_state)),
              ],
            ],
          ),
        ),
        actions: _actions(context, canDismiss),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, bool canDismiss) {
    if (_state.phase == UpdateFlowPhase.failed) {
      return [
        if (canDismiss)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_state.result),
            child: const Text('Close'),
          ),
        TextButton(
          onPressed: () {
            unawaited(_controller.retry());
          },
          child: const Text('Retry'),
        ),
      ];
    }

    if (_state.phase == UpdateFlowPhase.permissionRequired) {
      return [
        TextButton(
          onPressed: () {
            unawaited(_openInstallPermissionSettings());
          },
          child: const Text('Continue'),
        ),
      ];
    }

    if (canDismiss && !_state.isTerminal) {
      return [
        TextButton(
          onPressed: () {
            unawaited(_cancel());
          },
          child: const Text('Cancel'),
        ),
      ];
    }

    return const [];
  }

  Future<void> _cancel() async {
    final navigator = Navigator.of(context);
    final cancel = _controller.cancel();
    if (mounted) {
      navigator.pop();
    }
    await cancel;
  }

  Future<void> _openInstallPermissionSettings() async {
    _waitingForInstallPermission = true;
    try {
      await FlutterAppUpdaterPlatform.instance.openInstallPermissionSettings();
    } catch (_) {
      _waitingForInstallPermission = false;
    }
  }

  Future<void> _resumeAfterInstallPermission() async {
    _waitingForInstallPermission = false;
    try {
      final canInstall =
          await FlutterAppUpdaterPlatform.instance.canRequestPackageInstalls();
      if (canInstall && mounted) {
        await _controller.retry();
      }
    } catch (_) {
      // Keep the permission-required state visible when the platform check
      // cannot be completed.
    }
  }

  String _progressLabel(UpdateFlowState state) {
    final progress = state.progress;
    if (progress == null) {
      return '${state.receivedBytes} bytes';
    }
    final percent = (progress * 100).clamp(0, 100).round();
    return '$percent%';
  }

  String _failureLabel(UpdateFlowState state) {
    final result = state.result;
    if (result == null) {
      return 'Update failed.';
    }
    return result.message ?? result.code?.value ?? 'Update failed.';
  }
}

import 'package:flutter/material.dart';

import '../demo/update_demo_controller.dart';
import 'scenario_form.dart';
import 'update_result_dialog.dart';

class UpdateSimulatorPage extends StatefulWidget {
  final UpdateDemoController? controller;

  const UpdateSimulatorPage({super.key, this.controller});

  @override
  State<UpdateSimulatorPage> createState() => _UpdateSimulatorPageState();
}

class _UpdateSimulatorPageState extends State<UpdateSimulatorPage> {
  late final UpdateDemoController _controller =
      widget.controller ?? UpdateDemoController();
  late final bool _ownsController = widget.controller == null;
  bool _dialogVisible = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handleControllerChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChange);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _handleControllerChange() {
    if (_controller.phase == DemoPhase.updateAvailable && !_dialogVisible) {
      _dialogVisible = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showUpdateDialog();
        }
      });
    }
  }

  Future<void> _showUpdateDialog() async {
    final required = _controller.preparedUpdate?.isRequired ?? false;
    await showDialog<void>(
      context: context,
      barrierDismissible: !required,
      builder: (dialogContext) {
        void close() => Navigator.of(dialogContext).pop();
        return PopScope(
          canPop: !required,
          child: UpdateResultDialog(
            controller: _controller,
            onLater: () {
              _controller.deferUpdate();
              close();
            },
            onUpdate: () {
              _controller.performRecommended();
            },
            onReset: () {
              _controller.reset();
              close();
            },
            onCancel: _controller.cancel,
            onRetry: () {
              _controller.performRecommended();
            },
            onOpenSettings: _controller.simulateOpenSettings,
            onClose: close,
          ),
        );
      },
    );
    if (mounted) {
      setState(() {
        _dialogVisible = false;
      });
    }
    if (mounted &&
        !required &&
        _controller.phase == DemoPhase.updateAvailable) {
      _controller.deferUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Update Simulator'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 20),
            child: Center(child: _SafeModeBadge()),
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _SimulatorIntro(),
                      const SizedBox(height: 20),
                      ScenarioForm(
                        scenario: _controller.scenario,
                        enabled: !_controller.isBusy,
                        onChanged: _controller.updateScenario,
                      ),
                      if (!_dialogVisible)
                        if (_statusFor(_controller) case final status?) ...[
                          const SizedBox(height: 16),
                          _StatusBanner(status: status),
                        ],
                      const SizedBox(height: 20),
                      _ActionBar(controller: _controller),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final _StatusContent status;

  const _StatusBanner({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: status.isError
            ? Theme.of(context).colorScheme.errorContainer
            : const Color(0xFFDDECE3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(status.isError
              ? Icons.error_outline
              : Icons.check_circle_outline),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.title,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(status.message),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusContent {
  final String title;
  final String message;
  final bool isError;

  const _StatusContent(this.title, this.message, {this.isError = false});
}

_StatusContent? _statusFor(UpdateDemoController controller) {
  return switch (controller.phase) {
    DemoPhase.upToDate => const _StatusContent(
        'No update available',
        'The installed version is up to date.',
      ),
    DemoPhase.checkFailed => _StatusContent(
        controller.errorCode?.value ?? 'Check failed',
        controller.message ?? 'The simulated check failed.',
        isError: true,
      ),
    DemoPhase.succeeded => const _StatusContent(
        'Simulation complete',
        'No external action was performed.',
      ),
    DemoPhase.failed || DemoPhase.canceled => _StatusContent(
        controller.errorCode?.value ?? 'Simulation failed',
        controller.message ?? 'The simulated update did not complete.',
        isError: true,
      ),
    _ => null,
  };
}

class _SimulatorIntro extends StatelessWidget {
  const _SimulatorIntro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF202B34),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.science_outlined, color: Colors.white),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Configure. Check. Observe.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Version selection and update policy are real. Network, '
                  'store, download, and installation effects are simulated.',
                  style: TextStyle(color: Color(0xFFCBD3D8), height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SafeModeBadge extends StatelessWidget {
  const _SafeModeBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF31404B),
        border: Border.all(color: const Color(0xFF60737F)),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Row(
        children: [
          Icon(Icons.shield_outlined, size: 15),
          SizedBox(width: 5),
          Text('SAFE SIMULATION', style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final UpdateDemoController controller;

  const _ActionBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 12,
      runSpacing: 12,
      children: [
        OutlinedButton.icon(
          onPressed: controller.isBusy ? null : controller.reset,
          icon: const Icon(Icons.restart_alt),
          label: const Text('Reset'),
        ),
        FilledButton.icon(
          onPressed: controller.isBusy ? null : controller.checkForUpdate,
          icon: controller.phase == DemoPhase.checking
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.system_update_alt),
          label: const Text('Check for update'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../production/production_app_metadata.dart';
import '../production/production_update_configuration.dart';
import '../production/production_update_controller.dart';
import 'production_action_confirmation_dialog.dart';

/// Opt-in page that exercises the package's real production boundaries.
final class ProductionIntegrationPage extends StatefulWidget {
  final ProductionUpdateController? controller;
  final ProductionUpdateConfiguration? configuration;

  const ProductionIntegrationPage({
    super.key,
    this.controller,
    this.configuration,
  });

  @override
  State<ProductionIntegrationPage> createState() =>
      _ProductionIntegrationPageState();
}

final class _ProductionIntegrationPageState
    extends State<ProductionIntegrationPage> {
  late final ProductionUpdateController _controller = widget.controller ??
      ProductionUpdateController(
        configuration: widget.configuration ??
            ProductionUpdateConfiguration.fromEnvironment(),
        runtimeLoader: const PluginProductionRuntimeLoader(),
        updaterFactory: const DefaultProductionUpdaterFactory(),
      );
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _reviewRecommendedAction() async {
    final update = _controller.preparedUpdate;
    if (update == null) {
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ProductionActionConfirmationDialog(
        update: update,
        distributionPolicy: _controller.configuration.distributionPolicy,
        onCancel: () {
          _controller.declineRecommendedAction();
          Navigator.of(dialogContext).pop();
        },
        onConfirm: () {
          Navigator.of(dialogContext).pop();
          _controller.performRecommended();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Production Integration')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          if (!_controller.configuration.enabled) {
            return const _DisabledProductionExample();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 40),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _ProductionIntro(),
                      const SizedBox(height: 20),
                      if (_controller.phase == ProductionPhase.failed)
                        _FailureCard(controller: _controller)
                      else if (_controller.phase ==
                          ProductionPhase.updateAvailable)
                        _AvailableCard(
                          controller: _controller,
                          onReview: _reviewRecommendedAction,
                        )
                      else if (_controller.phase == ProductionPhase.upToDate)
                        const _MessageCard(
                          title: 'No production update available',
                          message: 'The installed application is up to date.',
                        )
                      else if (_controller.phase == ProductionPhase.succeeded)
                        _MessageCard(
                          title: 'Update action completed',
                          message: _controller.message ??
                              'The recommended action completed.',
                        ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: _controller.isBusy
                            ? null
                            : _controller.checkForUpdate,
                        icon: _controller.phase == ProductionPhase.checking
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.system_update_alt),
                        label: const Text('Check production update'),
                      ),
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

final class _DisabledProductionExample extends StatelessWidget {
  const _DisabledProductionExample();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: const Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 44),
              SizedBox(height: 16),
              Text(
                'Production integration disabled',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'ENABLE_PRODUCTION_UPDATE_EXAMPLE',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Set this flag to true and provide the documented HTTPS '
                'manifest, application ID, and public keys. The simulator '
                'remains the default experience.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ProductionIntro extends StatelessWidget {
  const _ProductionIntro();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Real signed-manifest integration',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text(
              'A check fetches, verifies, parses, selects, and prepares an '
              'update. No store, download, or installer action runs until a '
              'user reviews the exact destination and confirms it.',
            ),
          ],
        ),
      ),
    );
  }
}

final class _AvailableCard extends StatelessWidget {
  final ProductionUpdateController controller;
  final VoidCallback onReview;

  const _AvailableCard({required this.controller, required this.onReview});

  @override
  Widget build(BuildContext context) {
    final update = controller.preparedUpdate!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Update ${update.candidate.version} available',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(update.candidate.releaseNotes),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onReview,
              child: const Text('Review recommended action'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _FailureCard extends StatelessWidget {
  final ProductionUpdateController controller;

  const _FailureCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              controller.errorCode?.value ?? 'ACTION_FAILED',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(controller.message ?? 'The production update flow failed.'),
          ],
        ),
      ),
    );
  }
}

final class _MessageCard extends StatelessWidget {
  final String title;
  final String message;

  const _MessageCard({required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(message),
          ],
        ),
      ),
    );
  }
}

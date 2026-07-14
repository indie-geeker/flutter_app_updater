import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

/// Displays the exact security-relevant action details before execution.
final class ProductionActionConfirmationDialog extends StatelessWidget {
  final PreparedUpdateAvailable update;
  final UpdateDistributionPolicy distributionPolicy;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  const ProductionActionConfirmationDialog({
    super.key,
    required this.update,
    required this.distributionPolicy,
    required this.onCancel,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final details = _ActionDetails.from(update.recommendedAction);
    return AlertDialog(
      title: const Text('Confirm update action'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'The check is complete. Nothing happens until you confirm.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            _DetailRow(label: 'Action type', value: details.actionType),
            _DetailRow(
              label: 'Destination host',
              value: details.destinationHost,
            ),
            _DetailRow(
              label: 'Package / installer type',
              value: details.artifactType,
            ),
            _DetailRow(label: 'Exact size', value: details.exactSize),
            _DetailRow(label: 'SHA-256', value: details.sha256),
            _DetailRow(
              label: 'Distribution policy',
              value: distributionPolicy.name,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
        FilledButton(
          onPressed: onConfirm,
          child: const Text('Confirm and execute'),
        ),
      ],
    );
  }
}

final class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}

final class _ActionDetails {
  final String actionType;
  final String destinationHost;
  final String artifactType;
  final String exactSize;
  final String sha256;

  const _ActionDetails({
    required this.actionType,
    required this.destinationHost,
    required this.artifactType,
    required this.exactSize,
    required this.sha256,
  });

  factory _ActionDetails.from(UpdateAction action) {
    return switch (action) {
      OpenStoreAction(:final storeUrl) => _ActionDetails(
          actionType: 'Open official store',
          destinationHost: storeUrl.host,
          artifactType: 'Not applicable',
          exactSize: 'Not applicable',
          sha256: 'Not applicable',
        ),
      OpenAndroidMarketAction(:final fallbackUrl) => _ActionDetails(
          actionType: 'Open Android market',
          destinationHost: fallbackUrl?.host ?? 'Installed market application',
          artifactType: 'Not applicable',
          exactSize: 'Not applicable',
          sha256: 'Not applicable',
        ),
      DownloadPackageAction(
        :final packageUrl,
        :final packageType,
        :final packageSizeBytes,
        :final sha256,
      ) =>
        _ActionDetails(
          actionType: 'Download verified package',
          destinationHost: packageUrl.host,
          artifactType: packageType.name,
          exactSize: '$packageSizeBytes bytes',
          sha256: sha256,
        ),
      InstallPackageAction(
        :final packageType,
        :final packageSizeBytes,
        :final sha256,
      ) =>
        _ActionDetails(
          actionType: 'Install local package',
          destinationHost: 'Local file',
          artifactType: packageType.name,
          exactSize: packageSizeBytes == null
              ? 'Not provided'
              : '$packageSizeBytes bytes',
          sha256: sha256 ?? 'Not provided',
        ),
      DownloadAndInstallPackageAction(
        :final packageUrl,
        :final packageType,
        :final packageSizeBytes,
        :final sha256,
      ) =>
        _ActionDetails(
          actionType: 'Download and install verified package',
          destinationHost: packageUrl.host,
          artifactType: packageType.name,
          exactSize: '$packageSizeBytes bytes',
          sha256: sha256,
        ),
      OpenInstallerAction(
        :final installerUrl,
        :final installerType,
        :final installerSizeBytes,
        :final sha256,
      ) =>
        _ActionDetails(
          actionType: 'Download and open installer',
          destinationHost: installerUrl.host,
          artifactType: installerType.name,
          exactSize: '$installerSizeBytes bytes',
          sha256: sha256,
        ),
    };
  }
}

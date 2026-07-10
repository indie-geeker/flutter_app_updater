import 'package:flutter/material.dart';

import '../demo/update_demo_controller.dart';

class UpdateProgressDialogContent extends StatelessWidget {
  final UpdateDemoController controller;
  final VoidCallback onCancel;

  const UpdateProgressDialogContent({
    super.key,
    required this.controller,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final percent = controller.progress == null
        ? null
        : (controller.progress! * 100).round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DialogHeading(
          icon: Icons.downloading_outlined,
          title: 'Simulating update',
          subtitle: 'No network, file, store, or installer is being used.',
        ),
        const SizedBox(height: 24),
        LinearProgressIndicator(value: controller.progress),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(percent == null ? 'Preparing…' : '$percent%'),
            Text(
              _byteProgress(
                controller.downloadedBytes,
                controller.totalBytes,
              ),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
            label: const Text('Cancel update'),
          ),
        ),
      ],
    );
  }
}

class _DialogHeading extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DialogHeading({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(child: Icon(icon)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 5),
              Text(subtitle),
            ],
          ),
        ),
      ],
    );
  }
}

String _byteProgress(int? downloadedBytes, int? totalBytes) {
  final downloaded = downloadedBytes;
  final total = totalBytes;
  if (downloaded == null || total == null) {
    return '—';
  }
  return '${_megabytes(downloaded)} / ${_megabytes(total)} MB';
}

String _megabytes(int bytes) => (bytes / 1000000).toStringAsFixed(1);

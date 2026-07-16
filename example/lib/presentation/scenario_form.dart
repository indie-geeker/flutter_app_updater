import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

import '../demo/demo_scenario.dart';
import 'app_card.dart';

class ScenarioForm extends StatefulWidget {
  final DemoScenario scenario;
  final bool enabled;
  final ValueChanged<DemoScenario> onChanged;

  const ScenarioForm({
    super.key,
    required this.scenario,
    required this.enabled,
    required this.onChanged,
  });

  @override
  State<ScenarioForm> createState() => _ScenarioFormState();
}

class _ScenarioFormState extends State<ScenarioForm> {
  late final TextEditingController _installedVersion;
  late final TextEditingController _installedBuild;
  late final TextEditingController _runtimeArchitecture;
  late final TextEditingController _releaseVersion;
  late final TextEditingController _releaseBuild;
  late final TextEditingController _releaseArchitecture;
  late final TextEditingController _releaseNotes;
  late final TextEditingController _minimumVersion;
  late final TextEditingController _packageSizeMb;

  @override
  void initState() {
    super.initState();
    _installedVersion = TextEditingController();
    _installedBuild = TextEditingController();
    _runtimeArchitecture = TextEditingController();
    _releaseVersion = TextEditingController();
    _releaseBuild = TextEditingController();
    _releaseArchitecture = TextEditingController();
    _releaseNotes = TextEditingController();
    _minimumVersion = TextEditingController();
    _packageSizeMb = TextEditingController();
    _syncControllers();
  }

  @override
  void didUpdateWidget(ScenarioForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncControllers();
  }

  @override
  void dispose() {
    _installedVersion.dispose();
    _installedBuild.dispose();
    _runtimeArchitecture.dispose();
    _releaseVersion.dispose();
    _releaseBuild.dispose();
    _releaseArchitecture.dispose();
    _releaseNotes.dispose();
    _minimumVersion.dispose();
    _packageSizeMb.dispose();
    super.dispose();
  }

  void _syncControllers() {
    _sync(_installedVersion, widget.scenario.installedVersion);
    _sync(_installedBuild, widget.scenario.installedBuildNumber);
    _sync(
      _runtimeArchitecture,
      widget.scenario.runtimeArchitecture,
    );
    _sync(_releaseVersion, widget.scenario.releaseVersion);
    _sync(_releaseBuild, widget.scenario.releaseBuildNumber);
    _sync(
      _releaseArchitecture,
      widget.scenario.releaseArchitecture,
    );
    _sync(_releaseNotes, widget.scenario.releaseNotes);
    _sync(_minimumVersion, widget.scenario.minSupportedVersion ?? '');
    _sync(
      _packageSizeMb,
      (widget.scenario.packageSizeBytes / 1000000).toStringAsFixed(0),
    );
  }

  void _sync(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SectionCard(
          number: '01',
          title: 'Installed application',
          subtitle: 'The client state used by the real update selector.',
          child: _ResponsiveFields(
            children: [
              TextField(
                key: const Key('installed-version-field'),
                controller: _installedVersion,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Current version'),
                onChanged: (value) => _emit(
                  widget.scenario.copyWith(installedVersion: value),
                ),
              ),
              TextField(
                key: const Key('installed-build-field'),
                controller: _installedBuild,
                enabled: widget.enabled,
                decoration: const InputDecoration(labelText: 'Current build'),
                keyboardType: TextInputType.number,
                onChanged: (value) => _emit(
                  widget.scenario.copyWith(installedBuildNumber: value),
                ),
              ),
              _RebuiltDropdown<TargetPlatform>(
                rebuildValue: widget.scenario.platform,
                child: DropdownButtonFormField<TargetPlatform>(
                  key: const Key('platform-field'),
                  // `value` keeps the example compatible with Flutter 3.29;
                  // it was renamed to `initialValue` in newer SDKs.
                  // ignore: deprecated_member_use
                  value: widget.scenario.platform,
                  decoration: const InputDecoration(labelText: 'Platform'),
                  items: _platforms
                      .map(
                        (platform) => DropdownMenuItem(
                          value: platform,
                          child: Text(_platformLabel(platform)),
                        ),
                      )
                      .toList(),
                  onChanged: widget.enabled ? _changePlatform : null,
                ),
              ),
              TextField(
                key: const Key('runtime-architecture-field'),
                controller: _runtimeArchitecture,
                enabled: widget.enabled,
                decoration:
                    const InputDecoration(labelText: 'Runtime architecture'),
                onChanged: (value) => _emit(
                  widget.scenario.copyWith(runtimeArchitecture: value),
                ),
              ),
              _RebuiltDropdown<String>(
                rebuildValue: widget.scenario.runtimeChannel,
                child: DropdownButtonFormField<String>(
                  key: const Key('runtime-channel-field'),
                  // ignore: deprecated_member_use
                  value: widget.scenario.runtimeChannel,
                  decoration:
                      const InputDecoration(labelText: 'Runtime channel'),
                  items: const [
                    DropdownMenuItem(value: 'stable', child: Text('Stable')),
                    DropdownMenuItem(value: 'beta', child: Text('Beta')),
                  ],
                  onChanged: widget.enabled
                      ? (value) {
                          if (value != null) {
                            _emit(
                              widget.scenario.copyWith(runtimeChannel: value),
                            );
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          number: '02',
          title: 'Available release',
          subtitle: 'The in-memory manifest returned by the simulated server.',
          child: Column(
            children: [
              SwitchListTile.adaptive(
                key: const Key('update-available-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('A newer release is available'),
                subtitle: const Text(
                  'Disable to exercise the real no-update selection path.',
                ),
                value: widget.scenario.updateAvailable,
                onChanged: widget.enabled
                    ? (value) => _emit(
                          widget.scenario.copyWith(updateAvailable: value),
                        )
                    : null,
              ),
              const SizedBox(height: 12),
              _ResponsiveFields(
                children: [
                  TextField(
                    key: const Key('release-version-field'),
                    controller: _releaseVersion,
                    enabled: widget.enabled,
                    decoration:
                        const InputDecoration(labelText: 'Release version'),
                    onChanged: (value) => _emit(
                      widget.scenario.copyWith(releaseVersion: value),
                    ),
                  ),
                  TextField(
                    key: const Key('release-build-field'),
                    controller: _releaseBuild,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Release build'),
                    onChanged: (value) => _emit(
                      widget.scenario.copyWith(releaseBuildNumber: value),
                    ),
                  ),
                  TextField(
                    key: const Key('release-architecture-field'),
                    controller: _releaseArchitecture,
                    enabled: widget.enabled,
                    decoration: const InputDecoration(
                      labelText: 'Release architecture',
                    ),
                    onChanged: (value) => _emit(
                      widget.scenario.copyWith(releaseArchitecture: value),
                    ),
                  ),
                  _RebuiltDropdown<String>(
                    rebuildValue: widget.scenario.releaseChannel,
                    child: DropdownButtonFormField<String>(
                      key: const Key('release-channel-field'),
                      // ignore: deprecated_member_use
                      value: widget.scenario.releaseChannel,
                      decoration:
                          const InputDecoration(labelText: 'Release channel'),
                      items: const [
                        DropdownMenuItem(
                          value: 'stable',
                          child: Text('Stable'),
                        ),
                        DropdownMenuItem(value: 'beta', child: Text('Beta')),
                      ],
                      onChanged: widget.enabled
                          ? (value) {
                              if (value != null) {
                                _emit(
                                  widget.scenario.copyWith(
                                    releaseChannel: value,
                                  ),
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('release-notes-field'),
                controller: _releaseNotes,
                enabled: widget.enabled,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Release notes'),
                onChanged: (value) => _emit(
                  widget.scenario.copyWith(releaseNotes: value),
                ),
              ),
              SwitchListTile.adaptive(
                key: const Key('force-update-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Force this update'),
                subtitle: const Text(
                  'Required updates cannot be deferred by the user.',
                ),
                value:
                    widget.scenario.policyLevel == UpdatePolicyLevel.required,
                onChanged: widget.enabled
                    ? (value) => _emit(
                          widget.scenario.copyWith(
                            policyLevel: value
                                ? UpdatePolicyLevel.required
                                : UpdatePolicyLevel.recommended,
                          ),
                        )
                    : null,
              ),
              const SizedBox(height: 12),
              _ResponsiveFields(
                children: [
                  TextField(
                    key: const Key('minimum-version-field'),
                    controller: _minimumVersion,
                    enabled: widget.enabled,
                    decoration: const InputDecoration(
                      labelText: 'Minimum supported version',
                      hintText: 'Optional',
                    ),
                    onChanged: (value) => _emit(
                      widget.scenario.copyWith(
                        minSupportedVersion:
                            value.trim().isEmpty ? null : value.trim(),
                      ),
                    ),
                  ),
                  _RebuiltDropdown<DemoDelivery>(
                    rebuildValue: widget.scenario.delivery,
                    child: DropdownButtonFormField<DemoDelivery>(
                      key: const Key('delivery-field'),
                      // ignore: deprecated_member_use
                      value: widget.scenario.delivery,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Primary delivery'),
                      items: DemoScenario.allowedDeliveries(
                        widget.scenario.platform,
                      )
                          .map(
                            (delivery) => DropdownMenuItem(
                              value: delivery,
                              child: Text(_deliveryLabel(delivery)),
                            ),
                          )
                          .toList(),
                      onChanged: widget.enabled ? _changeDelivery : null,
                    ),
                  ),
                  _RebuiltDropdown<DemoDelivery?>(
                    rebuildValue: widget.scenario.fallbackDelivery,
                    child: DropdownButtonFormField<DemoDelivery?>(
                      key: const Key('fallback-delivery-field'),
                      // ignore: deprecated_member_use
                      value: widget.scenario.fallbackDelivery,
                      isExpanded: true,
                      decoration:
                          const InputDecoration(labelText: 'Fallback delivery'),
                      items: [
                        const DropdownMenuItem<DemoDelivery?>(
                          value: null,
                          child: Text('None'),
                        ),
                        ...DemoScenario.allowedDeliveries(
                          widget.scenario.platform,
                        ).map(
                          (delivery) => DropdownMenuItem<DemoDelivery?>(
                            value: delivery,
                            child: Text(_deliveryLabel(delivery)),
                          ),
                        ),
                      ],
                      onChanged: widget.enabled
                          ? (value) => _emit(
                                widget.scenario.copyWith(
                                  fallbackDelivery: value,
                                ),
                              )
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          number: '03',
          title: 'Simulation behavior',
          subtitle:
              'Control timing and the terminal result without side effects.',
          child: _ResponsiveFields(
            children: [
              TextField(
                key: const Key('package-size-field'),
                controller: _packageSizeMb,
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Transfer size',
                  suffixText: 'MB',
                ),
                onChanged: (value) {
                  final megabytes = int.tryParse(value);
                  if (megabytes != null && megabytes > 0) {
                    _emit(
                      widget.scenario.copyWith(
                        packageSizeBytes: megabytes * 1000000,
                      ),
                    );
                  }
                },
              ),
              _RebuiltDropdown<Duration>(
                rebuildValue: widget.scenario.executionDuration,
                child: DropdownButtonFormField<Duration>(
                  key: const Key('duration-field'),
                  // ignore: deprecated_member_use
                  value: widget.scenario.executionDuration,
                  decoration:
                      const InputDecoration(labelText: 'Simulation duration'),
                  items: const [
                    DropdownMenuItem(
                      value: Duration.zero,
                      child: Text('Instant'),
                    ),
                    DropdownMenuItem(
                      value: Duration(milliseconds: 500),
                      child: Text('0.5 seconds'),
                    ),
                    DropdownMenuItem(
                      value: Duration(seconds: 1),
                      child: Text('1 second'),
                    ),
                    DropdownMenuItem(
                      value: Duration(seconds: 2),
                      child: Text('2 seconds'),
                    ),
                    DropdownMenuItem(
                      value: Duration(seconds: 4),
                      child: Text('4 seconds'),
                    ),
                  ],
                  onChanged: widget.enabled
                      ? (value) {
                          if (value != null) {
                            _emit(
                              widget.scenario
                                  .copyWith(executionDuration: value),
                            );
                          }
                        }
                      : null,
                ),
              ),
              _RebuiltDropdown<DemoOutcome>(
                rebuildValue: widget.scenario.outcome,
                child: DropdownButtonFormField<DemoOutcome>(
                  key: const Key('outcome-field'),
                  // ignore: deprecated_member_use
                  value: widget.scenario.outcome,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Terminal outcome'),
                  items: DemoScenario.allowedOutcomes(
                    widget.scenario.delivery,
                  )
                      .map(
                        (outcome) => DropdownMenuItem(
                          value: outcome,
                          child: Text(_outcomeLabel(outcome)),
                        ),
                      )
                      .toList(),
                  onChanged: widget.enabled
                      ? (value) {
                          if (value != null) {
                            _emit(widget.scenario.copyWith(outcome: value));
                          }
                        }
                      : null,
                ),
              ),
              SwitchListTile.adaptive(
                key: const Key('retry-succeeds-switch'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Retry succeeds'),
                subtitle: const Text(
                  'Fail the first attempt, then recover with the same executor.',
                ),
                value: widget.scenario.succeedOnRetry,
                onChanged: widget.enabled &&
                        widget.scenario.outcome != DemoOutcome.success
                    ? (value) => _emit(
                          widget.scenario.copyWith(succeedOnRetry: value),
                        )
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _changePlatform(TargetPlatform? platform) {
    if (platform == null) {
      return;
    }
    final allowed = DemoScenario.allowedDeliveries(platform);
    final delivery = allowed.contains(widget.scenario.delivery)
        ? widget.scenario.delivery
        : allowed.first;
    final fallback = allowed.contains(widget.scenario.fallbackDelivery)
        ? widget.scenario.fallbackDelivery
        : null;
    final architecture = platform == TargetPlatform.android ? 'arm64' : 'x64';
    final allowedOutcomes = DemoScenario.allowedOutcomes(delivery);
    final outcome = allowedOutcomes.contains(widget.scenario.outcome)
        ? widget.scenario.outcome
        : DemoOutcome.success;
    _emit(
      widget.scenario.copyWith(
        platform: platform,
        delivery: delivery,
        fallbackDelivery: fallback,
        runtimeArchitecture: architecture,
        releaseArchitecture: architecture,
        outcome: outcome,
        succeedOnRetry: outcome == DemoOutcome.success
            ? false
            : widget.scenario.succeedOnRetry,
      ),
    );
  }

  void _changeDelivery(DemoDelivery? delivery) {
    if (delivery == null) {
      return;
    }
    final allowedOutcomes = DemoScenario.allowedOutcomes(delivery);
    final outcome = allowedOutcomes.contains(widget.scenario.outcome)
        ? widget.scenario.outcome
        : DemoOutcome.success;
    _emit(
      widget.scenario.copyWith(
        delivery: delivery,
        outcome: outcome,
        succeedOnRetry: outcome == DemoOutcome.success
            ? false
            : widget.scenario.succeedOnRetry,
      ),
    );
  }

  void _emit(DemoScenario scenario) {
    if (widget.enabled) {
      widget.onChanged(scenario);
    }
  }
}

class _SectionCard extends StatelessWidget {
  final String number;
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleLarge),
                      const SizedBox(height: 3),
                      Text(subtitle, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  final List<Widget> children;

  const _ResponsiveFields({required this.children});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width >= 700 ? (width - 12) / 2 : width;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _RebuiltDropdown<T> extends StatelessWidget {
  final T rebuildValue;
  final Widget child;

  const _RebuiltDropdown({required this.rebuildValue, required this.child});

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(key: ValueKey(rebuildValue), child: child);
  }
}

const _platforms = [
  TargetPlatform.android,
  TargetPlatform.iOS,
  TargetPlatform.macOS,
  TargetPlatform.windows,
];

String _platformLabel(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

String _deliveryLabel(DemoDelivery delivery) {
  return switch (delivery) {
    DemoDelivery.officialStore => 'Official store',
    DemoDelivery.androidMarket => 'Chinese Android market',
    DemoDelivery.androidDownload => 'Download APK only',
    DemoDelivery.androidInstall => 'Install local APK only',
    DemoDelivery.androidDownloadAndInstall => 'Download and install APK',
    DemoDelivery.desktopInstaller => 'Desktop installer',
  };
}

String _outcomeLabel(DemoOutcome outcome) {
  return switch (outcome) {
    DemoOutcome.success => 'Success',
    DemoOutcome.downloadFailed => 'Download failed',
    DemoOutcome.hashMismatch => 'Hash mismatch',
    DemoOutcome.installPermissionRequired => 'Install permission required',
    DemoOutcome.platformNotSupported => 'Platform not supported',
    DemoOutcome.actionFailed => 'Action failed',
  };
}

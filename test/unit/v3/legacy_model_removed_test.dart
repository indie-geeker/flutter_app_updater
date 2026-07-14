import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v3 legacy model removal', () {
    test('does not ship v2 model-centered Dart sources', () {
      const legacySources = [
        'lib/src/updater.dart',
        'lib/src/controller/update_controller.dart',
        'lib/src/models/update_error.dart',
        'lib/src/models/update_info.dart',
        'lib/src/models/update_check_result.dart',
        'lib/src/models/update_progress.dart',
        'lib/src/models/update_status.dart',
        'lib/src/network/http_client.dart',
        'lib/src/network/update_downloader.dart',
        'lib/src/ui/update_dialog.dart',
        'lib/src/utils/constants.dart',
        'lib/src/utils/update_checker.dart',
        'lib/src/utils/update_logger.dart',
      ];

      final existingLegacySources = legacySources
          .where((path) => File(path).existsSync())
          .toList(growable: false);

      expect(existingLegacySources, isEmpty);
    });

    test('does not ship unfinished Play in-app update symbols', () {
      const forbiddenNames = [
        'PlayUpdateMode',
        'PlayInAppUpdateAction',
        'startPlayInAppUpdate',
        'playInAppUpdateUnavailable',
      ];
      const runtimeRoots = ['lib', 'android', 'ios', 'macos', 'example/lib'];

      final matches = <String>[];
      for (final root in runtimeRoots) {
        for (final entity in Directory(root).listSync(recursive: true)) {
          if (entity is! File) continue;
          if (!const ['.dart', '.kt', '.swift'].any(entity.path.endsWith)) {
            continue;
          }
          final source = entity.readAsStringSync();
          for (final name in forbiddenNames) {
            if (source.contains(name)) matches.add('${entity.path}: $name');
          }
        }
      }

      expect(matches, isEmpty);
    });
  });
}

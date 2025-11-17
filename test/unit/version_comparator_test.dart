import 'package:test/test.dart';
import 'package:flutter_app_updater/src/utils/version_comparator.dart';

void main() {
  group('VersionComparator', () {
    group('compare', () {
      test('should detect newer version', () {
        expect(VersionComparator.compare('1.0.0', '1.0.1'), lessThan(0));
        expect(VersionComparator.compare('1.0.0', '2.0.0'), lessThan(0));
        expect(VersionComparator.compare('1.9.0', '1.10.0'), lessThan(0));
        expect(VersionComparator.compare('1.0.9', '1.0.10'), lessThan(0));
        expect(VersionComparator.compare('0.9.9', '1.0.0'), lessThan(0));
      });

      test('should detect same version', () {
        expect(VersionComparator.compare('1.0.0', '1.0.0'), equals(0));
        expect(VersionComparator.compare('2.5.3', '2.5.3'), equals(0));
        expect(VersionComparator.compare('10.20.30', '10.20.30'), equals(0));
      });

      test('should detect older version', () {
        expect(VersionComparator.compare('2.0.0', '1.0.0'), greaterThan(0));
        expect(VersionComparator.compare('1.10.0', '1.9.0'), greaterThan(0));
        expect(VersionComparator.compare('1.0.10', '1.0.9'), greaterThan(0));
        expect(VersionComparator.compare('3.0.0', '2.99.99'), greaterThan(0));
      });

      test('should handle version padding correctly', () {
        // 1.0 应该等于 1.0.0
        expect(VersionComparator.compare('1', '1.0'), equals(0));
        expect(VersionComparator.compare('1.0', '1.0.0'), equals(0));
        expect(VersionComparator.compare('1.0.0', '1.0.0.0'), equals(0));

        // 1.1 应该大于 1.0.9
        expect(VersionComparator.compare('1.1', '1.0.9'), greaterThan(0));

        // 1 应该小于 1.0.1
        expect(VersionComparator.compare('1', '1.0.1'), lessThan(0));
      });

      test('should handle v prefix', () {
        expect(VersionComparator.compare('v1.0.0', '1.0.1'), lessThan(0));
        expect(VersionComparator.compare('V2.0.0', 'v2.0.0'), equals(0));
        expect(VersionComparator.compare('v1.5.0', 'v1.4.0'), greaterThan(0));
        expect(VersionComparator.compare('v1.0.0', '2.0.0'), lessThan(0));
      });

      test('should handle build numbers', () {
        // 构建号应该被忽略
        expect(VersionComparator.compare('1.0.0+1', '1.0.0+2'), equals(0));
        expect(VersionComparator.compare('1.0.0+100', '1.0.1'), lessThan(0));
        expect(VersionComparator.compare('2.0.0+5', '1.9.9+999'), greaterThan(0));
      });

      test('should handle pre-release versions', () {
        // 预发布版本应该小于正式版本
        expect(VersionComparator.compare('1.0.0-alpha', '1.0.0'), lessThan(0));
        expect(VersionComparator.compare('1.0.0-beta', '1.0.0'), lessThan(0));
        expect(VersionComparator.compare('1.0.0-rc.1', '1.0.0'), lessThan(0));

        // 预发布版本之间的字典序比较
        expect(VersionComparator.compare('1.0.0-alpha', '1.0.0-beta'), lessThan(0));
        expect(VersionComparator.compare('1.0.0-beta', '1.0.0-rc'), lessThan(0));

        // 都是预发布版本时，主版本号仍然有效
        expect(VersionComparator.compare('2.0.0-alpha', '1.0.0-beta'), greaterThan(0));
      });

      test('should handle edge cases', () {
        // 空版本号部分应该被视为0
        expect(VersionComparator.compare('1..0', '1.0.0'), equals(0));

        // 只有主版本号
        expect(VersionComparator.compare('2', '1'), greaterThan(0));
        expect(VersionComparator.compare('1', '2'), lessThan(0));

        // 长版本号
        expect(VersionComparator.compare('1.2.3.4.5', '1.2.3.4.6'), lessThan(0));
      });

      test('should handle real-world version scenarios', () {
        // 模拟实际场景
        expect(VersionComparator.compare('1.9.0', '1.10.0'), lessThan(0));
        expect(VersionComparator.compare('1.99.0', '1.100.0'), lessThan(0));
        expect(VersionComparator.compare('2.0.0', '1.999.999'), greaterThan(0));
      });
    });

    group('hasUpdate', () {
      test('should return true for newer version', () {
        expect(VersionComparator.hasUpdate('1.0.0', '1.0.1'), isTrue);
        expect(VersionComparator.hasUpdate('1.9.0', '1.10.0'), isTrue);
        expect(VersionComparator.hasUpdate('0.9.9', '1.0.0'), isTrue);
      });

      test('should return false for same version', () {
        expect(VersionComparator.hasUpdate('1.0.0', '1.0.0'), isFalse);
        expect(VersionComparator.hasUpdate('1.0', '1.0.0'), isFalse);
        expect(VersionComparator.hasUpdate('v2.0.0', '2.0.0'), isFalse);
      });

      test('should return false for older version', () {
        expect(VersionComparator.hasUpdate('2.0.0', '1.0.0'), isFalse);
        expect(VersionComparator.hasUpdate('1.10.0', '1.9.0'), isFalse);
        expect(VersionComparator.hasUpdate('1.0.0', '1.0.0-beta'), isFalse);
      });

      test('should handle pre-release correctly', () {
        // 当前是预发布版本，正式版本可用
        expect(VersionComparator.hasUpdate('1.0.0-beta', '1.0.0'), isTrue);

        // 当前是正式版本，预发布版本不算更新
        expect(VersionComparator.hasUpdate('1.0.0', '1.0.0-beta'), isFalse);
      });
    });
  });
}

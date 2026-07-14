import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:flutter_app_updater/src/models/update_error_code.dart';
import 'package:flutter_app_updater/src/utils/retry_strategy.dart';

void main() {
  group('RetryStrategy', () {
    group('constructor', () {
      test('should use default values', () {
        const strategy = RetryStrategy();

        expect(strategy.maxAttempts, equals(3));
        expect(strategy.initialDelay, equals(const Duration(seconds: 1)));
        expect(strategy.backoffFactor, equals(2.0));
        expect(strategy.maxDelay, equals(const Duration(seconds: 30)));
        expect(strategy.enableJitter, isTrue);
      });

      test('should accept custom values', () {
        const strategy = RetryStrategy(
          maxAttempts: 5,
          initialDelay: Duration(milliseconds: 500),
          backoffFactor: 1.5,
          maxDelay: Duration(seconds: 10),
          enableJitter: false,
        );

        expect(strategy.maxAttempts, equals(5));
        expect(
            strategy.initialDelay, equals(const Duration(milliseconds: 500)));
        expect(strategy.backoffFactor, equals(1.5));
        expect(strategy.maxDelay, equals(const Duration(seconds: 10)));
        expect(strategy.enableJitter, isFalse);
      });

      test('should allow zero maxAttempts', () {
        const strategy = RetryStrategy(maxAttempts: 0);
        expect(strategy.maxAttempts, equals(0));
      });
    });

    group('predefined strategies', () {
      test('disabled should have zero attempts', () {
        expect(RetryStrategy.disabled.maxAttempts, equals(0));
      });

      test('fast should have quick retries', () {
        expect(RetryStrategy.fast.maxAttempts, equals(5));
        expect(RetryStrategy.fast.initialDelay,
            equals(const Duration(milliseconds: 500)));
        expect(RetryStrategy.fast.backoffFactor, equals(1.5));
      });

      test('standard should have balanced retries', () {
        expect(RetryStrategy.standard.maxAttempts, equals(3));
        expect(RetryStrategy.standard.initialDelay,
            equals(const Duration(seconds: 1)));
        expect(RetryStrategy.standard.backoffFactor, equals(2.0));
      });

      test('conservative should have cautious retries', () {
        expect(RetryStrategy.conservative.maxAttempts, equals(2));
        expect(RetryStrategy.conservative.initialDelay,
            equals(const Duration(seconds: 3)));
        expect(RetryStrategy.conservative.backoffFactor, equals(3.0));
      });
    });

    group('getDelay', () {
      test('should return initialDelay for first retry', () {
        const strategy = RetryStrategy(
          initialDelay: Duration(seconds: 2),
          backoffFactor: 2.0,
          enableJitter: false,
        );

        final delay = strategy.getDelay(0);
        expect(delay, equals(const Duration(seconds: 2)));
      });

      test('should apply exponential backoff', () {
        const strategy = RetryStrategy(
          initialDelay: Duration(seconds: 1),
          backoffFactor: 2.0,
          enableJitter: false,
        );

        // First retry: 1s * 2^0 = 1s
        expect(strategy.getDelay(0), equals(const Duration(seconds: 1)));

        // Second retry: 1s * 2^1 = 2s
        expect(strategy.getDelay(1), equals(const Duration(seconds: 2)));

        // Third retry: 1s * 2^2 = 4s
        expect(strategy.getDelay(2), equals(const Duration(seconds: 4)));

        // Fourth retry: 1s * 2^3 = 8s
        expect(strategy.getDelay(3), equals(const Duration(seconds: 8)));
      });

      test('should cap delay at maxDelay', () {
        const strategy = RetryStrategy(
          initialDelay: Duration(seconds: 1),
          backoffFactor: 2.0,
          maxDelay: Duration(seconds: 5),
          enableJitter: false,
        );

        // Should be capped at 5 seconds
        final delay = strategy.getDelay(10); // Would be 1024s without cap
        expect(delay.inSeconds, lessThanOrEqualTo(5));
      });

      test('should add jitter when enabled', () {
        const strategy = RetryStrategy(
          initialDelay: Duration(seconds: 1),
          backoffFactor: 2.0,
          enableJitter: true,
        );

        // Run multiple times to check jitter adds randomness
        final delays = List.generate(10, (_) => strategy.getDelay(1));

        // Base delay without jitter would be exactly 2 seconds
        // With jitter (0-25%), delays should vary between 2000ms and 2500ms
        for (final delay in delays) {
          expect(delay.inMilliseconds, greaterThanOrEqualTo(2000));
          expect(delay.inMilliseconds, lessThanOrEqualTo(2500));
        }

        // Check that we actually get some variation (not all the same)
        final uniqueDelays = delays.toSet();
        expect(uniqueDelays.length, greaterThan(1));
      });

      test('should handle negative attempt numbers', () {
        const strategy = RetryStrategy();

        final delay = strategy.getDelay(-1);
        expect(delay, equals(Duration.zero));
      });

      test('should handle zero initial delay', () {
        const strategy = RetryStrategy(
          initialDelay: Duration.zero,
          enableJitter: false,
        );

        final delay = strategy.getDelay(0);
        expect(delay, equals(Duration.zero));
      });
    });

    group('canRetry', () {
      test('should return true when within limit', () {
        const strategy = RetryStrategy(maxAttempts: 3);

        expect(strategy.canRetry(0), isTrue);
        expect(strategy.canRetry(1), isTrue);
        expect(strategy.canRetry(2), isTrue);
      });

      test('should return false when at or beyond limit', () {
        const strategy = RetryStrategy(maxAttempts: 3);

        expect(strategy.canRetry(3), isFalse);
        expect(strategy.canRetry(4), isFalse);
        expect(strategy.canRetry(10), isFalse);
      });

      test('should handle zero maxAttempts', () {
        const strategy = RetryStrategy(maxAttempts: 0);

        expect(strategy.canRetry(0), isFalse);
      });

      test('should handle negative attempt numbers', () {
        const strategy = RetryStrategy(maxAttempts: 3);

        expect(strategy.canRetry(-1), isTrue);
      });
    });

    group('shouldRetry', () {
      const strategy = RetryStrategy(maxAttempts: 3);

      group('network errors', () {
        test('should retry on SocketException', () {
          const error = SocketException('Connection failed');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });

        test('should retry on TimeoutException', () {
          final error = TimeoutException('Timeout');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });

        test('should retry on HandshakeException', () {
          const error = HandshakeException('SSL handshake failed');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });
      });

      group('HTTP errors', () {
        test('should retry on 500 server error', () {
          const error = HttpException('HTTP 500: Internal Server Error');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });

        test('should retry on 502 bad gateway', () {
          const error = HttpException('HTTP 502: Bad Gateway');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });

        test('should retry on 503 service unavailable', () {
          const error = HttpException('HTTP 503: Service Unavailable');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });

        test('should retry on 504 gateway timeout', () {
          const error = HttpException('HTTP 504: Gateway Timeout');
          expect(strategy.shouldRetry(error, 0), isTrue);
        });

        test('should not retry on 404 not found', () {
          const error = HttpException('HTTP 404: Not Found');
          expect(strategy.shouldRetry(error, 0), isFalse);
        });

        test('should not retry on other HTTP errors', () {
          const error = HttpException('HTTP 400: Bad Request');
          expect(strategy.shouldRetry(error, 0), isFalse);
        });
      });

      group('file system errors', () {
        test('should not retry on FileSystemException', () {
          const error = FileSystemException('Permission denied');
          expect(strategy.shouldRetry(error, 0), isFalse);
        });
      });

      group('parse errors', () {
        test('should not retry on FormatException', () {
          const error = FormatException('Invalid JSON');
          expect(strategy.shouldRetry(error, 0), isFalse);
        });
      });

      group('UpdateErrorCode', () {
        test('should not retry invalid configuration', () {
          expect(
            strategy.shouldRetry(UpdateErrorCode.configurationInvalid, 0),
            isFalse,
          );
        });

        test('should retry on PACKAGE_DOWNLOAD_FAILED', () {
          expect(
            strategy.shouldRetry(UpdateErrorCode.packageDownloadFailed, 0),
            isTrue,
          );
        });

        test('should not retry on PACKAGE_HASH_MISMATCH', () {
          expect(
            strategy.shouldRetry(UpdateErrorCode.packageHashMismatch, 0),
            isFalse,
          );
        });

        test('should not retry package install failures', () {
          expect(
            strategy.shouldRetry(
              UpdateErrorCode.packageInstallPermissionRequired,
              0,
            ),
            isFalse,
          );
          expect(
            strategy.shouldRetry(UpdateErrorCode.packageFileNotFound, 0),
            isFalse,
          );
          expect(
            strategy.shouldRetry(UpdateErrorCode.packageInstallFailed, 0),
            isFalse,
          );
        });

        test('should not retry background download operation failures', () {
          for (final code in [
            UpdateErrorCode.backgroundDownloadUnavailable,
            UpdateErrorCode.backgroundDownloadNotFound,
            UpdateErrorCode.backgroundDownloadStartRejected,
            UpdateErrorCode.backgroundDownloadInvalidState,
            UpdateErrorCode.backgroundStorageUnavailable,
          ]) {
            expect(strategy.shouldRetry(code, 0), isFalse, reason: code.value);
          }
        });
      });

      group('attempt limit', () {
        test('should not retry when maxAttempts reached', () {
          const error = SocketException('Connection failed');

          // Should retry for attempts 0, 1, 2
          expect(strategy.shouldRetry(error, 0), isTrue);
          expect(strategy.shouldRetry(error, 1), isTrue);
          expect(strategy.shouldRetry(error, 2), isTrue);

          // Should not retry for attempt 3 (maxAttempts = 3)
          expect(strategy.shouldRetry(error, 3), isFalse);
          expect(strategy.shouldRetry(error, 4), isFalse);
        });

        test('should never retry with disabled strategy', () {
          const error = SocketException('Connection failed');
          expect(RetryStrategy.disabled.shouldRetry(error, 0), isFalse);
        });
      });

      test('should not retry on unsupported error types', () {
        final error = Exception('Generic exception');
        expect(strategy.shouldRetry(error, 0), isFalse);
      });
    });

    group('equality and hashCode', () {
      test('should be equal when all properties match', () {
        const strategy1 = RetryStrategy(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 1),
          backoffFactor: 2.0,
          maxDelay: Duration(seconds: 30),
          enableJitter: true,
        );

        const strategy2 = RetryStrategy(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 1),
          backoffFactor: 2.0,
          maxDelay: Duration(seconds: 30),
          enableJitter: true,
        );

        expect(strategy1, equals(strategy2));
        expect(strategy1.hashCode, equals(strategy2.hashCode));
      });

      test('should not be equal when properties differ', () {
        const strategy1 = RetryStrategy(maxAttempts: 3);
        const strategy2 = RetryStrategy(maxAttempts: 5);

        expect(strategy1, isNot(equals(strategy2)));
      });

      test('should be equal to itself', () {
        const strategy = RetryStrategy();
        expect(strategy, equals(strategy));
      });
    });

    group('toString', () {
      test('should contain all important information', () {
        const strategy = RetryStrategy(
          maxAttempts: 3,
          initialDelay: Duration(seconds: 1),
          backoffFactor: 2.0,
          maxDelay: Duration(seconds: 30),
          enableJitter: true,
        );

        final str = strategy.toString();

        expect(str, contains('maxAttempts: 3'));
        expect(str, contains('initialDelay: 1000ms'));
        expect(str, contains('backoffFactor: 2.0'));
        expect(str, contains('maxDelay: 30s'));
        expect(str, contains('enableJitter: true'));
      });
    });
  });
}

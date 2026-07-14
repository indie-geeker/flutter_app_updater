import 'dart:io';

import '../models/update_error_code.dart';

/// Terminal result of a verified package transfer.
class PackageDownloadResult {
  /// Whether the package was downloaded and verified successfully.
  final bool isSuccess;

  /// Final verified artifact file.
  final File? file;

  /// Stable failure code when unsuccessful.
  final UpdateErrorCode? code;

  /// Human-readable failure diagnostic.
  final String? message;

  /// Exact number of verified artifact bytes.
  final int? downloadedBytes;

  /// Lowercase SHA-256 digest of the artifact.
  final String? sha256;

  const PackageDownloadResult._({
    required this.isSuccess,
    this.file,
    this.code,
    this.message,
    this.downloadedBytes,
    this.sha256,
  });

  /// Creates a successful verified-download result.
  const PackageDownloadResult.success({
    required File file,
    required int downloadedBytes,
    String? sha256,
  }) : this._(
          isSuccess: true,
          file: file,
          downloadedBytes: downloadedBytes,
          sha256: sha256,
        );

  /// Creates a failed download result.
  const PackageDownloadResult.failure({
    required UpdateErrorCode code,
    required String message,
  }) : this._(
          isSuccess: false,
          code: code,
          message: message,
        );
}

/// Byte progress reported by a package transfer.
class PackageDownloadProgress {
  /// Number of bytes persisted so far.
  final int downloadedBytes;

  /// Expected exact size, when known.
  final int? totalBytes;

  /// Creates a transfer progress snapshot.
  const PackageDownloadProgress({
    required this.downloadedBytes,
    this.totalBytes,
  });

  /// Clamped progress from zero to one, or `null` without a positive total.
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (downloadedBytes / total).clamp(0.0, 1.0).toDouble();
  }
}

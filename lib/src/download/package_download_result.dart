import 'dart:io';

import '../models/update_error_code.dart';

class PackageDownloadResult {
  final bool isSuccess;
  final File? file;
  final UpdateErrorCode? code;
  final String? message;
  final int? downloadedBytes;
  final String? sha256;

  const PackageDownloadResult._({
    required this.isSuccess,
    this.file,
    this.code,
    this.message,
    this.downloadedBytes,
    this.sha256,
  });

  const PackageDownloadResult.success({
    required File file,
    required int downloadedBytes,
    required String sha256,
  }) : this._(
          isSuccess: true,
          file: file,
          downloadedBytes: downloadedBytes,
          sha256: sha256,
        );

  const PackageDownloadResult.failure({
    required UpdateErrorCode code,
    required String message,
  }) : this._(
          isSuccess: false,
          code: code,
          message: message,
        );
}

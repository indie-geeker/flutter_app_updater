import 'dart:io';

import '../actions/update_action.dart';
import '../models/update_error_code.dart';

abstract interface class UpdateActionExecutor {
  bool supports(UpdateAction action);

  Future<UpdateActionResult> perform(UpdateAction action);
}

class UpdateActionResult {
  final bool isSuccess;
  final UpdateErrorCode? code;
  final String? message;
  final File? file;
  final int? downloadedBytes;
  final String? sha256;

  const UpdateActionResult._({
    required this.isSuccess,
    this.code,
    this.message,
    this.file,
    this.downloadedBytes,
    this.sha256,
  });

  const UpdateActionResult.success({
    File? file,
    int? downloadedBytes,
    String? sha256,
  }) : this._(
          isSuccess: true,
          file: file,
          downloadedBytes: downloadedBytes,
          sha256: sha256,
        );

  const UpdateActionResult.failure({
    required UpdateErrorCode code,
    required String message,
  }) : this._(
          isSuccess: false,
          code: code,
          message: message,
        );
}

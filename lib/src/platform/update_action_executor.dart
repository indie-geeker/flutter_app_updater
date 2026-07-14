import 'dart:io';

import '../actions/update_action.dart';
import '../models/update_error_code.dart';

/// Host or package boundary capable of executing selected update actions.
abstract interface class UpdateActionExecutor {
  /// Whether this executor can safely handle [action].
  bool supports(UpdateAction action);

  /// Performs [action] and returns a terminal structured result.
  Future<UpdateActionResult> perform(UpdateAction action);
}

/// Terminal result of an explicitly executed update action.
class UpdateActionResult {
  /// Whether the action completed successfully.
  final bool isSuccess;

  /// Stable failure code, present only when unsuccessful.
  final UpdateErrorCode? code;

  /// Human-readable failure diagnostic.
  final String? message;

  /// Verified downloaded artifact, when the action produces one.
  final File? file;

  /// Exact artifact byte count, when downloaded.
  final int? downloadedBytes;

  /// Lowercase SHA-256 digest of the downloaded artifact.
  final String? sha256;

  const UpdateActionResult._({
    required this.isSuccess,
    this.code,
    this.message,
    this.file,
    this.downloadedBytes,
    this.sha256,
  });

  /// Creates a successful terminal result with optional artifact metadata.
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

  /// Creates a failed terminal result with stable [code] and [message].
  const UpdateActionResult.failure({
    required UpdateErrorCode code,
    required String message,
  }) : this._(
          isSuccess: false,
          code: code,
          message: message,
        );
}

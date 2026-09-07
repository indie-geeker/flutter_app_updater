part of 'package_downloader.dart';

// Private storage boundary; schema and two-slot recovery stay compatible.
mixin _PackageCheckpointStore {
  static const _checkpointSchemaVersion = 2;
  int get maxDownloadBytes;
  PackageDownloadFileOperations get fileOperations;
  Future<void> _cleanupPartialState(File partialFile, File metadataFile);
  Future<void> _deleteIfExists(File file);
  String? _normalizedSha256(String? value);
  bool _isStrongEtag(String? value);
  Future<_ResumeMetadata?> _readResumeMetadata({
    required ArtifactDescriptor action,
    required File partialFile,
    required File metadataFile,
  }) async {
    final expectedSize = action.packageSizeBytes;
    final expectedSha256 = _normalizedSha256(action.sha256);
    if (expectedSha256 == null) {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }

    final candidates = <_ResumeMetadata>[];
    for (var slot = 0; slot < 2; slot++) {
      final metadata = await _readCheckpointSlot(
        _checkpointSlot(metadataFile, slot),
        slot,
      );
      if (metadata != null &&
          metadata.packageUrlSha256 == _packageUrlSha256(action.packageUrl) &&
          metadata.packageSizeBytes == expectedSize &&
          metadata.sha256 == expectedSha256 &&
          metadata.totalBytes == expectedSize &&
          metadata.downloadedBytes > 0 &&
          metadata.downloadedBytes <= metadata.totalBytes &&
          metadata.downloadedBytes <= maxDownloadBytes &&
          _isStrongEtag(metadata.etag)) {
        candidates.add(metadata);
      }
    }

    if (candidates.isEmpty || !await partialFile.exists()) {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }

    candidates.sort((left, right) => right.revision.compareTo(left.revision));
    final checkpoint = candidates.first;
    final fileLength = await partialFile.length();
    if (fileLength < checkpoint.downloadedBytes) {
      await _cleanupPartialState(partialFile, metadataFile);
      return null;
    }
    if (fileLength > checkpoint.downloadedBytes) {
      RandomAccessFile? file;
      try {
        file = await partialFile.open(mode: FileMode.writeOnlyAppend);
        await file.truncate(checkpoint.downloadedBytes);
        await file.flush();
      } on FileSystemException catch (error, stackTrace) {
        Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
      } finally {
        await file?.close();
      }
    }
    return checkpoint;
  }

  Future<_ResumeMetadata?> _readCheckpointSlot(
    File slotFile,
    int slot,
  ) async {
    if (!await slotFile.exists()) {
      return null;
    }
    try {
      final data = jsonDecode(await fileOperations.readAsString(slotFile));
      if (data is! Map<String, Object?> ||
          data['schemaVersion'] != _checkpointSchemaVersion ||
          data['revision'] is! int ||
          data['packageUrlSha256'] is! String ||
          data['downloadedBytes'] is! int ||
          data['packageSizeBytes'] is! int ||
          data['sha256'] is! String ||
          data['etag'] is! String ||
          data['totalBytes'] is! int) {
        return null;
      }
      final revision = data['revision']! as int;
      if (revision <= 0) {
        return null;
      }
      return _ResumeMetadata(
        slot: slot,
        revision: revision,
        packageUrlSha256:
            (data['packageUrlSha256']! as String).trim().toLowerCase(),
        downloadedBytes: data['downloadedBytes']! as int,
        packageSizeBytes: data['packageSizeBytes']! as int,
        sha256: (data['sha256']! as String).trim().toLowerCase(),
        etag: data['etag']! as String,
        totalBytes: data['totalBytes']! as int,
      );
    } on FormatException {
      return null;
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_CheckpointReadFailure(error), stackTrace);
    }
  }

  bool _canCheckpoint({
    required ArtifactDescriptor action,
    required PackageDownloadResponse response,
    required int? totalBytes,
  }) {
    final expectedSize = action.packageSizeBytes;
    return _normalizedSha256(action.sha256) != null &&
        totalBytes == expectedSize &&
        _isStrongEtag(response.etag);
  }

  Future<_CheckpointPosition> _flushAndCheckpoint({
    required RandomAccessFile file,
    required ArtifactDescriptor action,
    required PackageDownloadResponse response,
    required File metadataFile,
    required int downloadedBytes,
    required int totalBytes,
    required int previousRevision,
    required int previousSlot,
  }) async {
    try {
      await file.flush();
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
    }

    final nextRevision = previousRevision + 1;
    final nextSlot = previousSlot < 0 ? nextRevision % 2 : 1 - previousSlot;
    final slotFile = _checkpointSlot(metadataFile, nextSlot);
    final temporaryFile = File('${slotFile.path}.tmp');
    final metadata = <String, Object?>{
      'schemaVersion': _checkpointSchemaVersion,
      'revision': nextRevision,
      'packageUrlSha256': _packageUrlSha256(action.packageUrl),
      'downloadedBytes': downloadedBytes,
      'packageSizeBytes': action.packageSizeBytes,
      'sha256': _normalizedSha256(action.sha256),
      'etag': response.etag,
      'totalBytes': totalBytes,
    };

    RandomAccessFile? metadataHandle;
    try {
      await _deleteIfExists(temporaryFile);
      metadataHandle = await temporaryFile.open(mode: FileMode.write);
      await metadataHandle.writeFrom(utf8.encode(jsonEncode(metadata)));
      await metadataHandle.flush();
      await metadataHandle.close();
      metadataHandle = null;
      await _deleteIfExists(slotFile);
      await temporaryFile.rename(slotFile.path);
      return _CheckpointPosition(revision: nextRevision, slot: nextSlot);
    } on FileSystemException catch (error, stackTrace) {
      Error.throwWithStackTrace(_StorageFailure(error), stackTrace);
    } finally {
      await metadataHandle?.close();
      await _deleteIfExists(temporaryFile);
    }
  }

  Future<void> _cleanupMetadata(File metadataFile) async {
    await _deleteIfExists(metadataFile);
    for (var slot = 0; slot < 2; slot++) {
      final slotFile = _checkpointSlot(metadataFile, slot);
      await _deleteIfExists(File('${slotFile.path}.tmp'));
      await _deleteIfExists(slotFile);
    }
  }

  File _checkpointSlot(File metadataFile, int slot) {
    return File('${metadataFile.path}.$slot');
  }

  String _packageUrlSha256(Uri url) {
    return crypto.sha256.convert(utf8.encode(url.toString())).toString();
  }
}

class _ResumeMetadata {
  final int slot;
  final int revision;
  final String packageUrlSha256;
  final int downloadedBytes;
  final int packageSizeBytes;
  final String sha256;
  final String etag;
  final int totalBytes;

  const _ResumeMetadata({
    required this.slot,
    required this.revision,
    required this.packageUrlSha256,
    required this.downloadedBytes,
    required this.packageSizeBytes,
    required this.sha256,
    required this.etag,
    required this.totalBytes,
  });
}

class _CheckpointPosition {
  final int revision;
  final int slot;

  const _CheckpointPosition({
    required this.revision,
    required this.slot,
  });
}

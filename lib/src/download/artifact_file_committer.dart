part of 'package_downloader.dart';

// Owns replacement and restoration; caller must hold the download lock.
class _ArtifactFileCommitter {
  final Future<void> Function(File) _deleteIfExists;
  final Future<File> Function(File, String) _rename;
  const _ArtifactFileCommitter(this._deleteIfExists, this._rename);
  Future<File> replace(File partialFile, File targetFile) async {
    final backupFile = File('${targetFile.path}.previous');
    await _deleteIfExists(backupFile);
    final hadTarget = await targetFile.exists();
    if (hadTarget) {
      await _rename(targetFile, backupFile.path);
    }
    try {
      final finalFile = await _rename(partialFile, targetFile.path);
      await _deleteIfExists(backupFile);
      return finalFile;
    } catch (_) {
      if (hadTarget && await backupFile.exists()) {
        await _deleteIfExists(targetFile);
        await _rename(backupFile, targetFile.path);
      }
      rethrow;
    }
  }
}

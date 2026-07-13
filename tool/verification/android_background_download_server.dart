import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _usage = '''
Usage: dart run tool/verification/android_background_download_server.dart [options]

Options:
  --host <loopback-address>  Bind address (default: 127.0.0.1).
  --port <0-65535>           Bind port (default: 18080; 0 chooses a free port).
  --artifact <path>          Artifact to serve (default: deterministic test data).
  --help                     Show this help.
''';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help')) {
    stdout.write(_usage);
    return;
  }

  late final ServerCliOptions options;
  try {
    options = ServerCliOptions.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('Error: ${error.message}');
    stderr.write(_usage);
    exitCode = 64;
    return;
  }

  late final List<int> payload;
  if (options.artifactPath case final path?) {
    final artifact = File(path);
    if (!artifact.existsSync()) {
      stderr.writeln('Error: artifact does not exist: $path');
      exitCode = 66;
      return;
    }
    payload = await artifact.readAsBytes();
  } else {
    payload = List<int>.generate(256 * 1024, (index) => index & 0xff);
  }

  if (payload.isEmpty) {
    stderr.writeln('Error: artifact must not be empty.');
    exitCode = 65;
    return;
  }

  final server = await AndroidBackgroundDownloadServer.start(
    address: InternetAddress(options.host),
    port: options.port,
    payload: payload,
  );
  stdout.writeln('Android background download verification server');
  stdout.writeln('Artifact: ${server.uri.resolve('/artifact')}');
  stdout.writeln('Control:  ${server.uri.resolve('/control')}');
  stdout.writeln('Press Ctrl+C to stop.');

  final signal = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  void stop(ProcessSignal _) {
    if (!signal.isCompleted) {
      signal.complete();
    }
  }

  subscriptions.add(ProcessSignal.sigint.watch().listen(stop));
  if (!Platform.isWindows) {
    subscriptions.add(ProcessSignal.sigterm.watch().listen(stop));
  }

  await signal.future;
  await server.close();
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  stdout.writeln('Server stopped.');
}

final class ServerCliOptions {
  const ServerCliOptions({
    required this.host,
    required this.port,
    required this.artifactPath,
  });

  final String host;
  final int port;
  final String? artifactPath;

  static ServerCliOptions parse(List<String> arguments) {
    var host = InternetAddress.loopbackIPv4.address;
    var port = 18080;
    String? artifactPath;

    for (var index = 0; index < arguments.length; index += 2) {
      final name = arguments[index];
      if (index + 1 >= arguments.length) {
        throw FormatException('missing value for $name');
      }
      final value = arguments[index + 1];
      switch (name) {
        case '--host':
          final address = InternetAddress.tryParse(value);
          if (address == null || !address.isLoopback) {
            throw const FormatException('--host must be a loopback IP address');
          }
          host = address.address;
        case '--port':
          final parsed = int.tryParse(value);
          if (parsed == null || parsed < 0 || parsed > 65535) {
            throw const FormatException('--port must be between 0 and 65535');
          }
          port = parsed;
        case '--artifact':
          if (value.trim().isEmpty) {
            throw const FormatException('--artifact must not be empty');
          }
          artifactPath = value;
        default:
          throw FormatException('unknown argument: $name');
      }
    }

    return ServerCliOptions(
      host: host,
      port: port,
      artifactPath: artifactPath,
    );
  }
}

final class AndroidBackgroundDownloadServer {
  AndroidBackgroundDownloadServer._(this._server, List<int> payload)
      : _payload = Uint8List.fromList(payload),
        _sha256 = sha256.convert(payload).toString(),
        _configuration = _ServerConfiguration.defaults(payload.length);

  final HttpServer _server;
  final Uint8List _payload;
  final String _sha256;
  late _ServerConfiguration _configuration;
  var _artifactRequestSequence = 0;

  Uri get uri => Uri(
        scheme: 'http',
        host: _server.address.address,
        port: _server.port,
      );

  static Future<AndroidBackgroundDownloadServer> start({
    required InternetAddress address,
    required int port,
    required List<int> payload,
  }) async {
    if (!address.isLoopback) {
      throw ArgumentError.value(address.address, 'address', 'must be loopback');
    }
    if (port < 0 || port > 65535) {
      throw RangeError.range(port, 0, 65535, 'port');
    }
    if (payload.isEmpty) {
      throw ArgumentError.value(payload, 'payload', 'must not be empty');
    }

    final httpServer = await HttpServer.bind(address, port);
    final server = AndroidBackgroundDownloadServer._(httpServer, payload);
    httpServer.listen(server._handleRequest);
    return server;
  }

  Future<void> close() => _server.close(force: false);

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      switch ((request.method, request.uri.path)) {
        case ('GET', '/healthz'):
          await _writeJson(request.response, {
            'status': 'ok',
            'length': _payload.length,
            'sha256': _sha256,
          });
        case ('GET', '/control'):
          await _writeJson(request.response, _controlJson());
        case ('POST', '/control'):
          await _updateControl(request);
        case ('GET', '/artifact'):
          await _serveArtifact(request);
        default:
          final knownPath = const {'/healthz', '/control', '/artifact'}
              .contains(request.uri.path);
          request.response.statusCode =
              knownPath ? HttpStatus.methodNotAllowed : HttpStatus.notFound;
          if (knownPath) {
            request.response.headers.set(HttpHeaders.allowHeader, 'GET, POST');
          }
          await request.response.close();
      }
    } on HttpException {
      // A deliberately disconnected response owns and closes its detached socket.
    } catch (error) {
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await _writeJson(request.response, {'error': error.toString()});
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {
          // The response may already be closed or detached.
        }
      }
    }
  }

  Future<void> _updateControl(HttpRequest request) async {
    if (request.headers.contentType?.mimeType != ContentType.json.mimeType) {
      await _badRequest(
          request.response, 'Content-Type must be application/json');
      return;
    }

    try {
      final encoded = await request.fold<List<int>>(
        <int>[],
        (bytes, chunk) {
          if (bytes.length + chunk.length > 64 * 1024) {
            throw const FormatException('control body exceeds 64 KiB');
          }
          return bytes..addAll(chunk);
        },
      );
      final decoded = jsonDecode(utf8.decode(encoded));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('control body must be a JSON object');
      }
      final updated = _configuration.apply(decoded, _payload.length);
      _configuration = updated;
      _artifactRequestSequence = 0;
      await _writeJson(request.response, _controlJson());
    } on FormatException catch (error) {
      await _badRequest(request.response, error.message);
    }
  }

  Map<String, dynamic> _controlJson() => {
        ..._configuration.toJson(),
        'artifactUrl': uri.resolve('/artifact').toString(),
        'length': _payload.length,
        'sha256': _sha256,
      };

  Future<void> _serveArtifact(HttpRequest request) async {
    final configuration = _configuration;
    final sequence = ++_artifactRequestSequence;
    final etag = configuration.etagFor(sequence);
    final response = request.response;
    response.headers
      ..set(HttpHeaders.acceptRangesHeader, 'bytes')
      ..set(HttpHeaders.etagHeader, etag)
      ..contentType = ContentType(
        'application',
        'vnd.android.package-archive',
      );

    switch (configuration.mode) {
      case _ResponseMode.exact416:
        await _writeRangeNotSatisfiable(response, exact: true);
      case _ResponseMode.malformed416:
        await _writeRangeNotSatisfiable(response, exact: false);
      case _ResponseMode.disconnect:
        await _writeDisconnect(response, configuration.disconnectAfterBytes);
      case _ResponseMode.slow:
        await _writeSlow(response, configuration);
      case _ResponseMode.oversizedChunked:
        await _writeOversizedChunked(response, configuration);
      case _ResponseMode.ignoreRange:
        await _writeFull(response);
      case _ResponseMode.range:
        await _writeRangeAware(request, response, etag);
    }
  }

  Future<void> _writeRangeAware(
    HttpRequest request,
    HttpResponse response,
    String etag,
  ) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    if (range == null) {
      await _writeFull(response);
      return;
    }

    final ifRange = request.headers.value(HttpHeaders.ifRangeHeader);
    final strongMatch = !etag.startsWith('W/') && ifRange == etag;
    if (ifRange != null && !strongMatch) {
      await _writeFull(response);
      return;
    }

    final match = RegExp(r'^bytes=(\d+)-$').firstMatch(range);
    final offset = match == null ? null : int.tryParse(match.group(1)!);
    if (offset == null || offset >= _payload.length) {
      await _writeRangeNotSatisfiable(response, exact: true);
      return;
    }

    final end = _payload.length - 1;
    final body = _payload.sublist(offset);
    response
      ..statusCode = HttpStatus.partialContent
      ..contentLength = body.length;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes $offset-$end/${_payload.length}',
    );
    response.add(body);
    await response.close();
  }

  Future<void> _writeFull(HttpResponse response) async {
    response
      ..statusCode = HttpStatus.ok
      ..contentLength = _payload.length
      ..add(_payload);
    await response.close();
  }

  Future<void> _writeRangeNotSatisfiable(
    HttpResponse response, {
    required bool exact,
  }) async {
    response
      ..statusCode = HttpStatus.requestedRangeNotSatisfiable
      ..contentLength = 0;
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      exact ? 'bytes */${_payload.length}' : 'bytes */not-a-number',
    );
    await response.close();
  }

  Future<void> _writeDisconnect(HttpResponse response, int byteCount) async {
    if (byteCount == _payload.length) {
      response
        ..statusCode = HttpStatus.ok
        ..headers.chunkedTransferEncoding = true;
      final socket = await response.detachSocket();
      socket
        ..write('${_payload.length.toRadixString(16)}\r\n')
        ..add(_payload)
        ..write('\r\n');
      await socket.flush();
      // Deliberately omit the terminating `0\r\n\r\n` chunk. The peer receives
      // every artifact byte but must still report an incomplete transfer.
      socket.destroy();
      return;
    }

    response
      ..statusCode = HttpStatus.ok
      ..contentLength = _payload.length;
    final socket = await response.detachSocket();
    socket.add(_payload.sublist(0, byteCount));
    await socket.flush();
    socket.destroy();
  }

  Future<void> _writeSlow(
    HttpResponse response,
    _ServerConfiguration configuration,
  ) async {
    response
      ..statusCode = HttpStatus.ok
      ..contentLength = _payload.length;
    for (var offset = 0; offset < _payload.length;) {
      final end = math.min(offset + configuration.chunkSize, _payload.length);
      response.add(_payload.sublist(offset, end));
      await response.flush();
      offset = end;
      if (offset < _payload.length) {
        await Future<void>.delayed(
          Duration(milliseconds: configuration.delayPerChunkMs),
        );
      }
    }
    await response.close();
  }

  Future<void> _writeOversizedChunked(
    HttpResponse response,
    _ServerConfiguration configuration,
  ) async {
    response
      ..statusCode = HttpStatus.ok
      ..bufferOutput = false;
    final body = Uint8List(_payload.length + configuration.oversizedBytes)
      ..setRange(0, _payload.length, _payload)
      ..fillRange(_payload.length,
          _payload.length + configuration.oversizedBytes, 0xa5);
    for (var offset = 0; offset < body.length;) {
      final end = math.min(offset + configuration.chunkSize, body.length);
      response.add(body.sublist(offset, end));
      offset = end;
    }
    await response.close();
  }
}

enum _ResponseMode {
  range,
  ignoreRange,
  exact416,
  malformed416,
  disconnect,
  slow,
  oversizedChunked,
}

enum _EtagMode { strong, weak, changing }

final class _ServerConfiguration {
  const _ServerConfiguration({
    required this.mode,
    required this.etagMode,
    required this.etagValue,
    required this.disconnectAfterBytes,
    required this.delayPerChunkMs,
    required this.chunkSize,
    required this.oversizedBytes,
  });

  factory _ServerConfiguration.defaults(int payloadLength) =>
      _ServerConfiguration(
        mode: _ResponseMode.range,
        etagMode: _EtagMode.strong,
        etagValue: 'verification-v1',
        disconnectAfterBytes: math.max(1, payloadLength ~/ 2),
        delayPerChunkMs: 50,
        chunkSize: math.min(16 * 1024, payloadLength),
        oversizedBytes: 1024,
      );

  final _ResponseMode mode;
  final _EtagMode etagMode;
  final String etagValue;
  final int disconnectAfterBytes;
  final int delayPerChunkMs;
  final int chunkSize;
  final int oversizedBytes;

  String etagFor(int sequence) {
    final value =
        etagMode == _EtagMode.changing ? '$etagValue-$sequence' : etagValue;
    final quoted = '"$value"';
    return etagMode == _EtagMode.weak ? 'W/$quoted' : quoted;
  }

  _ServerConfiguration apply(Map<String, dynamic> patch, int payloadLength) {
    const knownKeys = {
      'mode',
      'etagMode',
      'etagValue',
      'disconnectAfterBytes',
      'delayPerChunkMs',
      'chunkSize',
      'oversizedBytes',
    };
    final unknown = patch.keys.where((key) => !knownKeys.contains(key));
    if (unknown.isNotEmpty) {
      throw FormatException('unknown control field: ${unknown.first}');
    }

    final nextMode = _enumValue(
      _ResponseMode.values,
      patch['mode'],
      mode,
      'mode',
    );
    final nextEtagMode = _enumValue(
      _EtagMode.values,
      patch['etagMode'],
      etagMode,
      'etagMode',
    );
    final nextEtagValue = patch['etagValue'] ?? etagValue;
    if (nextEtagValue is! String ||
        !RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(nextEtagValue)) {
      throw const FormatException(
        'etagValue must contain 1-128 letters, digits, dot, dash, or underscore',
      );
    }

    final nextDisconnect = _positiveInt(
      patch['disconnectAfterBytes'],
      disconnectAfterBytes,
      'disconnectAfterBytes',
      maximum: payloadLength,
    );
    final nextDelay = _nonNegativeInt(
      patch['delayPerChunkMs'],
      delayPerChunkMs,
      'delayPerChunkMs',
      maximum: 60 * 1000,
    );
    final nextChunkSize = _positiveInt(
      patch['chunkSize'],
      chunkSize,
      'chunkSize',
      maximum: 1024 * 1024,
    );
    final nextOversized = _positiveInt(
      patch['oversizedBytes'],
      oversizedBytes,
      'oversizedBytes',
      maximum: 64 * 1024 * 1024,
    );

    return _ServerConfiguration(
      mode: nextMode,
      etagMode: nextEtagMode,
      etagValue: nextEtagValue,
      disconnectAfterBytes: nextDisconnect,
      delayPerChunkMs: nextDelay,
      chunkSize: nextChunkSize,
      oversizedBytes: nextOversized,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.name,
        'etagMode': etagMode.name,
        'etagValue': etagValue,
        'disconnectAfterBytes': disconnectAfterBytes,
        'delayPerChunkMs': delayPerChunkMs,
        'chunkSize': chunkSize,
        'oversizedBytes': oversizedBytes,
      };
}

T _enumValue<T extends Enum>(
  List<T> values,
  Object? candidate,
  T fallback,
  String field,
) {
  if (candidate == null) {
    return fallback;
  }
  if (candidate is! String) {
    throw FormatException('$field must be a string');
  }
  for (final value in values) {
    if (value.name == candidate) {
      return value;
    }
  }
  throw FormatException('invalid $field: $candidate');
}

int _positiveInt(
  Object? candidate,
  int fallback,
  String field, {
  required int maximum,
}) {
  final value = candidate ?? fallback;
  if (value is! int || value <= 0 || value > maximum) {
    throw FormatException('$field must be between 1 and $maximum');
  }
  return value;
}

int _nonNegativeInt(
  Object? candidate,
  int fallback,
  String field, {
  required int maximum,
}) {
  final value = candidate ?? fallback;
  if (value is! int || value < 0 || value > maximum) {
    throw FormatException('$field must be between 0 and $maximum');
  }
  return value;
}

Future<void> _writeJson(
  HttpResponse response,
  Map<String, dynamic> value,
) async {
  final bytes = utf8.encode(jsonEncode(value));
  response
    ..statusCode = HttpStatus.ok
    ..headers.contentType = ContentType.json
    ..contentLength = bytes.length
    ..add(bytes);
  await response.close();
}

Future<void> _badRequest(HttpResponse response, String message) async {
  response.statusCode = HttpStatus.badRequest;
  final bytes = utf8.encode(jsonEncode({'error': message}));
  response
    ..headers.contentType = ContentType.json
    ..contentLength = bytes.length
    ..add(bytes);
  await response.close();
}

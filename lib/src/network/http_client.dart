import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/update_error.dart';
import '../utils/update_logger.dart';

/// 网络请求管理类
///
/// 负责处理HTTP请求，统一管理网络请求逻辑
/// 使用单例模式复用HttpClient以提高性能和避免资源泄漏
class HttpClientManager {
  /// 单例实例
  static final HttpClientManager _instance = HttpClientManager._internal();

  /// 共享的HttpClient实例，复用TCP连接
  static final HttpClient _sharedClient = HttpClient();

  /// 默认连接超时时间
  static const Duration _defaultTimeout = Duration(seconds: 30);

  /// 获取单例实例
  factory HttpClientManager() => _instance;

  HttpClientManager._internal() {
    // 配置共享客户端
    _sharedClient.connectionTimeout = _defaultTimeout;
    // 设置连接池参数以优化性能
    _sharedClient.maxConnectionsPerHost = 5;
  }

  /// 释放资源（仅在应用退出时调用）
  void dispose() {
    _sharedClient.close(force: true);
  }

  /// 执行GET请求
  /// 
  /// [url] 请求URL
  /// [headers] 可选的请求头
  /// [timeout] 超时时间，默认30秒
  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return _request(
      url: url,
      method: 'GET',
      headers: headers,
      timeout: timeout,
    );
  }

  /// 执行POST请求
  /// 
  /// [url] 请求URL
  /// [body] 请求体数据
  /// [headers] 可选的请求头
  /// [timeout] 超时时间，默认30秒
  Future<Map<String, dynamic>> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return _request(
      url: url,
      method: 'POST',
      body: body,
      headers: headers,
      timeout: timeout,
    );
  }

  /// 通用请求方法
  /// 
  /// [url] 请求URL
  /// [method] 请求方法，如GET、POST等
  /// [body] 请求体数据
  /// [headers] 可选的请求头
  /// [timeout] 超时时间，默认30秒
  Future<Map<String, dynamic>> _request({
    required String url,
    required String method,
    dynamic body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (url.isEmpty) {
      throw const UpdateError(
        code: 'MISSING_URL',
        message: '没有提供URL',
      );
    }

    try {
      // 打印请求信息
      UpdateLogger.debug('===== HTTP 请求开始 =====', tag: 'HttpClient');
      UpdateLogger.debug('URL: $url', tag: 'HttpClient');
      UpdateLogger.debug('方法: $method', tag: 'HttpClient');
      if (headers != null) {
        UpdateLogger.debug('请求头: ${jsonEncode(headers)}', tag: 'HttpClient');
      }
      if (body != null) {
        UpdateLogger.debug('请求体: ${body is String ? body : jsonEncode(body)}', tag: 'HttpClient');
      }
      UpdateLogger.debug('========================', tag: 'HttpClient');

      // 使用共享的HttpClient实例，复用TCP连接
      // 超时时间通过request.close().timeout()控制，而不是修改共享实例的配置

      // 创建请求
      HttpClientRequest request;
      if (method == 'GET') {
        request = await _sharedClient.getUrl(Uri.parse(url));
      } else if (method == 'POST') {
        request = await _sharedClient.postUrl(Uri.parse(url));
      } else {
        throw const UpdateError(
          code: 'INVALID_METHOD',
          message: '不支持的HTTP方法',
        );
      }

      // 添加请求头
      if (headers != null) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      // 添加请求体
      if (body != null) {
        if (body is Map || body is List) {
          final jsonBody = jsonEncode(body);
          request.headers.contentType = ContentType.json;
          request.write(jsonBody);
        } else if (body is String) {
          request.write(body);
        } else {
          throw const UpdateError(
            code: 'INVALID_BODY',
            message: '不支持的请求体类型',
          );
        }
      }

      // 发送请求并获取响应（使用传入的超时参数）
      final response = await request.close().timeout(timeout);

      if (response.statusCode != 200) {
        throw UpdateError.server(
          'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      // 读取响应内容
      final responseBody = await response.transform(utf8.decoder).join();

      // 打印响应信息
      UpdateLogger.debug('===== HTTP 响应 =====', tag: 'HttpClient');
      UpdateLogger.debug('状态码: ${response.statusCode}', tag: 'HttpClient');
      UpdateLogger.debug('响应头: ${response.headers}', tag: 'HttpClient');
      // 限制打印长度以避免过长的响应
      final printableResponse = responseBody.length > 1000
          ? '${responseBody.substring(0, 1000)}... (截断，完整长度: ${responseBody.length})'
          : responseBody;
      UpdateLogger.debug('响应体: $printableResponse', tag: 'HttpClient');
      UpdateLogger.debug('=====================', tag: 'HttpClient');

      // 解析JSON
      try {
        final data = json.decode(responseBody) as Map<String, dynamic>;
        // 打印解析后的JSON数据（美化格式）
        UpdateLogger.debug('解析的JSON数据: ${_prettyJson(data)}', tag: 'HttpClient');
        return data;
      } catch (e) {
        throw UpdateError.parse(e);
      }
    } catch (e) {
      if (e is UpdateError) {
        rethrow;
      }

      if (e is SocketException || e is TimeoutException) {
        throw UpdateError.network(e);
      }

      throw UpdateError.server(e);
    }
  }
  
  /// 格式化JSON为易读格式
  String _prettyJson(Map<String, dynamic> json) {
    try {
      const encoder = JsonEncoder.withIndent('  ');
      final prettyString = encoder.convert(json);
      // 如果JSON太长，只返回前面的部分
      if (prettyString.length > 1000) {
        return '${prettyString.substring(0, 1000)}... (截断，完整长度: ${prettyString.length})';
      }
      return prettyString;
    } catch (e) {
      return json.toString();
    }
  }
}

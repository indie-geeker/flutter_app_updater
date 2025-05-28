import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../models/update_error.dart';

/// 网络请求管理类
///
/// 负责处理HTTP请求，统一管理网络请求逻辑
class HttpClientManager {
  /// 单例实例
  static final HttpClientManager _instance = HttpClientManager._internal();

  /// 获取单例实例
  factory HttpClientManager() => _instance;

  HttpClientManager._internal();

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
      debugPrint('===== HTTP 请求开始 =====');
      debugPrint('URL: $url');
      debugPrint('方法: $method');
      if (headers != null) {
        debugPrint('请求头: ${jsonEncode(headers)}');
      }
      if (body != null) {
        debugPrint('请求体: ${body is String ? body : jsonEncode(body)}');
      }
      debugPrint('========================');
      
      final client = HttpClient();
      client.connectionTimeout = timeout;

      try {
        // 创建请求
        HttpClientRequest request;
        if (method == 'GET') {
          request = await client.getUrl(Uri.parse(url));
        } else if (method == 'POST') {
          request = await client.postUrl(Uri.parse(url));
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

        // 发送请求并获取响应
        final response = await request.close().timeout(timeout);

        if (response.statusCode != 200) {
          throw UpdateError.server(
            'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          );
        }

        // 读取响应内容
        final responseBody = await response.transform(utf8.decoder).join();
        
        // 打印响应信息
        debugPrint('===== HTTP 响应 =====');
        debugPrint('状态码: ${response.statusCode}');
        debugPrint('响应头: ${response.headers}');
        // 限制打印长度以避免过长的响应
        final printableResponse = responseBody.length > 1000 
            ? '${responseBody.substring(0, 1000)}... (截断，完整长度: ${responseBody.length})' 
            : responseBody;
        debugPrint('响应体: $printableResponse');
        debugPrint('=====================');

        // 解析JSON
        try {
          final data = json.decode(responseBody) as Map<String, dynamic>;
          // 打印解析后的JSON数据（美化格式）
          debugPrint('解析的JSON数据: ${_prettyJson(data)}');
          return data;
        } catch (e) {
          throw UpdateError.parse(e);
        }
      } finally {
        client.close();
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

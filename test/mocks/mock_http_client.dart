import 'dart:async';
import 'package:flutter_app_updater/src/models/update_error.dart';

/// Mock HTTP Client for testing purposes
///
/// This mock allows you to simulate different HTTP responses and errors
/// without making actual network calls.
class MockHttpClient {
  /// The response data to return when get() is called
  Map<String, dynamic>? _responseData;

  /// The error to throw when get() or post() is called
  Object? _error;

  /// Delay before returning response (simulates network latency)
  Duration _delay = Duration.zero;

  /// Number of times get() has been called
  int getCallCount = 0;

  /// Number of times post() has been called
  int postCallCount = 0;

  /// Last URL that was requested
  String? lastUrl;

  /// Last headers that were sent
  Map<String, String>? lastHeaders;

  /// Last body that was sent (for POST requests)
  dynamic lastBody;

  /// Set the response data that will be returned
  void setResponseData(Map<String, dynamic> data) {
    _responseData = data;
    _error = null;
  }

  /// Set an error that will be thrown
  void setError(Object error) {
    _error = error;
    _responseData = null;
  }

  /// Set network delay to simulate slow connections
  void setDelay(Duration delay) {
    _delay = delay;
  }

  /// Reset all mock state
  void reset() {
    _responseData = null;
    _error = null;
    _delay = Duration.zero;
    getCallCount = 0;
    postCallCount = 0;
    lastUrl = null;
    lastHeaders = null;
    lastBody = null;
  }

  /// Simulate a successful response
  void mockSuccessResponse({
    required String version,
    required String downloadUrl,
    String changelog = 'Bug fixes and improvements',
    bool isForceUpdate = false,
    int? fileSize,
    String? md5,
    Map<String, dynamic>? extraFields,
  }) {
    final response = <String, dynamic>{
      'version': version,
      'downloadUrl': downloadUrl,
      'changelog': changelog,
      'isForceUpdate': isForceUpdate,
      if (fileSize != null) 'fileSize': fileSize,
      if (md5 != null) 'md5': md5,
      if (extraFields != null) ...extraFields,
    };
    setResponseData(response);
  }

  /// Simulate a network error
  void mockNetworkError() {
    setError(UpdateError.network('Network connection failed'));
  }

  /// Simulate a server error
  void mockServerError({int statusCode = 500}) {
    setError(UpdateError.server('HTTP $statusCode: Server Error'));
  }

  /// Simulate a timeout error
  void mockTimeoutError() {
    setError(TimeoutException('Request timeout'));
  }

  /// Simulate a parse error
  void mockParseError() {
    setError(UpdateError.parse('Invalid JSON format'));
  }

  /// Mock GET request
  Future<Map<String, dynamic>> get(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    getCallCount++;
    lastUrl = url;
    lastHeaders = headers;

    // Simulate network delay
    if (_delay > Duration.zero) {
      await Future.delayed(_delay);
    }

    // Throw error if configured
    if (_error != null) {
      throw _error!;
    }

    // Return response data
    if (_responseData != null) {
      return _responseData!;
    }

    // Default error if no response configured
    throw const UpdateError(
      code: 'NO_MOCK_RESPONSE',
      message: 'Mock HTTP client has no response configured',
    );
  }

  /// Mock POST request
  Future<Map<String, dynamic>> post(
    String url, {
    dynamic body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    postCallCount++;
    lastUrl = url;
    lastHeaders = headers;
    lastBody = body;

    // Simulate network delay
    if (_delay > Duration.zero) {
      await Future.delayed(_delay);
    }

    // Throw error if configured
    if (_error != null) {
      throw _error!;
    }

    // Return response data
    if (_responseData != null) {
      return _responseData!;
    }

    // Default error if no response configured
    throw const UpdateError(
      code: 'NO_MOCK_RESPONSE',
      message: 'Mock HTTP client has no response configured',
    );
  }

  /// Verify that get() was called with specific URL
  bool wasGetCalledWith(String url) {
    return lastUrl == url && getCallCount > 0;
  }

  /// Verify that post() was called with specific URL
  bool wasPostCalledWith(String url) {
    return lastUrl == url && postCallCount > 0;
  }
}

/// Create a mock update response for testing
Map<String, dynamic> createMockUpdateResponse({
  String version = '2.0.0',
  String downloadUrl = 'https://example.com/app.apk',
  String changelog = 'Bug fixes',
  bool isForceUpdate = false,
  int? fileSize,
  String? md5,
  String? publishDate,
}) {
  return {
    'version': version,
    'downloadUrl': downloadUrl,
    'changelog': changelog,
    'isForceUpdate': isForceUpdate,
    if (fileSize != null) 'fileSize': fileSize,
    if (md5 != null) 'md5': md5,
    if (publishDate != null) 'publishDate': publishDate,
  };
}

/// Create a custom field mock response
Map<String, dynamic> createCustomFieldMockResponse({
  required String versionKey,
  required String downloadUrlKey,
  String version = '2.0.0',
  String downloadUrl = 'https://example.com/app.apk',
  Map<String, dynamic>? extraFields,
}) {
  return {
    versionKey: version,
    downloadUrlKey: downloadUrl,
    if (extraFields != null) ...extraFields,
  };
}

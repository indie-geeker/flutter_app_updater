import 'dart:async';
import 'dart:convert';
import 'dart:math';

/// 模拟更新API服务
/// 
/// 用于测试应用内更新框架的不同场景
class MockUpdateApi {
  /// 当前版本号
  static const currentVersion = '1.0.0';
  
  /// 新版本号
  static const newVersion = '1.1.0';
  
  /// 延迟时间（毫秒）
  final int _delay;
  
  /// 是否模拟网络错误
  final bool _simulateError;
  
  /// 是否强制更新
  final bool _forceUpdate;
  
  MockUpdateApi({
    int delay = 1000,
    bool simulateError = false,
    bool forceUpdate = false,
  })  : _delay = delay,
        _simulateError = simulateError,
        _forceUpdate = forceUpdate;

  /// 检查更新
  Future<Map<String, dynamic>> checkUpdate() async {
    // 模拟网络延迟
    await Future.delayed(Duration(milliseconds: _delay));
    
    // 模拟网络错误
    if (_simulateError) {
      throw Exception('网络请求失败');
    }
    
    // 返回更新信息
    return {
      'version': newVersion,
      'downloadUrl': 'https://example.com/app-$newVersion.apk',
      'description': '1. 修复了一些已知问题\n'
          '2. 优化了应用性能\n'
          '3. 增加了新功能: 深色模式支持\n'
          '4. 更新了UI设计，提升用户体验',
      'isForceUpdate': _forceUpdate,
      'publishDate': DateTime.now().toIso8601String(),
      'fileSize': 20 * 1024 * 1024, // 20MB
      'md5': 'abc123def456',
    };
  }
  
  /// 模拟下载进度
  StreamController<double> simulateDownloadProgress() {
    final controller = StreamController<double>();
    double progress = 0.0;
    
    // 每100毫秒更新一次进度
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      // 随机增加一点进度(0-2%)
      progress += Random().nextDouble() * 0.02;
      
      if (progress >= 1.0) {
        progress = 1.0;
        controller.add(progress);
        timer.cancel();
        controller.close();
      } else {
        controller.add(progress);
      }
      
      // 模拟网络波动
      if (Random().nextDouble() < 0.05) {
        // 5%的概率暂停一会
        timer.cancel();
        Future.delayed(const Duration(seconds: 1), () {
          timer.cancel();
          // 继续进度更新
          Timer.periodic(const Duration(milliseconds: 100), (newTimer) {
            timer = newTimer;
            // 随机增加一点进度(0-2%)
            progress += Random().nextDouble() * 0.02;
            
            if (progress >= 1.0) {
              progress = 1.0;
              controller.add(progress);
              timer.cancel();
              controller.close();
            } else {
              controller.add(progress);
            }
          });
        });
      }
    });
    
    return controller;
  }
  
  /// 创建用于测试的HTTP响应文本
  static String createMockResponse({
    String version = newVersion,
    bool forceUpdate = false,
    String? downloadUrl,
  }) {
    final data = {
      'version': version,
      'downloadUrl': downloadUrl ?? 'https://example.com/app-$version.apk',
      'description': '1. 修复了一些已知问题\n'
          '2. 优化了应用性能\n'
          '3. 增加了新功能: 深色模式支持',
      'isForceUpdate': forceUpdate,
      'publishDate': DateTime.now().toIso8601String(),
      'fileSize': 15 * 1024 * 1024, // 15MB
    };
    
    return jsonEncode(data);
  }
}

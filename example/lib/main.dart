import 'dart:developer' as developer;

import 'package:app_updater/app_updater.dart';
import 'package:flutter/material.dart';

import 'mock_api.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '应用内更新示例',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 更新服务实例
  late AppUpdateService _updateService;
  
  // 更新配置参数
  bool _forceUpdate = false;
  bool _simulateError = false;
  int _networkDelay = 1000;
  
  // 当前更新状态
  String _updateStatus = '准备就绪';
  
  @override
  void initState() {
    super.initState();
    // 初始化更新服务
    _initUpdateService();
  }
  
  // 初始化更新服务
  void _initUpdateService() {
    // 创建模拟 API
    final mockApi = MockUpdateApi(
      delay: _networkDelay,
      simulateError: _simulateError,
      forceUpdate: _forceUpdate,
    );
    
    // 创建更新服务
    _updateService = AppUpdateService(
      currentVersion: MockUpdateApi.currentVersion,
      onCheckUpdate: mockApi.checkUpdate,
    );
    
    // 初始化服务（不要自动检查更新）
    _updateService.init(checkOnInit: false);
    
    // 监听更新状态变化
    _updateService.controller.statusStream.listen((status) {
      setState(() {
        _updateStatus = _getStatusText(status);
      });
      developer.log('更新状态变化: $status');
    });
    
    // 监听错误信息
    _updateService.controller.errorStream.listen((error) {
      developer.log('更新错误: ${error.code} - ${error.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新错误: ${error.message}'),
          backgroundColor: Colors.red,
        ),
      );
    });
  }
  
  // 获取状态文本
  String _getStatusText(AppUpdateStatus status) {
    switch (status) {
      case AppUpdateStatus.idle:
        return '准备就绪';
      case AppUpdateStatus.checking:
        return '正在检查更新...';
      case AppUpdateStatus.available:
        return '发现新版本: ${_updateService.controller.updateInfo?.version}';
      case AppUpdateStatus.notAvailable:
        return '已是最新版本';
      case AppUpdateStatus.downloading:
        final progress = _updateService.controller.progress;
        if (progress != null) {
          return '正在下载: ${progress.progressPercentage}%';
        }
        return '正在下载...';
      case AppUpdateStatus.paused:
        return '下载已暂停';
      case AppUpdateStatus.downloaded:
        return '下载完成，可以安装';
      case AppUpdateStatus.canceled:
        return '下载已取消';
      case AppUpdateStatus.error:
        return '发生错误: ${_updateService.controller.error?.message}';
      default:
        return '未知状态';
    }
  }
  
  // 检查更新并显示对话框
  void _checkForUpdates() async {
    try {
      // 重新初始化服务（使用当前配置）
      _initUpdateService();
      
      // 检查更新并显示对话框
      final updateInfo = await _updateService.checkForUpdate(
        showDialogIfAvailable: true,
        context: context,
      );
      
      if (updateInfo == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的更新')),
        );
      }
    } catch (e) {
      developer.log('检查更新时出错: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新时出错: $e')),
      );
    }
  }
  
  // 检查更新但使用自定义对话框
  void _checkWithCustomDialog() async {
    try {
      // 重新初始化服务
      _initUpdateService();
      
      // 检查更新
      final updateInfo = await _updateService.controller.checkForUpdate();
      
      if (updateInfo != null) {
        if (!mounted) return;
        
        // 使用自定义对话框
        await _updateService.showUpdateDialog(
          context: context,
          updateInfo: updateInfo,
          dialogBuilder: (context, info) {
            return _buildCustomDialog(context, info);
          },
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的更新')),
        );
      }
    } catch (e) {
      developer.log('检查更新时出错: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('检查更新时出错: $e')),
      );
    }
  }
  
  // 构建自定义更新对话框
  Widget _buildCustomDialog(BuildContext context, AppUpdateInfo updateInfo) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.system_update, color: Colors.blue.shade700),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '发现新版本',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '版本 ${updateInfo.version}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // 更新内容
            const SizedBox(height: 20),
            const Text(
              '更新内容:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(updateInfo.description),
            ),
            
            // 按钮
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!updateInfo.isForceUpdate)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('暂不更新'),
                  ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _updateService.downloadUpdate(autoInstall: true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('立即更新'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('应用内更新示例'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 显示当前版本和状态
            Text('当前版本: ${MockUpdateApi.currentVersion}'),
            const SizedBox(height: 4),
            Text('更新状态: $_updateStatus'),
            
            const Divider(height: 32),
            
            // 更新配置选项
            const Text('测试配置:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            
            // 强制更新开关
            SwitchListTile(
              title: const Text('强制更新'),
              subtitle: const Text('开启后将显示强制更新对话框'),
              value: _forceUpdate,
              onChanged: (value) {
                setState(() {
                  _forceUpdate = value;
                });
              },
            ),
            
            // 模拟错误开关
            SwitchListTile(
              title: const Text('模拟网络错误'),
              subtitle: const Text('开启后将模拟网络请求失败'),
              value: _simulateError,
              onChanged: (value) {
                setState(() {
                  _simulateError = value;
                });
              },
            ),
            
            // 网络延迟滑块
            ListTile(
              title: const Text('模拟网络延迟'),
              subtitle: Text('${_networkDelay}ms'),
              trailing: SizedBox(
                width: 150,
                child: Slider(
                  min: 0,
                  max: 5000,
                  divisions: 10,
                  label: '${_networkDelay}ms',
                  value: _networkDelay.toDouble(),
                  onChanged: (value) {
                    setState(() {
                      _networkDelay = value.toInt();
                    });
                  },
                ),
              ),
            ),
            
            const Divider(height: 32),
            
            // 操作按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // 检查更新按钮
                ElevatedButton(
                  onPressed: _checkForUpdates,
                  child: const Text('检查更新'),
                ),
                
                // 使用自定义对话框
                OutlinedButton(
                  onPressed: _checkWithCustomDialog,
                  child: const Text('使用自定义对话框'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }
}

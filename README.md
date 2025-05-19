# App Updater

轻量级的Flutter应用内更新框架，专为不同项目需求设计，支持完全自定义UI和后台下载功能。

## 特点

- **轻量级**：不依赖第三方库，完全使用Flutter原生功能
- **模块化**：各个功能模块分离，易于维护和扩展
- **可定制**：更新对话框UI可以完全自定义
- **功能完整**：
  - 支持强制更新和可选更新
  - 下载进度显示
  - 断点续传
  - 后台下载
  - 适应不同API响应格式

## 开始使用

1. 在`pubspec.yaml`中添加依赖：

```yaml
dependencies:
  app_updater: ^1.0.0
```

2. 导入包：

```dart
import 'package:app_updater/app_updater.dart';
```

## 基本用法

### 创建更新服务

```dart
// 创建更新服务
final updateService = AppUpdateService(
  currentVersion: '1.0.0',      // 当前版本
  updateUrl: 'https://your-api.com/check-update',  // 更新检查API
);

// 初始化服务并自动检查更新
updateService.init(checkOnInit: true);
```

### 检查更新并显示对话框

```dart
void checkForUpdates(BuildContext context) async {
  await updateService.checkForUpdate(
    showDialogIfAvailable: true,
    context: context,
  );
}
```

### 自定义API字段映射

对于不同的API返回格式，可以自定义字段映射：

```dart
final updateService = AppUpdateService(
  currentVersion: '1.0.0',
  updateUrl: 'https://your-api.com/check-update',
  versionKey: 'appVersion',              // 自定义版本号字段名
  downloadUrlKey: 'appDownloadLink',     // 自定义下载地址字段名
  descriptionKey: 'updateDescription',   // 自定义描述字段名
  isForceUpdateKey: 'forceUpdate',       // 自定义强制更新字段名
);
```

### 使用自定义更新检查逻辑

```dart
final updateService = AppUpdateService(
  currentVersion: '1.0.0',
  onCheckUpdate: () async {
    // 自定义获取更新信息的逻辑
    final response = await yourApiClient.checkForUpdates();
    return response.data;
  },
);
```

### 自定义更新对话框

```dart
updateService.showUpdateDialog(
  context: context,
  updateInfo: updateInfo,
  dialogBuilder: (context, updateInfo) {
    return MyCustomUpdateDialog(
      updateInfo: updateInfo,
      controller: updateService.controller,
    );
  },
);
```

## 高级用法

### 监听更新状态变化

```dart
updateService.controller.statusStream.listen((status) {
  switch (status) {
    case AppUpdateStatus.downloaded:
      showToast('更新已下载完成，准备安装');
      break;
    case AppUpdateStatus.error:
      showToast('更新出错：${updateService.controller.error?.message}');
      break;
    // 处理其他状态...
  }
});
```

### 控制下载过程

```dart
// 暂停下载
await updateService.controller.pauseDownload();

// 恢复下载
await updateService.controller.resumeDownload();

// 取消下载
await updateService.controller.cancelDownload();
```

## 最佳实践

1. **在启动时检查更新**：在应用启动后的适当时机检查更新
2. **合理设置更新检查间隔**：避免频繁检查消耗用户流量
3. **自定义UI以符合应用风格**：确保更新对话框与应用整体风格一致
4. **妥善处理强制更新**：强制更新时应明确告知用户并阻止继续使用旧版本
5. **提供详细的更新日志**：让用户了解新版本的改进和新功能

## 贡献

欢迎提交问题和功能请求！如果您想贡献代码，请提交 Pull Request。

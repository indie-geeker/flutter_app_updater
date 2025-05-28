# Flutter App Updater

轻量级的Flutter应用内更新框架，专为不同项目需求设计，支持完全自定义UI和下载功能。

## 特点

- **轻量级**：不依赖第三方库，完全使用Flutter原生功能
- **模块化**：各个功能模块分离，易于维护和扩展
- **可定制**：更新对话框UI可以完全自定义
- **功能完整**：
  - 支持强制更新和可选更新
  - 下载进度显示
  - 适应不同API响应格式

## 安装

在`pubspec.yaml`文件中添加依赖：

```yaml
dependencies:
  flutter_app_updater: ^0.1.0
```

然后运行：

```bash
flutter pub get
```

## 基本使用

```dart
import 'package:flutter_app_updater/flutter_app_updater.dart';

// 创建更新服务
final updater = FlutterAppUpdater(
  updateUrl: "https://your-api.com/update.json",
  versionKey: "newVersionCode",        // 版本号字段
  downloadUrlKey: "apkUrl",            // 下载链接字段
  changeLogKey: "updateMessage",       // 更新日志字段
  isForceUpdateKey: "forceUpdate"      // 是否强制更新字段
);

// 初始化
avoid main() {
  updater.init();
  // ...
}

// 检查更新
void checkUpdate() async {
  try {
    // 检查更新，设置showDialogIfAvailable为false，手动控制对话框显示
    final updateInfo = await updater.checkForUpdate(
      showDialogIfAvailable: false,
    );

    if (updateInfo != null) {
      print('新版本: ${updateInfo.newVersion}');
      print('下载链接: ${updateInfo.downloadUrl}');
      print('更新日志: ${updateInfo.changelog}');
      
      // 显示更新对话框
      await updater.showUpdateDialog(
        context: context,
        updateInfo: updateInfo,
      );
    } else {
      print('已经是最新版本');
    }
  } catch (e) {
    print('检查更新错误: $e');
  }
}
```

## 自定义更新对话框

您可以完全自定义更新对话框的UI：

```dart
updater.showUpdateDialog(
  context: context,
  updateInfo: updateInfo,
  dialogBuilder: (context, updateInfo) {
    return AlertDialog(
      title: Text('发现新版本 ${updateInfo.newVersion}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('更新内容：'),
          Text(updateInfo.changelog),
        ],
      ),
      actions: [
        if (!updateInfo.isForceUpdate)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('稍后再说'),
          ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            // 开始下载更新
            final file = await updater.downloadUpdate(
              autoInstall: true,  // 下载完成后自动安装
            );
          },
          child: Text('立即更新'),
        ),
      ],
    );
  },
);
```

## 高级配置

### 初始化参数

```dart
// 初始化时可配置自动检查
await updater.init(
  checkOnInit: true,        // 初始化时检查更新
  checkInterval: 24,        // 每24小时自动检查一次（设为null禁用自动检查）
);
```

### 下载更新

```dart
final file = await updater.downloadUpdate(
  savePath: "/storage/download/",  // 保存路径
  autoInstall: true,              // 下载后自动安装
  showNotification: true,         // 显示下载通知
);
```

### 手动安装

```dart
await updater.installUpdate();
```

### 获取版本信息

```dart
String? platformVersion = await updater.getPlatformVersion();
String? appVersionCode = await updater.getAppVersionCode();
String? appVersionName = await updater.getAppVersionName();
```

### 资源释放

```dart
@override
void dispose() {
  updater.dispose();  // 释放资源（定时器等）
  super.dispose();
}
```

## 自定义API处理

您可以在FlutterAppUpdater构造函数中传入自定义的onCheckUpdate函数来覆盖默认的更新检查逻辑：

```dart
final updater = FlutterAppUpdater(
  onCheckUpdate: () async {
    // 自定义更新检查逻辑
    final response = await customApiCall();
    return UpdateInfo(
      newVersion: response['version'],
      downloadUrl: response['downloadUrl'],
      changelog: response['releaseNotes'],
      isForceUpdate: response['mandatory'] ?? false,
    );
  },
);
```

## 示例项目

查看[example](./example)目录获取完整的示例应用。

## 贡献

欢迎提交问题和拉取请求，我们将尽快回应。

## 许可

MIT License
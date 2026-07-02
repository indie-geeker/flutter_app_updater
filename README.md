# Flutter App Updater

轻量级 Flutter 应用更新基础库，适合独立开发者在自有分发场景中接入版本检查、更新提示、文件下载和 Android APK 安装。

## 能力范围

- 自定义更新接口字段映射
- 结构化区分“有更新 / 无更新 / 检查失败”
- 默认更新弹窗，也支持完全自定义 UI
- 下载进度、暂停、恢复、取消
- Range 断点续传、重试策略、MD5 校验
- Android APK 安装
- Android / iOS / macOS 应用版本读取

## 平台支持

| 平台 | 检查更新 | 下载文件 | 自动读取应用版本 | 安装更新 |
| --- | --- | --- | --- | --- |
| Android | 支持 | 支持 | 支持 | 支持 APK |
| iOS | 支持 | 支持 | 支持 | 不支持应用内安装 |
| macOS | 支持 | 支持 | 支持 | 不支持 |
| Windows | 支持 | 支持 | 需传 `currentVersion` | 不支持 |
| OpenHarmony | 支持 | 支持 | 需传 `currentVersion` | 不支持 |

> iOS 应用更新通常应跳转 App Store、TestFlight 或你的企业分发页面，本库不会绕过系统安装策略。

## 安装

```yaml
dependencies:
  flutter_app_updater: ^2.1.0
```

```bash
flutter pub get
```

## 服务端响应示例

默认字段：

```json
{
  "version": "2.0.0",
  "downloadUrl": "https://example.com/app-2.0.0.apk",
  "changelog": "Bug fixes and performance improvements",
  "isForceUpdate": false,
  "fileSize": 25600000,
  "md5": "8b1a9953c4611296a827abf8c47804d7",
  "publishDate": "2026-07-02T10:00:00Z"
}
```

`version` 和 `downloadUrl` 是必填字段。缺失或为空会返回 `INVALID_UPDATE_INFO` 错误。

## 基本使用

```dart
import 'package:flutter/material.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

final updater = FlutterAppUpdater(
  updateUrl: 'https://your-api.com/update.json',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await updater.init();
  runApp(const MyApp());
}

Future<void> checkUpdate(BuildContext context) async {
  final result = await updater.checkForUpdateResult(forceCheck: true);

  if (result.isAvailable) {
    await updater.showUpdateDialog(
      context: context,
      updateInfo: result.updateInfo!,
    );
    return;
  }

  if (result.isFailed) {
    debugPrint('检查更新失败: ${result.error}');
    return;
  }

  debugPrint('已经是最新版本');
}
```

如果只需要旧式返回值，也可以继续使用：

```dart
final updateInfo = await updater.checkForUpdate();
```

这个方法在“无更新”和“检查失败”时都会返回 `null`。新项目建议使用 `checkForUpdateResult()`。

## 自定义字段

```dart
final updater = FlutterAppUpdater(
  updateUrl: 'https://your-api.com/update.json',
  versionKey: 'newVersionCode',
  downloadUrlKey: 'apkUrl',
  changeLogKey: 'updateMessage',
  isForceUpdateKey: 'forceUpdate',
);
```

## 自定义检查逻辑

`onCheckUpdate` 返回一个 `Map<String, dynamic>`，之后仍会复用字段解析、版本比较和校验逻辑。

```dart
final updater = FlutterAppUpdater(
  currentVersion: '1.0.0',
  onCheckUpdate: () async {
    final response = await customApiCall();
    return {
      'version': response.version,
      'downloadUrl': response.apkUrl,
      'changelog': response.releaseNotes,
      'isForceUpdate': response.mandatory,
    };
  },
);
```

## 自定义更新弹窗

```dart
await updater.showUpdateDialog(
  context: context,
  updateInfo: updateInfo,
  dialogBuilder: (context, updateInfo) {
    return AlertDialog(
      title: Text('发现新版本 ${updateInfo.newVersion}'),
      content: Text(updateInfo.changelog),
      actions: [
        if (!updateInfo.isForceUpdate)
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('稍后再说'),
          ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context, true);
            await updater.downloadUpdate(autoInstall: true);
          },
          child: const Text('立即更新'),
        ),
      ],
    );
  },
);
```

## 下载与安装

```dart
final file = await updater.downloadUpdate(
  autoInstall: true,
);
```

Android 下载完成后可以调用：

```dart
final installed = await updater.installUpdate();
```

Android 8.0+ 需要用户授权“安装未知来源应用”。如果未授权，安装会失败并返回 `INSTALL_PERMISSION_REQUIRED`。

## 重试策略

```dart
final downloader = UpdateDownloader(
  url: 'https://example.com/app.apk',
  savePath: '/path/to/app.apk',
  retryStrategy: RetryStrategy.fast,
);

final customDownloader = UpdateDownloader(
  url: 'https://example.com/app.apk',
  savePath: '/path/to/app.apk',
  retryStrategy: const RetryStrategy(
    maxAttempts: 5,
    initialDelay: Duration(seconds: 2),
    backoffFactor: 2.0,
    maxDelay: Duration(minutes: 1),
    enableJitter: true,
  ),
);
```

## 日志

```dart
UpdateLogger.setLogLevel(LogLevel.error);
UpdateLogger.setLogLevel(LogLevel.debug);
```

## 错误码

常见错误：

- `MISSING_VERSION`：未传入当前应用版本，且平台无法自动读取
- `MISSING_URL`：未配置 `updateUrl` 或 `onCheckUpdate`
- `INVALID_UPDATE_INFO`：服务端响应缺少必填字段
- `INVALID_VERSION`：版本号格式不受支持
- `NETWORK_ERROR`：网络连接失败
- `SERVER_ERROR`：服务端响应异常
- `DOWNLOAD_ERROR`：下载失败
- `MD5_MISMATCH`：文件校验失败
- `INSTALL_PERMISSION_REQUIRED`：Android 未授权安装 APK
- `PLATFORM_NOT_SUPPORTED`：当前平台不支持安装

## 验证命令

维护者发布前应至少运行：

```bash
flutter analyze
flutter test
flutter analyze example
(cd example && flutter build apk --debug)
flutter pub publish --dry-run
```

## 许可

Apache-2.0

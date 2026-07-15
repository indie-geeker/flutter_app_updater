# Flutter App Updater

[English](README.md) | 简体中文

[![CI](https://github.com/indie-geeker/flutter_app_updater/actions/workflows/ci.yml/badge.svg)](https://github.com/indie-geeker/flutter_app_updater/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/flutter_app_updater.svg)](https://pub.dev/packages/flutter_app_updater)
[![license](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)

Flutter App Updater 是面向商用 Flutter 应用的无 UI v3 更新基础库。它负责获取并校验更新清单、为当前应用选择合适版本，并在宿主明确调用后执行更新动作。

v3 稳定范围：

- Android：Google Play 页面、中国 Android 应用市场、APK 下载、APK 安装、下载后安装。
- iOS：App Store 页面。
- macOS：Mac App Store 页面，下载并打开 DMG 或 ZIP 安装包。
- Windows：下载并打开 MSIX、MSI 或 EXE 安装包。

## 安装

```yaml
dependencies:
  flutter_app_updater: ^3.0.0
```

## 快速开始

默认集成入口是 `AppUpdater.manifest`：

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse('https://example.com/app-updates.json'),
  expectedAppId: 'com.example.app',
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
  distributionPolicy: UpdateDistributionPolicy.any,
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestPublicKeys,
  ),
);

final result = await updater.checkAndPrepare();

switch (result) {
  case PreparedUpdateAvailable():
    final actionResult = await updater.performRecommended(result);
    if (!actionResult.isSuccess) {
      debugPrint('${actionResult.code}: ${actionResult.message}');
    }
  case PreparedUpdateNotAvailable():
    debugPrint('已是最新版本');
  case PreparedUpdateCheckFailed(:final code, :final message):
    debugPrint('$code: $message');
}
```

核心包不会显示界面。宿主应用应根据准备结果显示自己的弹窗、底部面板、更新页面或静默策略。

`expectedAppId` 是必填项，用于把远程清单绑定到当前应用。其他应用的清单会在版本选择和动作执行前返回 `APP_ID_MISMATCH`。

v2 项目请阅读 [v2 到 v3 迁移指南](doc/migration-v2-to-v3.md)。完整的传输、签名、文件和平台信任边界见[安全模型](doc/security-model.md)。

## 进度与取消

下载和安装器动作会发出开始事件、零到多个进度事件，以及唯一一个终止事件：

```dart
final cancelToken = UpdateActionCancelToken();

await for (final event in updater.performRecommendedStream(
  result,
  cancelToken: cancelToken,
)) {
  switch (event) {
    case UpdateActionStarted():
      showProgress();
    case UpdateActionProgress(:final fraction):
      updateProgress(fraction);
    case UpdateActionCompleted(:final result):
      handleResult(result);
  }
}

// 用户在界面中点击取消时调用。
cancelToken.cancel();
```

如果只需要最终结果，可继续使用 `perform()` 或 `performRecommended()`。

## 网络与文件安全

- 远程清单和文件默认必须使用绝对 HTTPS URL。普通 HTTP 仅能通过显式配置用于本机回环开发。重定向最多五次，每个目标都会重新校验；HTTPS 不允许降级到 HTTP，敏感请求头只会跟随同源重定向。
- 远程自托管动作必须声明精确的正数文件大小和 SHA-256，并且在解析 payload 前通过 Ed25519 envelope 验证。
- 下载请求有超时、瞬时失败重试、最大 1 GiB 默认限制、ETag/Last-Modified 续传校验、URL 指纹、进程内保护和操作系统持久锁。
- 取消、大小越界或哈希不匹配会清理不可信的部分文件。
- 清单的 `appId`、平台、渠道和架构会在动作选择前校验。运行时架构未知时，架构专用版本会失败关闭，只有省略架构的通用版本可以匹配。
- 动作保持发布者给出的顺序。`UpdateDistributionPolicy` 和执行器能力只过滤动作，不重排动作；过滤后第一个动作是推荐动作。

## 获取更新信息

`AppUpdater.manifest` 对静态 JSON 文件和 RESTful 接口都发送 HTTPS `GET` 请求。两种方式使用完全相同的 manifest v3 返回结构。

### 静态 JSON 文件

把清单 payload 或签名后的 envelope 作为不可变文件发布到 CDN、对象存储或 Web 服务器。仓库内的 [`doc/examples/update-manifest-v3.json`](doc/examples/update-manifest-v3.json) 是可参考的完整 payload。

这里的静态 JSON 指通过 HTTPS 托管的文档。`AppUpdater.manifest` 不读取本地 `file://` URL 或 Flutter asset 路径。可信适配器可以自行构造 `UpdateManifest`，再使用 `UpdateSource.staticManifest`。

```dart
final updater = AppUpdater.manifest(
  manifestUrl: Uri.parse(
    'https://cdn.example.com/releases/app-updates.json',
  ),
  expectedAppId: 'com.example.app',
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestPublicKeys,
  ),
);

final result = await updater.checkAndPrepare();
```

### RESTful 接口

REST 服务可以根据请求参数动态选择版本。默认 fetcher 只发送 `GET`，因此把筛选条件放在 URL 中，把可选凭证放在 `headers` 中：

```http
GET /v1/apps/com.example.app/updates?platform=android&architecture=arm64&channel=stable&installedVersion=1.0.0 HTTP/1.1
Host: updates.example.com
Accept: application/json
Authorization: Bearer <short-lived-token>
```

```dart
final endpoint = Uri.https(
  'updates.example.com',
  '/v1/apps/com.example.app/updates',
  {
    'platform': 'android',
    'architecture': 'arm64',
    'channel': 'stable',
    'installedVersion': '1.0.0',
  },
);

final updater = AppUpdater.manifest(
  manifestUrl: endpoint,
  expectedAppId: 'com.example.app',
  headers: {
    'Accept': 'application/json',
    'Authorization': 'Bearer $accessToken',
  },
  installedVersion: '1.0.0',
  platform: defaultTargetPlatform,
  architecture: 'arm64',
  channel: 'stable',
  downloadDirectory: downloadDirectory,
  signaturePolicy: ManifestSignaturePolicy.required(
    trustedPublicKeys: trustedManifestPublicKeys,
  ),
);

final result = await updater.checkAndPrepare();
```

默认传输层只接受 HTTP 200，响应体最大 1 MiB，并直接把 body 解析成 manifest v3 根对象或签名 envelope。不要再包装成 `{ "data": ... }`、`{ "result": ... }` 或其他业务响应对象。如果现有接口无法返回该结构，请实现自定义 `ManifestFetcher`。调用方请求头在跨域重定向后会被移除。

无论使用哪种传输方式，只有在使用 `ManifestSignaturePolicy.optional` 且清单仅包含官方商店或 Android 市场动作时，才允许返回裸清单。自托管包或桌面安装器必须使用有效的 Ed25519 envelope。生产环境建议对所有响应签名。

## Manifest v3 返回结构

```json
{
  "schemaVersion": 3,
  "appId": "com.example.app",
  "channel": "stable",
  "releases": [
    {
      "version": "2.0.0",
      "buildNumber": "42",
      "platform": "android",
      "architecture": "arm64",
      "releaseNotes": "修复已知问题",
      "releasedAt": "2026-07-03T10:00:00Z",
      "policy": {
        "level": "recommended",
        "minSupportedVersion": "1.5.0"
      },
      "actions": [
        {
          "type": "downloadAndInstallPackage",
          "packageUrl": "https://example.com/app.apk",
          "packageType": "apk",
          "packageSizeBytes": 25600000,
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
      ]
    }
  ]
}
```

### Manifest 字段：必填与选填

#### 根对象字段

| 字段 | 必填/选填 | 类型与约束 | 含义 |
| --- | --- | --- | --- |
| `schemaVersion` | 必填 | 整数，必须为 `3` | 清单协议版本。 |
| `appId` | 必填 | 非空字符串 | 必须与客户端 `expectedAppId` 一致。 |
| `channel` | 必填 | 非空字符串 | 未单独声明渠道的 release 会继承它。 |
| `releases` | 必填 | 数组 | 按发布者顺序排列的候选版本；没有版本时可为空数组。 |

#### Release 字段

| 字段 | 必填/选填 | 类型与约束 | 含义 |
| --- | --- | --- | --- |
| `version` | 必填 | 语义化版本字符串 | 更新排序的主要依据。 |
| `platform` | 必填 | 稳定版本使用 `android`、`ios`、`macos` 或 `windows` | 必须与客户端平台完全匹配。 |
| `releaseNotes` | 必填 | 非空字符串 | 由宿主应用展示的更新说明。 |
| `actions` | 必填 | 非空数组 | 按发布者优先级排序的交付方式。 |
| `buildNumber` | 选填 | 非负 ASCII 十进制整数字符串 | 语义化版本相同时比较；允许前导零，并按整数解析。 |
| `channel` | 选填 | 非空字符串 | 覆盖根对象的 `channel`。 |
| `architecture` | 选填 | 非空字符串 | 精确匹配运行时架构；省略表示通用版本。 |
| `releasedAt` | 选填 | ISO-8601 字符串 | 发布者提供的发布时间。 |
| `policy` | 选填 | 对象 | 更新建议级别和最低支持版本。 |

#### Policy 字段

| 字段 | 必填/选填 | 类型与约束 | 含义 |
| --- | --- | --- | --- |
| `level` | 选填 | `optional`、`recommended` 或 `required`；默认 `optional` | 宿主应如何提示更新。 |
| `minSupportedVersion` | 选填 | 不大于该 release `version` 的语义化版本字符串 | 已安装版本低于它时，本次更新按必更新处理。 |

#### Action 字段

每个 action 对象都必须包含非空的 `type` 判别字段。该值选择下表中的一
行；其余必填与选填字段严格由对应 action 类型决定。

| `type` | 必填字段 | 选填字段 | 说明 |
| --- | --- | --- | --- |
| `openStore` | `store`、`storeUrl` | 无 | `store` 为 `googlePlay`、`appStore` 或 `macAppStore`；远程 URL 必须属于对应官方域名。 |
| `openAndroidMarket` | `market`、`targetPackageName` | `fallbackUrl` | `targetPackageName` 必须等于清单 `appId`。 |
| `downloadPackage` | `packageUrl`、`packageType`、`packageSizeBytes`、`sha256` | 无 | 必须提供精确正数大小和 64 位十六进制 SHA-256。 |
| `downloadAndInstallPackage` | `packageUrl`、`packageType`、`packageSizeBytes`、`sha256` | 无 | 运行时本地安装只支持 Android APK。 |
| `openInstaller` | `installerUrl`、`installerType`、`installerSizeBytes`、`sha256` | 无 | 稳定类型：Windows `msix`/`msi`/`exe`，macOS `dmg`/`zip`。 |
| `installPackage` | `packagePath` | `packageType`，默认 `apk` | 仅允许可信本地 Dart 代码构造；远程清单会拒绝该动作。 |

`buildNumber` 是选填字段；提供时必须是非负 ASCII 十进制整数字符串（`0`、`42`、`00042` 都有效）。
允许前导零，并按整数解析。其他值会导致整个响应被拒绝。
`minSupportedVersion` 提供时不得大于同一 release 的 `version`。

Manifest v3 在每个对象边界都使用精确白名单：根对象、每个 release、
policy 与 action 对象都会拒绝未知字段。不存在 `extensions` 逃生口。
签名 envelope 也会拒绝多余字段。新增字段必须升级 schema version。
任何包含未知字段、类型错误或无效值的 v3 响应都会被整体拒绝，而不是
忽略该字段。

所有远程 URL 必须是绝对 URL。远程策略还要求 HTTPS，并要求每个自托管文件都有精确正数大小和 64 位十六进制 `sha256`。文档任意位置出现已移除的旧版 schema 字段名都会被拒绝；请只使用上表列出的 v3 字段。

parser 还可以识别 `linux`/`fuchsia` 平台值和 `appImage`/`deb`/`rpm` 安装器值，以保留 typed model 兼容性；但 v3 默认执行器和插件注册并未把它们作为稳定支持，最终可能返回 `NO_SUPPORTED_ACTION`。下方平台矩阵才是当前可执行契约。

上面的 JSON 是被签名的 payload，不是包含自托管动作时的最终网络响应。网络响应需要把 payload 的精确字节编码进版本化 Ed25519 envelope。下列字段全部必填；envelope 同样使用精确白名单，出现任何多余字段都会拒绝整个响应：

```json
{
  "format": "flutter_app_updater.ed25519.v1",
  "keyId": "release-2026-01",
  "issuedAt": "2026-07-14T12:00:00Z",
  "expiresAt": "2026-07-15T12:00:00Z",
  "payload": "<清单 JSON 精确字节的 Base64>",
  "signature": "<Ed25519 签名的 Base64>"
}
```

| 字段 | 必填/选填 | 类型与约束 |
| --- | --- | --- |
| `format` | 必填 | 必须为 `flutter_app_updater.ed25519.v1`。 |
| `keyId` | 必填 | 非空字符串，并存在于客户端 `trustedPublicKeys`。 |
| `issuedAt` | 必填 | ISO-8601 有效期开始时间。 |
| `expiresAt` | 必填 | ISO-8601 有效期结束时间；晚于 `issuedAt` 且不超过配置的最长有效期。 |
| `payload` | 必填 | manifest v3 JSON 精确字节的 Base64。 |
| `signature` | 必填 | 对包定义的域隔离输入生成的 Base64 Ed25519 签名。 |

密钥轮换时，先让客户端同时信任旧、新两个 `keyId`，再切换服务端签名密钥，最后在后续客户端版本中移除旧密钥。

## 常用动作配置

### 官方商店

```json
{
  "type": "openStore",
  "store": "googlePlay",
  "storeUrl": "https://play.google.com/store/apps/details?id=com.example.app"
}
```

iOS 使用 `appStore`，macOS 使用 `macAppStore`。

### 中国 Android 应用市场

```json
{
  "type": "openAndroidMarket",
  "market": "xiaomi",
  "targetPackageName": "com.example.app",
  "fallbackUrl": "https://app.mi.com/details?id=com.example.app"
}
```

支持的市场名：`huawei`、`honor`、`xiaomi`、`oppo`、`vivo`、`meizu`、`tencentMyApp`、`generic`。

### 自托管 Android APK

自托管 APK 安装只适用于符合分发政策的企业、私有或非 Google Play 场景。Google Play 版本应使用商店动作，不能仅为了自更新而申请 `REQUEST_INSTALL_PACKAGES`。插件不会自动合并该敏感权限；符合条件的宿主需自行声明：

```xml
<uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES" />
```

下载并随后打开系统安装器：

```json
{
  "type": "downloadAndInstallPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

只下载、稍后由宿主管理安装：

```json
{
  "type": "downloadPackage",
  "packageUrl": "https://example.com/app.apk",
  "packageType": "apk",
  "packageSizeBytes": 25600000,
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

远程清单不能要求安装任意本地路径。宿主只能在可信 typed boundary 中构造 `InstallPackageAction`，例如在自己的校验下载完成后。Android 会在交给系统安装器前再次校验文件大小、SHA-256、包名和签名继承关系。

## Android 高级后台下载

`AndroidBackgroundDownloadManager` 是 Android 专用、显式启用的 API，一次只管理一个持久且用户可见的 APK 传输。它独立于默认 `AppUpdater` 动作流。启动必须来自可见的用户操作，并提供 HTTPS URL、精确长度和 SHA-256：

前台下载与 Android 持久下载使用不同的 URL 持久化契约。
前台 action 流可以使用带短期 query 凭证的 HTTPS 文件 URL。
前台 checkpoint 只保存 SHA-256 URL 指纹，不保存原始 URL 或 query token。
Android 持久下载的 `start()` 只接受不含 userinfo、query 或 fragment 的稳定、无凭证入口 URL。
持久任务记录也只保存该稳定入口 URL。

如需使用短期下载凭证，应让稳定入口返回到短期签名 URL 的 HTTPS 重定向。
带签名的重定向目标只存在于当前进程内存中的传输上下文，绝不会持久化。
每个重定向目标都会重新校验，任何 HTTPS 到 HTTP 的降级都会被拒绝。

```dart
final downloads = AndroidBackgroundDownloadManager();
final task = await downloads.start(
  DownloadPackageAction(
    packageUrl: Uri.parse('https://downloads.example.com/app.apk'),
    packageType: PackageType.apk,
    packageSizeBytes: 25600000,
    sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  ),
);

await for (final snapshot in downloads.watch(task.id)) {
  updateBackgroundDownloadUi(snapshot);
}
```

应用重新打开后使用 `list()`、`listUnfinished()` 和 `get()` 恢复界面状态。`resume()` 只能由用户操作触发，`cancel()` 是终止动作，`remove()` 只能删除已取消或其他终止状态的任务。

持久任务状态存放在 Android `noBackupFilesDir`；APK 和部分下载文件存放在应用私有 `filesDir`，并通过包内 FileProvider 暴露给系统安装器。
首次使用新布局时，预发布 single-root 布局中的旧任务和文件会被重置而不是迁移。
宿主应把这些旧任务视为不可续传，并由用户重新发起可见传输。

宿主需按 [英文 README 的完整 Android manifest 示例](README.md#required-host-manifest) 合并网络、前台服务、通知及 API 34+ 用户发起数据传输任务声明。Android 13+ 的通知权限由宿主决定何时解释和申请。

服务器应支持精确 `Range: bytes=N-`、`206 Content-Range` 和稳定的强 ETag。忽略 Range 的服务器可能触发安全的完整重下；弱或变化的 validator 不能作为续传证据。

下载完成与安装刻意分离：

```dart
final installAction = await downloads.createInstallAction(task.id);
// 此处只复验私有 APK，不会开始安装。
final installResult = await updater.perform(installAction);
```

原生记录和部分字节可跨 Flutter engine detach 与普通进程重建保存，但不能保证 force-stop 后继续，也不会跨重启持久调度。最近任务划掉、系统 Task Manager Stop、电池限制、后台启动限制、存储压力和 OEM 进程管理都可能停止或拒绝任务。该实现不承诺在任何 OEM 系列上不间断后台运行。

真实设备验证仍应按 [`tool/verification/android_background_download.md`](tool/verification/android_background_download.md) 记录具体设备、API、ROM、通知、电池策略和结果。

### iOS App Store

```json
{
  "type": "openStore",
  "store": "appStore",
  "storeUrl": "https://apps.apple.com/app/id123456789"
}
```

### macOS 与 Windows 安装器

```json
{
  "type": "openInstaller",
  "installerUrl": "https://example.com/app.msi",
  "installerType": "msi",
  "installerSizeBytes": 82000000,
  "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
}
```

稳定安装器类型：Windows 支持 `msix`、`msi`、`exe`；macOS 支持 `dmg`、`zip`。

## 平台矩阵

| 平台 | 官方商店 | 中国市场 | 包下载 | 包安装 | 桌面安装器 |
| --- | --- | --- | --- | --- | --- |
| Android | 稳定 | 稳定 | 稳定 | 稳定 | 不适用 |
| iOS | 稳定 | 不适用 | 不支持 | 不支持 | 不适用 |
| macOS | 稳定 | 不适用 | 稳定 | 不支持 | 稳定 |
| Windows | 不支持 | 不适用 | 稳定 | 不支持 | 稳定 |

不支持的动作会返回结构化失败，不会让平台异常穿透公共 API。

## 错误处理

`checkAndPrepare()` 返回：

- `PreparedUpdateAvailable`
- `PreparedUpdateNotAvailable`
- `PreparedUpdateCheckFailed`

`perform()` 和 `performRecommended()` 返回 `UpdateActionResult`。常用错误码包括 `MANIFEST_FETCH_FAILED`、`MANIFEST_INVALID`、`APP_ID_MISMATCH`、`NO_SUPPORTED_ACTION`、`PACKAGE_DOWNLOAD_FAILED`、`PACKAGE_HASH_MISMATCH`、`PACKAGE_INSTALL_PERMISSION_REQUIRED`、`PACKAGE_INSTALL_FAILED`、`INSTALLER_OPEN_FAILED`、`PLATFORM_NOT_SUPPORTED`、`ACTION_CANCELED`。

## 示例应用

仓库示例默认打开可配置、无外部副作用的更新模拟器。另有明确标记且默认禁用的生产集成页；只有显式配置后，它才会走真实签名清单的获取、验证、应用绑定、选择、准备和用户确认动作。安全边界、配置方式和运行命令见 [`example/README.md`](example/README.md)。

## 维护者验证

最低支持 Flutter 3.22.0。完整 CI 同时验证该最低版本和当前 stable，覆盖根项目与 example 的分析/测试、总覆盖率与关键文件 80% 门槛、Dart API 文档、所有已注册平台的 example 构建、Android/Windows 原生测试及干净发布包。

```bash
flutter pub get
(cd example && flutter pub get)
dart format --output=none --set-exit-if-changed lib test example/lib example/test example/integration_test tool
flutter analyze --no-pub
flutter test --coverage --no-pub
dart doc --dry-run
(cd example && flutter analyze --no-pub && flutter test --no-pub)
(cd example && flutter build apk --debug --no-pub)
bash tool/ci/publish_dry_run.sh
```

Android 原生门槛从 `example/android` 运行：

```bash
../../android/gradlew :flutter_app_updater:testDebugUnitTest :flutter_app_updater:lintDebug :app:processDebugMainManifest
```

发布时同步更新 `pubspec.yaml` 和 `CHANGELOG.md`，把发布提交合入 `main`，再给该精确提交打 `v<version>` 标签。发布工作流会重新运行完整门槛，并校验 tag、version、CHANGELOG 和 `origin/main` 祖先关系。

开发检查见 [CONTRIBUTING.md](CONTRIBUTING.md)，私密安全漏洞报告方式见 [SECURITY.md](SECURITY.md)。

## 许可证

Apache-2.0

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

void main() {
  runApp(const MyApp());
}

// 定义全局导航键
// 这个键可以用于获取当前构建上下文
// 确保对话框有正确的 MaterialLocalizations 上下文
// 很多库如对话框和本地化都依赖于这个上下文
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  String _appVersion = 'Unknown';
  final _flutterAppUpdaterPlugin = FlutterAppUpdater(
      updateUrl: "https://power.earthg.cn/update/update.json",
      versionKey: "newVersionCode",
      downloadUrlKey: "apkUrl",
      changeLogKey: "updateMessage",
      isForceUpdateKey: "forceUpdate"
  );


  @override
  void initState() {
    super.initState();
    _flutterAppUpdaterPlugin.init();

    initPlatformState();

  }

  Future<void> initPlatformState() async {
    String platformVersion;
    String appVersion;
    try {
      platformVersion =
          await _flutterAppUpdaterPlugin.getPlatformVersion() ?? 'Unknown platform version';
      appVersion =
          await _flutterAppUpdaterPlugin.getAppVersion() ?? 'Unknown app version';
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
      appVersion = 'Failed to get app version.';
    }
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
      _appVersion = appVersion;
    });
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      // 添加导航键以获取正确的应用上下文
      navigatorKey: navigatorKey,
      // 添加国际化支持
      localizationsDelegates: const [
        // 使用内置的本地化委托
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: const [
        Locale('zh', 'CN'), // 中文
        Locale('en', 'US'), // 英文
      ],
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
        body: Center(
          child: Column(
            children: [
              Text('Running on: $_platformVersion\n'),
              Text('App Version: $_appVersion\n'),
              ElevatedButton(
                onPressed: () async {
                  try {
                    // 检查更新，设置 showDialogIfAvailable 为 false，因为我们想手动控制对话框显示
                    final updateInfo = await _flutterAppUpdaterPlugin.checkForUpdate(
                      showDialogIfAvailable: false,
                    );

                    if (updateInfo != null) {
                      debugPrint('New version available: ${updateInfo.newVersion}');
                      debugPrint('Download URL: ${updateInfo.downloadUrl}');
                      debugPrint('Changelog: ${updateInfo.changelog}');

                      // 清晰地显示更新对话框
                      // 使用 navigatorKey.currentContext 获取全局上下文
                      // 这个上下文有正确的 MaterialLocalizations
                      final ctx = navigatorKey.currentContext;
                      if (ctx != null) {
                        await _flutterAppUpdaterPlugin.showUpdateDialog(
                          context: ctx,
                          updateInfo: updateInfo,
                        );
                      }
                    } else {
                      debugPrint('No updates available');
                    }
                  } catch (e) {
                    debugPrint('Error checking for updates: $e');
                  }
                },
                child: const Text('Check for Updates'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

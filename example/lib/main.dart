import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_app_updater/flutter_app_updater.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  String _appVersionCode = 'Unknown';
  String _appVersionName = 'Unknown';
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
    String appVersionName;
    try {
      platformVersion =
          await _flutterAppUpdaterPlugin.getPlatformVersion() ?? 'Unknown platform version';
      appVersion =
          await _flutterAppUpdaterPlugin.getAppVersionCode() ?? 'Unknown app version';

      appVersionName =
          await _flutterAppUpdaterPlugin.getAppVersionName() ?? 'Unknown app version name';

    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
      appVersion = 'Failed to get app version.';
      appVersionName = 'Failed to get app version name.';
    }
    if (!mounted) return;

    setState(() {
      _platformVersion = platformVersion;
      _appVersionCode = appVersion;
      _appVersionName = appVersionName;
    });
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
              Text('App Version: $_appVersionCode\n'),
              Text('App Version Name: $_appVersionName\n'),
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
                      if (mounted) {
                        await _flutterAppUpdaterPlugin.showUpdateDialog(
                          context: this.context,
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

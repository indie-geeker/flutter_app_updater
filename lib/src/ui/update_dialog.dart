import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/update_controller.dart';
import '../models/update_error.dart';
import '../models/update_info.dart';
import '../models/update_progress.dart';
import '../models/update_status.dart';


/// 应用更新对话框
///
/// 提供默认的更新对话框UI，支持强制更新和可选更新
/// 可以通过继承此类或使用自定义builder完全定制UI
class UpdateDialog extends StatefulWidget {
  /// 更新信息
  final UpdateInfo updateInfo;

  /// 更新控制器
  final UpdateController controller;

  /// 对话框标题
  final String? title;

  /// 对话框宽度
  final double? width;

  /// 对话框高度
  final double? height;

  /// 对话框内边距
  final EdgeInsets contentPadding;

  /// 更新按钮文本
  final String updateButtonText;

  /// 取消按钮文本
  final String cancelButtonText;

  /// 稍后提醒按钮文本
  final String remindLaterButtonText;

  /// 安装按钮文本
  final String installButtonText;

  /// 下载中文本
  final String downloadingText;

  /// 暂停下载按钮文本
  final String pauseButtonText;

  /// 继续下载按钮文本
  final String resumeButtonText;

  /// 下载完成文本
  final String downloadedText;

  /// 错误提示文本
  final String errorText;

  /// 重试按钮文本
  final String retryButtonText;

  /// 主按钮样式
  final ButtonStyle? primaryButtonStyle;

  /// 次要按钮样式
  final ButtonStyle? secondaryButtonStyle;

  /// 标题样式
  final TextStyle? titleStyle;

  /// 版本号样式
  final TextStyle? versionStyle;

  /// 描述文本样式
  final TextStyle? changLogStyle;

  /// 进度提示文本样式
  final TextStyle? progressTextStyle;

  /// 进度条颜色
  final Color? progressColor;

  /// 进度条背景色
  final Color? progressBackgroundColor;

  /// 对话框背景色
  final Color? backgroundColor;

  /// 对话框圆角半径
  final double borderRadius;

  /// 是否自动开始下载
  final bool autoStartDownload;

  /// 下载完成后是否自动安装
  final bool autoInstall;

  /// 自定义更新信息头部构建器
  final Widget Function(BuildContext, UpdateInfo)? headerBuilder;

  /// 自定义更新内容构建器
  final Widget Function(BuildContext, UpdateInfo)? contentBuilder;

  /// 自定义按钮构建器
  final Widget Function(BuildContext, UpdateInfo, UpdateStatus)? actionsBuilder;

  /// 自定义进度指示器构建器
  final Widget Function(BuildContext, UpdateProgress)? progressBuilder;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.controller,
    this.title,
    this.width,
    this.height,
    this.contentPadding = const EdgeInsets.all(16.0),
    this.updateButtonText = '立即更新',
    this.cancelButtonText = '取消',
    this.remindLaterButtonText = '稍后提醒',
    this.installButtonText = '立即安装',
    this.downloadingText = '正在下载更新...',
    this.pauseButtonText = '暂停',
    this.resumeButtonText = '继续',
    this.downloadedText = '下载完成',
    this.errorText = '下载出错',
    this.retryButtonText = '重试',
    this.primaryButtonStyle,
    this.secondaryButtonStyle,
    this.titleStyle,
    this.versionStyle,
    this.changLogStyle,
    this.progressTextStyle,
    this.progressColor,
    this.progressBackgroundColor,
    this.backgroundColor,
    this.borderRadius = 8.0,
    this.autoStartDownload = false,
    this.autoInstall = false,
    this.headerBuilder,
    this.contentBuilder,
    this.actionsBuilder,
    this.progressBuilder,
  });

  @override
  UpdateDialogState createState() => UpdateDialogState();
}

class UpdateDialogState extends State<UpdateDialog> {
  // 下载错误
  UpdateError? _error;

  // 下载状态订阅
  StreamSubscription? _statusSubscription;
  StreamSubscription? _progressSubscription;
  StreamSubscription? _errorSubscription;

  @override
  void initState() {
    super.initState();

    // 监听下载状态变化
    _statusSubscription = widget.controller.statusStream.listen((status) {
      setState(() {});
    });

    // 监听下载进度变化
    _progressSubscription = widget.controller.progressStream.listen((_) {
      setState(() {});
    });

    // 监听错误信息
    _errorSubscription = widget.controller.errorStream.listen((error) {
      setState(() {
        _error = error;
      });
    });

    // 如果设置了自动开始下载
    if (widget.autoStartDownload) {
      _startDownload();
    }
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _progressSubscription?.cancel();
    _errorSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: widget.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      child: Container(
        width: widget.width ?? MediaQuery.of(context).size.width * 0.85,
        constraints: BoxConstraints(
          maxWidth: 400,
          maxHeight: widget.height ?? MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 对话框头部
            _buildHeader(context, theme),

            // 对话框内容
            Flexible(
              child: SingleChildScrollView(
                padding: widget.contentPadding,
                child: _buildContent(context, theme),
              ),
            ),

            // 进度条区域
            _buildProgressArea(context, theme),

            // 按钮区域
            _buildActions(context, theme),
          ],
        ),
      ),
    );
  }

  // 构建对话框头部
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    if (widget.headerBuilder != null) {
      return widget.headerBuilder!(context, widget.updateInfo);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title ?? '发现新版本',
            style: widget.titleStyle ?? theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            '新版本：${widget.updateInfo.newVersion}',
            style: widget.versionStyle ?? theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }

  // 构建对话框内容
  Widget _buildContent(BuildContext context, ThemeData theme) {
    if (widget.contentBuilder != null) {
      return widget.contentBuilder!(context, widget.updateInfo);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.updateInfo.changelog,
          style: widget.changLogStyle ??
              theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),

        if (widget.updateInfo.fileSize != null) ...[
          const SizedBox(height: 12),
          Text(
            '文件大小：${_formatFileSize(widget.updateInfo.fileSize!)}',
            style: theme.textTheme.bodySmall,
          ),
        ],

        if (widget.updateInfo.publishDate != null) ...[
          const SizedBox(height: 4),
          Text(
            '发布时间：${_formatDate(widget.updateInfo.publishDate!)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  // 构建进度区域
  Widget _buildProgressArea(BuildContext context, ThemeData theme) {
    final status = widget.controller.status;
    final progress = widget.controller.progress;

    if (status != UpdateStatus.downloading &&
        status != UpdateStatus.paused &&
        status != UpdateStatus.error) {
      return const SizedBox.shrink();
    }

    if (widget.progressBuilder != null && progress != null) {
      return widget.progressBuilder!(context, progress);
    }

    // 显示错误信息
    if (status == UpdateStatus.error && _error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Text(
          '${widget.errorText}: ${_error!.message}',
          style: TextStyle(color: Colors.red[700]),
        ),
      );
    }

    // 进度显示
    if (progress != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              value: progress.progress > 0 ? progress.progress : null,
              backgroundColor: widget.progressBackgroundColor,
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.progressColor ?? theme.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  status == UpdateStatus.paused
                      ? '已暂停 ${progress.progressPercentage}%'
                      : '${widget.downloadingText} ${progress.progressPercentage}%',
                  style: widget.progressTextStyle ?? theme.textTheme.bodySmall,
                ),
                if (progress.total > 0)
                  Text(
                    '${_formatFileSize(progress.downloaded)} / ${_formatFileSize(progress.total)}',
                    style: widget.progressTextStyle ?? theme.textTheme.bodySmall,
                  ),
              ],
            ),
            if (progress.speed != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${_formatSpeed(progress.speed!)}${progress.estimatedTimeRemaining != null ? ' • 剩余时间：${_formatTime(progress.estimatedTimeRemaining!)}' : ''}',
                  style: widget.progressTextStyle ?? theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(
            backgroundColor: widget.progressBackgroundColor,
            valueColor: AlwaysStoppedAnimation<Color>(
              widget.progressColor ?? theme.primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.downloadingText,
            style: widget.progressTextStyle ?? theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  // 构建按钮区域
  Widget _buildActions(BuildContext context, ThemeData theme) {
    final status = widget.controller.status;

    if (widget.actionsBuilder != null) {
      return widget.actionsBuilder!(context, widget.updateInfo, status);
    }

    // 根据不同状态显示不同按钮
    Widget actionButtons;

    switch (status) {
      case UpdateStatus.available:
        actionButtons = _buildAvailableActions(context, theme);
        break;
      case UpdateStatus.downloading:
        actionButtons = _buildDownloadingActions(context, theme);
        break;
      case UpdateStatus.paused:
        actionButtons = _buildPausedActions(context, theme);
        break;
      case UpdateStatus.downloaded:
        actionButtons = _buildDownloadedActions(context, theme);
        break;
      case UpdateStatus.error:
        actionButtons = _buildErrorActions(context, theme);
        break;
      default:
        actionButtons = _buildAvailableActions(context, theme);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: actionButtons,
    );
  }

  // 有可用更新时的按钮
  Widget _buildAvailableActions(BuildContext context, ThemeData theme) {
    // 强制更新时只显示更新按钮
    if (widget.updateInfo.isForceUpdate) {
      return ElevatedButton(
        style: widget.primaryButtonStyle,
        onPressed: _startDownload,
        child: Text(widget.updateButtonText),
      );
    }

    // 可选更新时显示更新和取消按钮
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          style: widget.secondaryButtonStyle,
          onPressed: () => Navigator.pop(context, false),
          child: Text(widget.cancelButtonText),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: widget.primaryButtonStyle,
          onPressed: _startDownload,
          child: Text(widget.updateButtonText),
        ),
      ],
    );
  }

  // 下载中的按钮
  Widget _buildDownloadingActions(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!widget.updateInfo.isForceUpdate)
          TextButton(
            style: widget.secondaryButtonStyle,
            onPressed: () {
              widget.controller.cancelDownload();
              Navigator.pop(context, false);
            },
            child: Text(widget.cancelButtonText),
          ),
        const SizedBox(width: 8),
        TextButton(
          style: widget.secondaryButtonStyle,
          onPressed: () => widget.controller.pauseDownload(),
          child: Text(widget.pauseButtonText),
        ),
      ],
    );
  }

  // 下载暂停时的按钮
  Widget _buildPausedActions(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!widget.updateInfo.isForceUpdate)
          TextButton(
            style: widget.secondaryButtonStyle,
            onPressed: () {
              widget.controller.cancelDownload();
              Navigator.pop(context, false);
            },
            child: Text(widget.cancelButtonText),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: widget.primaryButtonStyle,
          onPressed: () => widget.controller.resumeDownload(),
          child: Text(widget.resumeButtonText),
        ),
      ],
    );
  }

  // 下载完成时的按钮
  Widget _buildDownloadedActions(BuildContext context, ThemeData theme) {
    return ElevatedButton(
      style: widget.primaryButtonStyle,
      onPressed: () async {
        final success = await widget.controller.installUpdate();
        if (success && mounted) {
          Navigator.pop(context, true);
        }
      },
      child: Text(widget.installButtonText),
    );
  }

  // 发生错误时的按钮
  Widget _buildErrorActions(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (!widget.updateInfo.isForceUpdate)
          TextButton(
            style: widget.secondaryButtonStyle,
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.cancelButtonText),
          ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: widget.primaryButtonStyle,
          onPressed: _startDownload,
          child: Text(widget.retryButtonText),
        ),
      ],
    );
  }

  // 开始下载
  void _startDownload() {
    widget.controller.downloadUpdate(
      autoInstall: widget.autoInstall,
    );
  }

  // 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
    }
  }

  // 格式化日期
  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  // 格式化速度
  String _formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '$bytesPerSecond B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  // 格式化剩余时间
  String _formatTime(int seconds) {
    if (seconds < 60) {
      return '$seconds秒';
    } else if (seconds < 3600) {
      final minutes = (seconds / 60).floor();
      final remainingSeconds = seconds % 60;
      return '$minutes分$remainingSeconds秒';
    } else {
      final hours = (seconds / 3600).floor();
      final remainingMinutes = ((seconds % 3600) / 60).floor();
      return '$hours小时$remainingMinutes分';
    }
  }
}
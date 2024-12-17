import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:ui' as ui;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '对话视频生成器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isGenerating = false;
  String? _currentVideoPath;
  final GlobalKey _chatKey = GlobalKey();

  // 示例数据
  final List<ChatMessage> _messages = [
    ChatMessage(sender: "用户A", message: "你好！", isLeft: true),
    ChatMessage(sender: "用户B", message: "你好！很高兴见到你。", isLeft: false),
    ChatMessage(sender: "用户A", message: "今天天气真不错。", isLeft: true),
    ChatMessage(sender: "用户B", message: "是的，阳光明媚，很适合出去走走。", isLeft: false),
    ChatMessage(sender: "用户A", message: "你周末有什么计划吗？", isLeft: true),
    ChatMessage(sender: "用户B", message: "我打算去公园野餐，你要一起来吗？", isLeft: false),
    ChatMessage(sender: "用户A", message: "听起来不错！需要我带些什么吗？", isLeft: true),
    ChatMessage(sender: "用户B", message: "你可以带些水果或饮料，我来准备主食。", isLeft: false),
    ChatMessage(sender: "用户A", message: "好的，我带些苹果和橙汁。几点见面？", isLeft: true),
    ChatMessage(sender: "用户B", message: "上午10点如何？这个时间阳光正好。", isLeft: false),
  ];

  // 添加进度变量
  double _generationProgress = 0.0;
  String _progressText = '';

  // 添加速度控制变量
  double _animationSpeed = 1.0; // 默认速度为1.0

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<String> _getVideoSavePath() async {
    Directory? directory;
    if (Platform.isAndroid) {
      directory = await getTemporaryDirectory();
      print('Using temporary directory: ${directory.path}');
    } else if (Platform.isIOS) {
      directory = await getApplicationDocumentsDirectory();
    } else {
      directory = await getApplicationDocumentsDirectory();
    }

    final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String fileName = 'chat_video_$timestamp.mp4';
    final String path = '${directory.path}/$fileName';
    print('Generated video path: $path');
    return path;
  }

  Future<bool> _requestPermissions() async {
    if (Platform.isAndroid) {
      // 获取 Android 版本
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final androidVersion = androidInfo.version.sdkInt;

      // 请求所有必要权限
      final permissions = <Permission>[
        Permission.microphone,
        Permission.notification,
        Permission.systemAlertWindow,
      ];

      // 根据 Android 版本添加存储权限
      if (androidVersion >= 33) {
        permissions.addAll([
          Permission.videos,
          Permission.audio,
          Permission.photos,
        ]);
      } else {
        permissions.add(Permission.storage);
        // 对于 Android 10 及以上版本，请求管理所有文件的权限
        if (androidVersion >= 29) {
          permissions.add(Permission.manageExternalStorage);
        }
      }

      // 请求所有权限
      Map<Permission, PermissionStatus> statuses = await permissions.request();

      // 检查是否所有权限都被授予
      bool allGranted = true;
      statuses.forEach((permission, status) {
        print('Permission $permission: $status');
        if (!status.isGranted) {
          allGranted = false;
        }
      });

      // 特别处理系统悬浮窗权限
      if (!await Permission.systemAlertWindow.isGranted) {
        await Permission.systemAlertWindow.request();
      }

      return allGranted;
    }
    return true;
  }

  Future<void> _moveVideoToDownloads(String sourcePath) async {
    if (!Platform.isAndroid) return;

    try {
      print('Checking source file: $sourcePath');
      final File sourceFile = File(sourcePath);

      // 检查文件是否存在
      final bool exists = await sourceFile.exists();
      print('Source file exists: $exists');

      if (!exists) {
        // 尝试列出源目录中的文件
        final Directory sourceDir =
            Directory(sourcePath.substring(0, sourcePath.lastIndexOf('/')));
        print('Listing directory: ${sourceDir.path}');
        final List<FileSystemEntity> files = await sourceDir.list().toList();
        print('Files in directory:');
        for (var file in files) {
          print('  ${file.path}');
        }
        return;
      }

      // 获取 Download 目录路径
      final downloadDir = Directory('/storage/emulated/0/Download');
      final bool downloadExists = await downloadDir.exists();
      print('Download directory exists: $downloadExists');

      if (!downloadExists) {
        print('Creating download directory');
        await downloadDir.create(recursive: true);
      }

      final String fileName = sourcePath.split('/').last;
      final String destinationPath = '${downloadDir.path}/$fileName';
      print('Destination path: $destinationPath');

      // 复制文件到 Download 目录
      final File newFile = await sourceFile.copy(destinationPath);
      print('File copied successfully: ${await newFile.exists()}');

      // 删除源文件
      await sourceFile.delete();
      print('Source file deleted');
    } catch (e, stackTrace) {
      print('Error moving video: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // 计算基准帧数
  int _calculateBaseFrames(double totalHeight, double frameSize) {
    // 计算需要滚动的实际距离
    double scrollDistance = totalHeight + frameSize * 0.1;

    // 假设每秒滚动 200 像素是适合阅读的速度
    double pixelsPerSecond = 200.0;

    // 计算需要的总秒数
    double totalSeconds = scrollDistance / pixelsPerSecond;

    // 转换为帧数（30fps）
    int baseFrames = (totalSeconds * 30).round();

    // 设置最小帧数，确保即使内容很少也有基本的动画效果
    return baseFrames.clamp(60, 900); // 最少2秒，最多30秒
  }

  Future<void> _generateVideo() async {
    if (_isGenerating) return;

    try {
      setState(() {
        _isGenerating = true;
        _generationProgress = 0.0;
        _progressText = '准备生成...';
      });

      // 1. 创建临时目录存放帧图片
      final tempDir = await getTemporaryDirectory();
      final framesDir = Directory('${tempDir.path}/frames');
      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create();

      // 2. 生成每一帧的图片
      // 使用1:1的正方形尺寸
      final frameSize = 1080.0; // 1080x1080 是社交媒体常用的尺寸

      // 计算所有消息的总高度
      double totalHeight = 0;
      final List<_MessageLayout> messageLayouts = [];

      // 先计算所有消息的布局
      for (final message in _messages) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${message.sender}: ${message.message}',
            style: const TextStyle(fontSize: 32), // 增大字体以适应视频尺寸
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: frameSize * 0.8);

        final messageHeight = textPainter.height + 40; // 添加边距
        totalHeight += messageHeight + 20; // 添加消息间距

        messageLayouts.add(_MessageLayout(
          message: message,
          textPainter: textPainter,
          height: messageHeight,
        ));
      }

      // 根据内容计算所需的基准帧数
      final int baseFrames = _calculateBaseFrames(totalHeight, frameSize);
      final int totalFrames = (baseFrames / _animationSpeed).round();

      print('Total height: $totalHeight px');
      print('Base frames: $baseFrames');
      print('Actual frames with speed ${_animationSpeed}x: $totalFrames');

      // 计算帧率 (在FFmpeg命令之前)
      final frameRate =
          (totalFrames / (totalHeight / (200.0 * _animationSpeed))).round();

      // 生成帧
      for (int frame = 0; frame < totalFrames; frame++) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        // 绘制白色背景
        canvas.drawRect(
          Rect.fromLTWH(0, 0, frameSize, frameSize),
          Paint()..color = Colors.white,
        );

        // 移除速度变量，因为已经通过帧数调整了
        final progress = frame / (totalFrames - 1);
        final currentY = frameSize - (totalHeight + frameSize * 0.1) * progress;

        // 绘制所有消息
        double y = currentY;
        for (final layout in messageLayouts) {
          if (y + layout.height > 0 && y < frameSize) {
            // 只绘制可见区域内的消息
            final x = layout.message.isLeft
                ? 40.0
                : frameSize - layout.textPainter.width - 40;

            // 绘制气泡背景
            final bubblePath = Path()
              ..addRRect(RRect.fromRectAndRadius(
                Rect.fromLTWH(
                  x - 20,
                  y,
                  layout.textPainter.width + 40,
                  layout.height,
                ),
                const Radius.circular(20),
              ));

            canvas.drawPath(
              bubblePath,
              Paint()
                ..color = layout.message.isLeft
                    ? Colors.grey[300]!
                    : Colors.blue[100]!
                ..style = PaintingStyle.fill,
            );

            // 修改这里：重新创建TextPainter并设置文字颜色
            final textPainter = TextPainter(
              text: TextSpan(
                text: '${layout.message.sender}: ${layout.message.message}',
                style: const TextStyle(
                  fontSize: 32,
                  color: Colors.black, // 设置文字颜色为黑色
                ),
              ),
              textDirection: TextDirection.ltr,
            );
            textPainter.layout(maxWidth: frameSize * 0.8);
            textPainter.paint(canvas, Offset(x, y + 20));
          }
          y += layout.height + 20;
        }

        // 保存帧
        final picture = recorder.endRecording();
        final image =
            await picture.toImage(frameSize.toInt(), frameSize.toInt());
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final buffer = byteData!.buffer.asUint8List();

        final frameFile = File(
            '${framesDir.path}/frame_${frame.toString().padLeft(4, '0')}.png');
        await frameFile.writeAsBytes(buffer);

        // 更新进度
        setState(() {
          _generationProgress = (frame + 1) / totalFrames * 0.8; // 帧生成占80%进度
          _progressText = '生成帧 ${frame + 1}/$totalFrames';
        });
      }

      setState(() {
        _progressText = '正在合成视频...';
        _generationProgress = 0.8; // 开始FFmpeg处理
      });

      // 3. 使用FFmpeg将图片序列转换为视频
      _currentVideoPath = await _getVideoSavePath();

      // 确保输出目录存在
      final outputDir = Directory(
          _currentVideoPath!.substring(0, _currentVideoPath!.lastIndexOf('/')));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // 更新FFmpeg命令，确保使用正确的帧率
      final command = '''
        -y \
        -f image2 \
        -framerate $frameRate \
        -i ${framesDir.path}/frame_%04d.png \
        -c:v mpeg4 \
        -q:v 1 \
        -pix_fmt yuv420p \
        ${_currentVideoPath}
      '''
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      print('Executing FFmpeg command: $command');
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      // 获取完整的输出和日志
      final output = await session.getOutput();
      final logs = await session.getLogs();
      print('FFmpeg complete output:');
      print(output);
      print('\nFFmpeg complete logs:');
      for (var log in logs) {
        print('${log.getLevel()}: ${log.getMessage()}');
      }

      if (ReturnCode.isSuccess(returnCode)) {
        setState(() {
          _progressText = '保存视频文件...';
          _generationProgress = 0.9;
        });

        print('Video generation completed successfully');

        // 检查生成的视频文件
        final videoFile = File(_currentVideoPath!);
        final videoExists = await videoFile.exists();
        final videoSize = await videoFile.length();
        print('Generated video exists: $videoExists');
        print('Generated video size: $videoSize bytes');

        if (mounted && _currentVideoPath != null) {
          await _moveVideoToDownloads(_currentVideoPath!);
          final String fileName = _currentVideoPath!.split('/').last;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 5),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('视频生成成功！'),
                  const SizedBox(height: 4),
                  Text(
                    '保存在手机的Download文件夹中',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text('文件名: $fileName', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          );
        }
      } else {
        final failureStack = StringBuffer();
        failureStack.writeln('Video generation failed:');
        failureStack.writeln('Return code: $returnCode');
        failureStack.writeln('State: ${await session.getState()}');
        failureStack.writeln('\nComplete output:');
        failureStack.writeln(output);
        failureStack.writeln('\nComplete logs:');
        for (var log in logs) {
          failureStack.writeln('${log.getLevel()}: ${log.getMessage()}');
        }
        print(failureStack.toString());
        throw Exception(failureStack.toString());
      }

      // 清理临时文件
      await framesDir.delete(recursive: true);
    } catch (e, stackTrace) {
      print('Error in video generation process: $e');
      print('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('生成视频时出现错误: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      setState(() {
        _isGenerating = false;
        _generationProgress = 0.0;
        _progressText = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('对话视频生成器'),
        actions: [
          IconButton(
            icon: Icon(
                _isGenerating ? Icons.hourglass_empty : Icons.movie_creation),
            color: _isGenerating ? Colors.orange : null,
            onPressed: _generateVideo,
          ),
        ],
        // 添加进度条
        bottom: _isGenerating
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4.0),
                child: Column(
                  children: [
                    LinearProgressIndicator(value: _generationProgress),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        _progressText,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // 添加速度控制滑块
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('滚动速度'),
                    Text('${_animationSpeed.toStringAsFixed(1)}x'),
                  ],
                ),
                Slider(
                  value: _animationSpeed,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  label: '${_animationSpeed.toStringAsFixed(1)}x',
                  onChanged: (value) {
                    setState(() {
                      _animationSpeed = value;
                    });
                  },
                ),
              ],
            ),
          ),
          // 聊天列表现在需要放在Expanded中
          Expanded(
            child: ListView.builder(
              key: _chatKey,
              controller: _scrollController,
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                return ChatBubble(message: message);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String sender;
  final String message;
  final bool isLeft;

  ChatMessage({
    required this.sender,
    required this.message,
    required this.isLeft,
  });
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment:
            message.isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (!message.isLeft) const Spacer(),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: message.isLeft ? Colors.grey[300] : Colors.blue[100],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.sender,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(message.message),
              ],
            ),
          ),
          if (message.isLeft) const Spacer(),
        ],
      ),
    );
  }
}

class _MessageLayout {
  final ChatMessage message;
  final TextPainter textPainter;
  final double height;

  _MessageLayout({
    required this.message,
    required this.textPainter,
    required this.height,
  });
}

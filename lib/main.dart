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

  // 示例��据
  final List<ChatMessage> _messages = [
    ChatMessage(sender: "用户A", message: "你好！", isLeft: true),
    ChatMessage(sender: "用户B", message: "你好！很高兴见到你。", isLeft: false),
    ChatMessage(sender: "用户A", message: "今天天气真不错。", isLeft: true),
    ChatMessage(sender: "用户B", message: "是的，阳光明媚。", isLeft: false),
  ];

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

      // 请求所有必要的权限
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

  Future<void> _generateVideo() async {
    if (_isGenerating) return;

    try {
      setState(() => _isGenerating = true);

      // 1. 创建临时目录存放帧图片
      final tempDir = await getTemporaryDirectory();
      final framesDir = Directory('${tempDir.path}/frames');
      if (await framesDir.exists()) {
        await framesDir.delete(recursive: true);
      }
      await framesDir.create();

      // 2. 生成每一帧的图片
      final frameWidth = MediaQuery.of(context).size.width;
      final frameHeight = MediaQuery.of(context).size.height;

      for (int i = 0; i < _messages.length; i++) {
        // 为每一帧创建新的 recorder 和 canvas
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);

        // 清空画布
        canvas.drawColor(Colors.white, BlendMode.src);

        // 绘制消息
        final message = _messages[i];
        final textPainter = TextPainter(
          text: TextSpan(
            text: '${message.sender}: ${message.message}',
            style: const TextStyle(fontSize: 16),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout(maxWidth: frameWidth * 0.8);

        final x = message.isLeft ? 20.0 : frameWidth - textPainter.width - 20;
        final y = frameHeight - (i + 1) * 60.0;

        // 绘制气泡背景
        final paint = Paint()
          ..color = message.isLeft ? Colors.grey[300]! : Colors.blue[100]!;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x - 10, y - 10, textPainter.width + 20,
                textPainter.height + 20),
            const Radius.circular(20),
          ),
          paint,
        );

        textPainter.paint(canvas, Offset(x, y));

        // 保存帧
        final picture = recorder.endRecording();
        final image =
            await picture.toImage(frameWidth.toInt(), frameHeight.toInt());
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        final buffer = byteData!.buffer.asUint8List();

        final frameFile = File('${framesDir.path}/frame_$i.png');
        await frameFile.writeAsBytes(buffer);
      }

      // 3. 使用FFmpeg将图片序列转换为视频
      _currentVideoPath = await _getVideoSavePath();

      // 确保输出目录存在
      final outputDir = Directory(
          _currentVideoPath!.substring(0, _currentVideoPath!.lastIndexOf('/')));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      // 检查源文件是否存在
      final firstFrame = File('${framesDir.path}/frame_0.png');
      if (!await firstFrame.exists()) {
        throw Exception('Source frames not found');
      }
      print('First frame exists: ${await firstFrame.exists()}');
      print('First frame size: ${await firstFrame.length()} bytes');

      // 列出所有帧文件
      final List<FileSystemEntity> frameFiles = await framesDir.list().toList();
      print('Total frames: ${frameFiles.length}');
      for (var file in frameFiles) {
        print('Frame file: ${file.path}');
      }

      // 使用更简单的FFmpeg命令，使用 mpeg4 编码器
      final command = '''
        -y \
        -f image2 \
        -framerate 1 \
        -i ${framesDir.path}/frame_%d.png \
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
      setState(() => _isGenerating = false);
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
      ),
      body: ListView.builder(
        key: _chatKey,
        controller: _scrollController,
        reverse: true,
        itemCount: _messages.length,
        itemBuilder: (context, index) {
          final message = _messages[index];
          return ChatBubble(message: message);
        },
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

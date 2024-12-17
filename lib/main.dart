import 'package:flutter/material.dart';
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter/return_code.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/services.dart';

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
    ChatMessage(
      sender: "用户A",
      message: "你好！",
      isLeft: true,
      avatar: 'assets/avatar_a.png',
    ),
    ChatMessage(
      sender: "用户B",
      message: "你好！很高兴见到你。",
      isLeft: false,
      avatar: 'assets/avatar_b.png',
    ),
    ChatMessage(
      sender: "用户A",
      message: "今天天气真不错。",
      isLeft: true,
      avatar: 'assets/avatar_a.png',
    ),
    ChatMessage(
      sender: "用户B",
      message: "是的，阳光明媚，很适合出去走走。",
      isLeft: false,
      avatar: 'assets/avatar_b.png',
    ),
    ChatMessage(
      sender: "用户A",
      message: "你末有什么计划吗？",
      isLeft: true,
      avatar: 'assets/avatar_a.png',
    ),
    ChatMessage(
      sender: "用户B",
      message: "我打算去公园野餐，你要一起来吗？",
      isLeft: false,
      avatar: 'assets/avatar_b.png',
    ),
    ChatMessage(
      sender: "用户A",
      message: "听起来不错！需要我带些什么吗？",
      isLeft: true,
      avatar: 'assets/avatar_a.png',
    ),
    ChatMessage(
      sender: "用户B",
      message: "你可以带些水果或饮料，我来准备主食。",
      isLeft: false,
      avatar: 'assets/avatar_b.png',
    ),
    ChatMessage(
      sender: "用户A",
      message: "好的，我带些苹果和橙汁。几点见面？",
      isLeft: true,
      avatar: 'assets/avatar_a.png',
    ),
    ChatMessage(
      sender: "用户B",
      message: "上午10点如何？这个时间阳光正好。",
      isLeft: false,
      avatar: 'assets/avatar_b.png',
    ),
  ];

  // 添加进度变量
  double _generationProgress = 0.0;
  String _progressText = '';

  // 添加速度控制变量
  double _animationSpeed = 1.0; // 默认速度为1.0

  // 添加用户名字体大小控制
  double _senderFontSize = 24.0;

  // 添加界面控制相关的状态变量
  Color _leftBubbleColor = Colors.white;
  Color _rightBubbleColor = const Color(0xFF95EC69);
  Color _leftTextColor = Colors.black;
  Color _rightTextColor = Colors.black;
  double _bubbleRadius = 20.0;
  double _fontSize = 20.0;

  // 添加颜色选择器对话框
  Future<Color?> _showColorPicker(BuildContext context, Color initialColor) {
    return showDialog<Color>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('选择颜色'),
          content: SingleChildScrollView(
            child: ColorPicker(
              pickerColor: initialColor,
              onColorChanged: (Color color) {
                initialColor = color;
              },
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('确定'),
              onPressed: () => Navigator.of(context).pop(initialColor),
            ),
          ],
        );
      },
    );
  }

  // 添加一个方法来确保值在围内
  double _clampFontSize(double value) {
    return value.clamp(20.0, 48.0);
  }

  double _clampSenderFontSize(double value) {
    return value.clamp(16.0, 36.0);
  }

  @override
  void initState() {
    super.initState();
    // 确保初始值在有效范围内
    _fontSize = _clampFontSize(_fontSize);
    _senderFontSize = _clampSenderFontSize(_senderFontSize);
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

      // 计算所有消息的布局
      for (final message in _messages) {
        final senderTextPainter = TextPainter(
          text: TextSpan(
            text: message.sender,
            style: TextStyle(
              fontSize: _senderFontSize,
              color: Colors.grey[600], // 用户名使用灰色
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        senderTextPainter.layout(maxWidth: frameSize * 0.8);

        final messageTextPainter = TextPainter(
          text: TextSpan(
            text: message.message,
            style: TextStyle(
              fontSize: _fontSize,
              color: message.isLeft ? _leftTextColor : _rightTextColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        messageTextPainter.layout(maxWidth: frameSize * 0.8);

        final messageHeight =
            senderTextPainter.height + 4 + messageTextPainter.height + 20;
        totalHeight += messageHeight + 20;

        messageLayouts.add(_MessageLayout(
          message: message,
          senderTextPainter: senderTextPainter,
          messageTextPainter: messageTextPainter,
          height: messageHeight,
        ));
      }

      // 根据内容计算所需的标准帧数
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

        // 计算当前帧的垂直偏移
        final progress = frame / (totalFrames - 1);
        final currentY = frameSize - (totalHeight + frameSize * 0.1) * progress;

        // 绘制所有消息
        double y = currentY;
        for (final layout in messageLayouts) {
          if (y + layout.height > 0 && y < frameSize) {
            // 计算基础x坐标，考虑头像空间
            final baseX = layout.message.isLeft
                ? 80.0 // 40(边距) + 40(头像空间)
                : frameSize -
                    max(layout.senderTextPainter.width,
                        layout.messageTextPainter.width) -
                    80;

            // 绘制头像
            final avatarImage = await loadImage(layout.message.avatar);
            final avatarRect = Rect.fromCircle(
              center: Offset(
                layout.message.isLeft ? 40 : frameSize - 40,
                y + layout.senderTextPainter.height + 30,
              ),
              radius: 20,
            );

            // 绘制圆形头像
            final avatarPath = Path()..addOval(avatarRect);
            canvas.save();
            canvas.clipPath(avatarPath);
            canvas.drawImageRect(
              avatarImage,
              Rect.fromLTWH(0, 0, avatarImage.width.toDouble(),
                  avatarImage.height.toDouble()),
              avatarRect,
              Paint(),
            );
            canvas.restore();

            // 绘制用户名
            layout.senderTextPainter.paint(canvas, Offset(baseX, y));

            // 绘制气泡
            final bubblePath = Path();
            final bubbleRect = RRect.fromRectAndCorners(
              Rect.fromLTWH(
                baseX - 16,
                y + layout.senderTextPainter.height + 4,
                layout.messageTextPainter.width + 32,
                layout.messageTextPainter.height + 20,
              ),
              topLeft:
                  Radius.circular(layout.message.isLeft ? 0 : _bubbleRadius),
              topRight:
                  Radius.circular(layout.message.isLeft ? _bubbleRadius : 0),
              bottomLeft: Radius.circular(_bubbleRadius),
              bottomRight: Radius.circular(_bubbleRadius),
            );
            bubblePath.addRRect(bubbleRect);

            canvas.drawPath(
              bubblePath,
              Paint()
                ..color =
                    layout.message.isLeft ? _leftBubbleColor : _rightBubbleColor
                ..style = PaintingStyle.fill,
            );

            // 绘制消息文本
            layout.messageTextPainter.paint(canvas,
                Offset(baseX, y + layout.senderTextPainter.height + 14));
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

  // 添加图片加载辅助方法
  Future<ui.Image> loadImage(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo fi = await codec.getNextFrame();
    return fi.image;
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
          // 添加设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                builder: (BuildContext context) {
                  return StatefulBuilder(
                    builder: (BuildContext context, StateSetter setModalState) {
                      return SingleChildScrollView(
                        child: Column(
                          children: [
                            ListTile(
                              title: const Text('左气泡颜色'),
                              trailing: Container(
                                width: 24,
                                height: 24,
                                color: _leftBubbleColor,
                              ),
                              onTap: () async {
                                final color = await _showColorPicker(
                                    context, _leftBubbleColor);
                                if (color != null) {
                                  setState(() => _leftBubbleColor = color);
                                  setModalState(() {});
                                }
                              },
                            ),
                            ListTile(
                              title: const Text('右侧气泡颜色'),
                              trailing: Container(
                                width: 24,
                                height: 24,
                                color: _rightBubbleColor,
                              ),
                              onTap: () async {
                                final color = await _showColorPicker(
                                    context, _rightBubbleColor);
                                if (color != null) {
                                  setState(() => _rightBubbleColor = color);
                                  setModalState(() {});
                                }
                              },
                            ),
                            ListTile(
                              title: const Text('左侧文字颜色'),
                              trailing: Container(
                                width: 24,
                                height: 24,
                                color: _leftTextColor,
                              ),
                              onTap: () async {
                                final color = await _showColorPicker(
                                    context, _leftTextColor);
                                if (color != null) {
                                  setState(() => _leftTextColor = color);
                                  setModalState(() {});
                                }
                              },
                            ),
                            ListTile(
                              title: const Text('右侧文字颜色'),
                              trailing: Container(
                                width: 24,
                                height: 24,
                                color: _rightTextColor,
                              ),
                              onTap: () async {
                                final color = await _showColorPicker(
                                    context, _rightTextColor);
                                if (color != null) {
                                  setState(() => _rightTextColor = color);
                                  setModalState(() {});
                                }
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('气泡圆角'),
                                      Text(
                                          '${_bubbleRadius.toStringAsFixed(1)}'),
                                    ],
                                  ),
                                  Slider(
                                    value: _bubbleRadius,
                                    min: 0,
                                    max: 40,
                                    divisions: 40,
                                    label: _bubbleRadius.toStringAsFixed(1),
                                    onChanged: (value) {
                                      setState(() => _bubbleRadius = value);
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('字体大小'),
                                      Text('${_fontSize.toStringAsFixed(1)}'),
                                    ],
                                  ),
                                  Slider(
                                    value: _fontSize,
                                    min: 20.0,
                                    max: 48.0,
                                    divisions: 28,
                                    label: _fontSize.toStringAsFixed(1),
                                    onChanged: (value) {
                                      setState(() =>
                                          _fontSize = _clampFontSize(value));
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text('用户名字体大小'),
                                      Text(
                                          '${_senderFontSize.toStringAsFixed(1)}'),
                                    ],
                                  ),
                                  Slider(
                                    value: _senderFontSize,
                                    min: 16.0,
                                    max: 36.0,
                                    divisions: 20,
                                    label: _senderFontSize.toStringAsFixed(1),
                                    onChanged: (value) {
                                      setState(() => _senderFontSize =
                                          _clampSenderFontSize(value));
                                      setModalState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
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
                return ChatBubble(
                  message: message,
                  leftBubbleColor: _leftBubbleColor,
                  rightBubbleColor: _rightBubbleColor,
                  leftTextColor: _leftTextColor,
                  rightTextColor: _rightTextColor,
                  bubbleRadius: _bubbleRadius,
                  fontSize: _fontSize,
                  senderFontSize: _senderFontSize,
                );
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
  final String avatar; // 新增头像字段

  ChatMessage({
    required this.sender,
    required this.message,
    required this.isLeft,
    this.avatar = 'assets/default_avatar.png', // 默认头像
  });
}

class ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final Color leftBubbleColor;
  final Color rightBubbleColor;
  final Color leftTextColor;
  final Color rightTextColor;
  final double bubbleRadius;
  final double fontSize;
  final double senderFontSize;

  const ChatBubble({
    super.key,
    required this.message,
    required this.leftBubbleColor,
    required this.rightBubbleColor,
    required this.leftTextColor,
    required this.rightTextColor,
    required this.bubbleRadius,
    required this.fontSize,
    required this.senderFontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment:
            message.isLeft ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          // 发送者名字
          Padding(
            padding: EdgeInsets.only(
              left: message.isLeft ? 48 : 0, // 为头像留出空间
              right: message.isLeft ? 0 : 48,
              bottom: 4,
            ),
            child: Text(
              message.sender,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: senderFontSize,
                color: message.isLeft
                    ? leftTextColor
                    : rightTextColor, // 确保使用正确的颜色
              ),
            ),
          ),
          // 消息行
          Row(
            mainAxisAlignment: message.isLeft
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start, // 确保头像与气泡顶部对齐
            children: [
              if (!message.isLeft) const Spacer(),
              if (message.isLeft)
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: AssetImage(message.avatar),
                  ),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth:
                      MediaQuery.of(context).size.width * 0.65, // 稍微减小以适应头像
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: message.isLeft ? leftBubbleColor : rightBubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft:
                          Radius.circular(message.isLeft ? 0 : bubbleRadius),
                      topRight:
                          Radius.circular(message.isLeft ? bubbleRadius : 0),
                      bottomLeft: Radius.circular(bubbleRadius),
                      bottomRight: Radius.circular(bubbleRadius),
                    ),
                  ),
                  child: Text(
                    message.message,
                    style: TextStyle(
                      fontSize: fontSize,
                      color: message.isLeft
                          ? leftTextColor
                          : rightTextColor, // 确保使用正确的颜色
                    ),
                  ),
                ),
              ),
              if (message.isLeft) const Spacer(),
              if (!message.isLeft)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundImage: AssetImage(message.avatar),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageLayout {
  final ChatMessage message;
  final TextPainter senderTextPainter;
  final TextPainter messageTextPainter;
  final double height;

  _MessageLayout({
    required this.message,
    required this.senderTextPainter,
    required this.messageTextPainter,
    required this.height,
  });
}

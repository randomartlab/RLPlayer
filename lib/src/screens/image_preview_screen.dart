/// 图片预览页（本地文件 / 在线 URL，2026-09-02 用户需求：
/// 文件树内非封面图片浏览，类似打开歌词）。
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../utils/ui_tokens.dart';

class ImagePreviewScreen extends StatefulWidget {
  const ImagePreviewScreen.local({super.key, required this.filePath})
      : url = null,
        title = null;

  const ImagePreviewScreen.network({super.key, required this.url, this.title})
      : filePath = null;

  final String? filePath;
  final String? url;
  final String? title;

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title ?? (widget.filePath?.split('/').last ?? '图片'),
          style: const TextStyle(fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: widget.filePath != null
              ? Image.file(
                  File(widget.filePath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          size: 56, color: Colors.white54),
                      const SizedBox(height: UiSpacing.medium),
                      Text('图片无法解码',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : Image.network(
                  widget.url!,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) =>
                      progress == null
                          ? child
                          : const Center(
                              child: CircularProgressIndicator()),
                  errorBuilder: (_, _, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          size: 56, color: Colors.white54),
                      const SizedBox(height: UiSpacing.medium),
                      Text('图片加载失败',
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

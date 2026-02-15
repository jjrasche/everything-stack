import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ScreenshotService {
  static final ScreenshotService instance = ScreenshotService._();
  ScreenshotService._();

  GlobalKey? _boundaryKey;
  final String _screenshotDir = 'logs/screenshots';

  /// Set the RepaintBoundary key (called by ScreenshotWrapper)
  void setBoundaryKey(GlobalKey key) {
    _boundaryKey = key;
  }

  /// Capture current screen and save to file
  /// Returns the file path, or null if capture failed
  Future<String?> capture({String context = 'manual'}) async {
    if (_boundaryKey == null) {
      print('⚠️ [ScreenshotService] No boundary key set');
      return null;
    }

    try {
      final boundary = _boundaryKey!.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        print('⚠️ [ScreenshotService] Could not find RenderRepaintBoundary');
        return null;
      }

      // Capture image
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        print('⚠️ [ScreenshotService] Failed to convert image to bytes');
        return null;
      }

      // Ensure directory exists
      final dir = Directory(_screenshotDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // Generate filename with timestamp
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final filename = '$timestamp-$context.png';
      final filePath = '$_screenshotDir/$filename';

      final file = File(filePath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      print('📸 [ScreenshotService] Saved: $filePath');
      return filePath;
    } catch (e) {
      print('⚠️ [ScreenshotService] Capture failed: $e');
      return null;
    }
  }

  /// Capture and save with automatic context detection
  Future<String?> captureWithContext(String context) async {
    return capture(context: context);
  }

  /// Get list of recent screenshots
  Future<List<String>> getRecentScreenshots({int limit = 10}) async {
    try {
      final dir = Directory(_screenshotDir);
      if (!await dir.exists()) return [];

      final files = await dir.list().toList();
      final pngFiles = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();

      pngFiles.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

      return pngFiles.take(limit).map((f) => f.path).toList();
    } catch (e) {
      return [];
    }
  }
}

/// Wrapper widget that enables screenshot capture
/// Place this at the root of your app widget tree
class ScreenshotWrapper extends StatefulWidget {
  final Widget child;

  const ScreenshotWrapper({super.key, required this.child});

  @override
  State<ScreenshotWrapper> createState() => _ScreenshotWrapperState();
}

class _ScreenshotWrapperState extends State<ScreenshotWrapper> {
  final GlobalKey _boundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Register key with service after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScreenshotService.instance.setBoundaryKey(_boundaryKey);
    });
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _boundaryKey,
      child: widget.child,
    );
  }
}

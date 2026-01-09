import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';

import 'ocr_models.dart'; // To access OcrHistoryItem and OcrStats

class OcrController extends GetxController
    with GetSingleTickerProviderStateMixin {
  // Storage keys
  static const _kHistoryKey = 'ocr_history_v1';
  static const _kStatsKey = 'ocr_stats_v1';

  final _picker = ImagePicker();
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  // Observable variables
  final camera = Rxn<CameraController>();
  final cameraReady = false.obs;
  final isExtracting = false.obs;
  final error = RxnString();
  final currentText = RxnString();
  final currentImagePath = RxnString();
  final history = <OcrHistoryItem>[].obs;
  final stats = OcrStats.empty().obs;
  final historyOpen = false.obs;

  final historySearch = TextEditingController();

  // Scan overlay animation
  late AnimationController scanCtrl;

  @override
  void onInit() {
    super.onInit();
    scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    bootstrap();

    // Listen to search changes
    historySearch.addListener(() {
      update(['history_list']);
    });
  }

  @override
  void onClose() {
    historySearch.dispose();
    scanCtrl.dispose();
    camera.value?.dispose();
    _recognizer.close();
    super.onClose();
  }

  Future<void> bootstrap() async {
    await loadLocal();
    await ensurePermissions();
    await initCamera();
  }

  Future<void> ensurePermissions() async {
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      error.value = 'Camera permission is required for live scanning.';
    }

    await Permission.photos.request();
    await Permission.storage.request();
  }

  Future<void> initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        cameraReady.value = false;
        error.value = 'No camera found on this device.';
        return;
      }

      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      camera.value = controller;
      cameraReady.value = true;
    } catch (e) {
      cameraReady.value = false;
      error.value = 'Failed to initialize camera: $e';
    }
  }

  Future<void> loadLocal() async {
    final sp = await SharedPreferences.getInstance();

    final histRaw = sp.getString(_kHistoryKey);
    if (histRaw != null && histRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(histRaw);
        if (decoded is List) {
          history.value = decoded
              .whereType<Map>()
              .map((m) => OcrHistoryItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
              .reversed
              .toList();
        }
      } catch (_) {}
    }

    final statsRaw = sp.getString(_kStatsKey);
    if (statsRaw != null && statsRaw.trim().isNotEmpty) {
      try {
        stats.value = OcrStats.fromJson(
          Map<String, dynamic>.from(jsonDecode(statsRaw)),
        );
      } catch (_) {}
    }
  }

  Future<void> persistLocal() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kHistoryKey,
      jsonEncode(history.reversed.map((e) => e.toJson()).toList()),
    );
    await sp.setString(_kStatsKey, jsonEncode(stats.value.toJson()));
  }

  Future<String> _saveImageToAppDir(File src) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'ocr_images'));
    if (!imagesDir.existsSync()) imagesDir.createSync(recursive: true);

    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final ext = p.extension(src.path).isNotEmpty
        ? p.extension(src.path)
        : '.jpg';
    final destPath = p.join(imagesDir.path, 'scan_$id$ext');

    await src.copy(destPath);
    return destPath;
  }

  Future<void> extractFromFile(File file) async {
    isExtracting.value = true;
    error.value = null;

    try {
      final savedPath = await _saveImageToAppDir(file);

      final input = InputImage.fromFilePath(savedPath);
      final recognized = await _recognizer.processImage(input);
      final text = recognized.text.trim();

      final finalText = text.isEmpty ? 'No text detected' : text;
      final preview = finalText.length > 80
          ? '${finalText.substring(0, 80)}\u2026'
          : finalText;

      final item = OcrHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        preview: preview,
        fullText: finalText,
        imagePath: savedPath,
      );

      history.insert(0, item);

      stats.value = stats.value.copyWith(
        totalScans: stats.value.totalScans + 1,
        totalCharacters: stats.value.totalCharacters + finalText.length,
        lastScanAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await persistLocal();

      currentText.value = finalText;
      currentImagePath.value = savedPath;
    } catch (e) {
      error.value = 'Failed to extract text. Please ensure the image is clear.';
    } finally {
      isExtracting.value = false;
    }
  }

  Future<void> capture() async {
    if (camera.value == null || !cameraReady.value) return;
    if (isExtracting.value) return;

    try {
      final c = camera.value!;
      if (c.value.isTakingPicture) return;

      final x = await c.takePicture();
      await extractFromFile(File(x.path));
    } catch (e) {
      error.value = 'Capture failed: $e';
    }
  }

  Future<void> pickFromGallery() async {
    if (isExtracting.value) return;
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (x == null) return;
      await extractFromFile(File(x.path));
    } catch (e) {
      error.value = 'Failed to pick image: $e';
    }
  }

  void openHistory() {
    historyOpen.value = true;
    historySearch.text = '';
  }

  void closeHistory() => historyOpen.value = false;

  void clearError() => error.value = null;

  void closeResult() {
    currentText.value = null;
    currentImagePath.value = null;
  }

  void selectHistoryItem(OcrHistoryItem item) {
    currentText.value = item.fullText;
    currentImagePath.value = item.imagePath;
    historyOpen.value = false;
  }

  Future<void> clearAllHistory() async {
    history.clear();
    stats.value = OcrStats.empty();
    await persistLocal();
  }

  List<OcrHistoryItem> get filteredHistory {
    final q = historySearch.text.trim().toLowerCase();
    if (q.isEmpty) return history;
    return history
        .where(
          (h) =>
              h.preview.toLowerCase().contains(q) ||
              h.fullText.toLowerCase().contains(q),
        )
        .toList();
  }
}

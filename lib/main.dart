import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Keep immersive feel similar to the web full-screen experience
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const FreeLensOcrApp());
}

class FreeLensOcrApp extends StatelessWidget {
  const FreeLensOcrApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF10B981), // emerald
        brightness: Brightness.dark,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Free Lens OCR',
      theme: base.copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617), // slate-950
        textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
          bodyColor: const Color(0xFFE2E8F0), // slate-200
          displayColor: const Color(0xFFE2E8F0),
        ),
      ),
      home: const OcrHomePage(),
    );
  }
}

class OcrHistoryItem {
  final String id;
  final int timestampMs;
  final String preview;
  final String fullText;
  final String imagePath;

  OcrHistoryItem({
    required this.id,
    required this.timestampMs,
    required this.preview,
    required this.fullText,
    required this.imagePath,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestampMs': timestampMs,
    'preview': preview,
    'fullText': fullText,
    'imagePath': imagePath,
  };

  static OcrHistoryItem fromJson(Map<String, dynamic> j) => OcrHistoryItem(
    id: j['id'] as String,
    timestampMs: (j['timestampMs'] as num).toInt(),
    preview: (j['preview'] as String?) ?? '',
    fullText: (j['fullText'] as String?) ?? '',
    imagePath: (j['imagePath'] as String?) ?? '',
  );
}

class OcrStats {
  final int totalScans;
  final int totalCharacters;
  final int? lastScanAtMs;

  OcrStats({
    required this.totalScans,
    required this.totalCharacters,
    required this.lastScanAtMs,
  });

  Map<String, dynamic> toJson() => {
    'totalScans': totalScans,
    'totalCharacters': totalCharacters,
    'lastScanAtMs': lastScanAtMs,
  };

  static OcrStats fromJson(Map<String, dynamic> j) => OcrStats(
    totalScans: (j['totalScans'] as num?)?.toInt() ?? 0,
    totalCharacters: (j['totalCharacters'] as num?)?.toInt() ?? 0,
    lastScanAtMs: (j['lastScanAtMs'] as num?)?.toInt(),
  );

  static OcrStats empty() =>
      OcrStats(totalScans: 0, totalCharacters: 0, lastScanAtMs: null);

  OcrStats copyWith({
    int? totalScans,
    int? totalCharacters,
    int? lastScanAtMs,
  }) => OcrStats(
    totalScans: totalScans ?? this.totalScans,
    totalCharacters: totalCharacters ?? this.totalCharacters,
    lastScanAtMs: lastScanAtMs ?? this.lastScanAtMs,
  );
}

class OcrHomePage extends StatefulWidget {
  const OcrHomePage({super.key});

  @override
  State<OcrHomePage> createState() => _OcrHomePageState();
}

class _OcrHomePageState extends State<OcrHomePage>
    with TickerProviderStateMixin {
  // Storage keys matching the web style/versioning
  static const _kHistoryKey = 'ocr_history_v1';
  static const _kStatsKey = 'ocr_stats_v1';

  final _picker = ImagePicker();
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  bool _cameraReady = false;

  bool _isExtracting = false;
  String? _error;

  // Current result overlay
  String? _currentText;
  String? _currentImagePath;

  // History / stats
  List<OcrHistoryItem> _history = [];
  OcrStats _stats = OcrStats.empty();

  // History drawer
  bool _historyOpen = false;
  final _historySearch = TextEditingController();

  // Scan overlay animation
  late final AnimationController _scanCtrl;

  @override
  void initState() {
    super.initState();
    _scanCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _bootstrap();
  }

  @override
  void dispose() {
    _historySearch.dispose();
    _scanCtrl.dispose();
    _camera?.dispose();
    _recognizer.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadLocal();
    await _ensurePermissions();
    await _initCamera();
  }

  Future<void> _ensurePermissions() async {
    // Camera permission
    final cam = await Permission.camera.request();
    if (!cam.isGranted) {
      setState(
        () => _error = 'Camera permission is required for live scanning.',
      );
    }

    // Gallery pick permission (best-effort; Android 13+ uses picker)
    await Permission.photos.request();
    await Permission.storage.request();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _cameraReady = false;
          _error = 'No camera found on this device.';
        });
        return;
      }

      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await controller.initialize();

      if (!mounted) return;
      setState(() {
        _camera = controller;
        _cameraReady = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraReady = false;
        _error = 'Failed to initialize camera: $e';
      });
    }
  }

  Future<void> _loadLocal() async {
    final sp = await SharedPreferences.getInstance();

    final histRaw = sp.getString(_kHistoryKey);
    if (histRaw != null && histRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(histRaw);
        if (decoded is List) {
          _history = decoded
              .whereType<Map>()
              .map((m) => OcrHistoryItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
              .reversed
              .toList(); // newest first
        }
      } catch (_) {}
    }

    final statsRaw = sp.getString(_kStatsKey);
    if (statsRaw != null && statsRaw.trim().isNotEmpty) {
      try {
        _stats = OcrStats.fromJson(
          Map<String, dynamic>.from(jsonDecode(statsRaw)),
        );
      } catch (_) {}
    }

    if (mounted) setState(() {});
  }

  Future<void> _persistLocal() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kHistoryKey,
      jsonEncode(_history.reversed.map((e) => e.toJson()).toList()),
    );
    await sp.setString(_kStatsKey, jsonEncode(_stats.toJson()));
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

  Future<void> _extractFromFile(File file) async {
    setState(() {
      _isExtracting = true;
      _error = null;
    });

    try {
      final savedPath = await _saveImageToAppDir(file);

      final input = InputImage.fromFilePath(savedPath);
      final recognized = await _recognizer.processImage(input);
      final text = recognized.text.trim();

      final finalText = text.isEmpty ? 'No text detected' : text;
      final preview = finalText.length > 80
          ? '${finalText.substring(0, 80)}…'
          : finalText;

      final item = OcrHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        preview: preview,
        fullText: finalText,
        imagePath: savedPath,
      );

      _history.insert(0, item);

      _stats = _stats.copyWith(
        totalScans: _stats.totalScans + 1,
        totalCharacters: _stats.totalCharacters + finalText.length,
        lastScanAtMs: DateTime.now().millisecondsSinceEpoch,
      );

      await _persistLocal();

      setState(() {
        _currentText = finalText;
        _currentImagePath = savedPath;
      });
    } catch (e) {
      setState(
        () => _error =
            'Failed to extract text. Please ensure the image is clear.',
      );
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
    }
  }

  Future<void> _capture() async {
    if (_camera == null || !_cameraReady) return;
    if (_isExtracting) return;

    try {
      final c = _camera!;
      if (c.value.isTakingPicture) return;

      final x = await c.takePicture();
      await _extractFromFile(File(x.path));
    } catch (e) {
      setState(() => _error = 'Capture failed: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_isExtracting) return;
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (x == null) return;
      await _extractFromFile(File(x.path));
    } catch (e) {
      setState(() => _error = 'Failed to pick image: $e');
    }
  }

  void _openHistory() {
    setState(() {
      _historyOpen = true;
      _historySearch.text = '';
    });
  }

  void _closeHistory() => setState(() => _historyOpen = false);

  List<OcrHistoryItem> get _filteredHistory {
    final q = _historySearch.text.trim().toLowerCase();
    if (q.isEmpty) return _history;
    return _history
        .where(
          (h) =>
              h.preview.toLowerCase().contains(q) ||
              h.fullText.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;

    // Match the web sizing idea: w=min(90vw, 520px), aspect 3/4
    final viewfinderW = min(w * 0.90, 520.0);
    final viewfinderH = min(viewfinderW * (4 / 3), h * 0.62);

    return Scaffold(
      body: Stack(
        children: [
          // Background base + subtle radial “glow” like the Tailwind app
          Container(decoration: const BoxDecoration(color: Color(0xFF020617))),
          Positioned(
            top: -220,
            left: -180,
            child: Container(
              width: 520,
              height: 520,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x3310B981), Color(0x00020617)],
                ),
              ),
            ),
          ),

          // Camera preview (behind everything)
          if (_cameraReady && _camera != null)
            Positioned.fill(
              child: IgnorePointer(
                // Equivalent to pointer-events:none on iframe/video
                ignoring: true,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _camera!.value.previewSize?.height ?? w,
                    height: _camera!.value.previewSize?.width ?? h,
                    child: CameraPreview(_camera!),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Center(
                child: Text(
                  _error ?? 'Camera loading…',
                  style: const TextStyle(color: Color(0xFF94A3B8)), // slate-400
                ),
              ),
            ),

          // Top header
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3310B981),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.black,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Free Lens OCR',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  _HeaderIconButton(
                    tooltip: 'History',
                    icon: Icons.history,
                    badge: _history.isNotEmpty,
                    onTap: _openHistory,
                  ),
                ],
              ),
            ),
          ),

          // Scan overlay (frame + scan line)
          Center(
            child: SizedBox(
              width: viewfinderW,
              height: viewfinderH,
              child: Stack(
                children: [
                  // Semi-transparent glass background
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0x660B1220),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: const Color(0x3310B981),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  // Corner frame painter
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ScanFramePainter(
                        color: const Color(0xFF10B981),
                        radius: 22,
                        stroke: 2.2,
                      ),
                    ),
                  ),

                  // Animated scan line
                  AnimatedBuilder(
                    animation: _scanCtrl,
                    builder: (context, _) {
                      final t = _scanCtrl.value;
                      final top = lerpDouble(14, viewfinderH - 18, t)!;
                      return Positioned(
                        left: 16,
                        right: 16,
                        top: top,
                        child: Container(
                          height: 2,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            gradient: const LinearGradient(
                              colors: [
                                Color(0x0010B981),
                                Color(0xFF10B981),
                                Color(0x0010B981),
                              ],
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x5510B981),
                                blurRadius: 12,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  // Hint text
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x99020617),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0x22334B),
                            width: 1,
                          ),
                        ),
                        child: const Text(
                          'Align text inside frame • Tap shutter to scan',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFCBD5E1),
                          ), // slate-300
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls (upload + shutter)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                child: Row(
                  children: [
                    _RoundAction(
                      icon: Icons.photo_library_outlined,
                      size: 52,
                      onTap: _pickFromGallery,
                    ),
                    const Spacer(),
                    _ShutterButton(disabled: _isExtracting, onTap: _capture),
                    const Spacer(),
                    const SizedBox(
                      width: 52,
                    ), // keep symmetry like the web layout
                  ],
                ),
              ),
            ),
          ),

          // Watermark-like error banner (web shows inline errors)
          if (_error != null)
            Positioned(
              left: 16,
              right: 16,
              top: 86,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B1220),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0x33EF4444),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 13,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => setState(() => _error = null),
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      splashRadius: 18,
                    ),
                  ],
                ),
              ),
            ),

          // Result panel overlay (matches the web bottom overlay)
          if (_currentText != null && _currentImagePath != null)
            _ResultOverlay(
              text: _currentText!,
              imagePath: _currentImagePath!,
              onClose: () => setState(() {
                _currentText = null;
                _currentImagePath = null;
              }),
              onCopy: () async {
                await Clipboard.setData(ClipboardData(text: _currentText!));
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied to clipboard'),
                    duration: Duration(milliseconds: 900),
                  ),
                );
              },
            ),

          // History drawer (right-side slide, like the web)
          _HistoryDrawer(
            open: _historyOpen,
            controller: _historySearch,
            items: _filteredHistory,
            onClose: _closeHistory,
            onPick: (item) {
              setState(() {
                _currentText = item.fullText;
                _currentImagePath = item.imagePath;
                _historyOpen = false;
              });
            },
            onClearAll: () async {
              setState(() {
                _history.clear();
              });
              _stats = OcrStats.empty();
              await _persistLocal();
              if (mounted) setState(() {});
            },
          ),

          // Processing overlay
          if (_isExtracting)
            Positioned.fill(
              child: Container(
                color: const Color(0x99020617),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1220),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: const Color(0x2210B981),
                        width: 1.2,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Extracting text…',
                          style: TextStyle(fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool badge;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0x330F172A), // slate-900/20
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x1E334B), width: 1),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(icon, color: const Color(0xFFE2E8F0), size: 20),
              if (badge)
                Positioned(
                  top: 11,
                  right: 12,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: size / 2,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x330F172A),
          borderRadius: BorderRadius.circular(size / 2),
          border: Border.all(color: const Color(0x22334B), width: 1.2),
        ),
        child: Icon(icon, color: const Color(0xFFE2E8F0), size: 22),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool disabled;
  final VoidCallback onTap;

  const _ShutterButton({required this.disabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: disabled ? null : onTap,
      radius: 44,
      child: Container(
        width: 74,
        height: 74,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: disabled ? const Color(0x3310B981) : const Color(0xFF10B981),
          boxShadow: const [
            BoxShadow(
              color: Color(0x3310B981),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Center(
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF020617),
              border: Border.all(color: const Color(0xFF10B981), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultOverlay extends StatelessWidget {
  final String text;
  final String imagePath;
  final VoidCallback onClose;
  final VoidCallback onCopy;

  const _ResultOverlay({
    required this.text,
    required this.imagePath,
    required this.onClose,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Positioned(
      left: 16,
      right: 16,
      bottom: max(16, mq.padding.bottom + 12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x2210B981), width: 1.2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 8),
              child: Row(
                children: [
                  const Text(
                    'Extracted Text',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    color: const Color(0xFFCBD5E1),
                    splashRadius: 18,
                  ),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close, size: 18),
                    color: const Color(0xFF94A3B8),
                    splashRadius: 18,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0x1E334B)),

            // Body
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 64,
                        height: 64,
                        color: const Color(0xFF020617),
                        child: Image.file(
                          File(imagePath),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              size: 20,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Text(
                          text,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12.5,
                            height: 1.35,
                            color: const Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDrawer extends StatelessWidget {
  final bool open;
  final TextEditingController controller;
  final List<OcrHistoryItem> items;
  final VoidCallback onClose;
  final ValueChanged<OcrHistoryItem> onPick;
  final Future<void> Function() onClearAll;

  const _HistoryDrawer({
    required this.open,
    required this.controller,
    required this.items,
    required this.onClose,
    required this.onPick,
    required this.onClearAll,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final width = min(360.0, mq.size.width * 0.92);
    final df = DateFormat('MMM d, yyyy • HH:mm');

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      top: 0,
      bottom: 0,
      right: open ? 0 : -width - 20,
      width: width,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(0, 10, 10, 10),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0x1E334B), width: 1.2),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
                child: Row(
                  children: [
                    const Text(
                      'History',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () async {
                        await onClearAll();
                      },
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: const Color(0xFF94A3B8),
                      splashRadius: 18,
                      tooltip: 'Clear all',
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, size: 18),
                      color: const Color(0xFF94A3B8),
                      splashRadius: 18,
                      tooltip: 'Close',
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                    filled: true,
                    fillColor: const Color(0xFF020617),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x1E334B)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0x1E334B)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFF10B981),
                        width: 1.2,
                      ),
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                  onChanged: (_) => (context as Element).markNeedsBuild(),
                ),
              ),
              const Divider(height: 1, color: Color(0x1E334B)),
              Expanded(
                child: items.isEmpty
                    ? const Center(
                        child: Text(
                          'No scans yet',
                          style: TextStyle(color: Color(0xFF94A3B8)),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        itemBuilder: (context, i) {
                          final it = items[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onPick(it),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF020617),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0x1E334B),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      color: const Color(0xFF0B1220),
                                      child: Image.file(
                                        File(it.imagePath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const Center(
                                              child: Icon(
                                                Icons.image_outlined,
                                                size: 18,
                                                color: Color(0xFF94A3B8),
                                              ),
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          it.preview,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            height: 1.25,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          df.format(
                                            DateTime.fromMillisecondsSinceEpoch(
                                              it.timestampMs,
                                            ),
                                          ),
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemCount: items.length,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanFramePainter extends CustomPainter {
  final Color color;
  final double radius;
  final double stroke;

  _ScanFramePainter({
    required this.color,
    required this.radius,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color.withOpacity(0.95);

    final r = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );

    // Draw subtle outer border
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color.withOpacity(0.18);
    canvas.drawRRect(r, outer);

    // Draw corner “L” shapes like the web scan-frame
    const cornerLen = 26.0;

    // TL
    canvas.drawLine(const Offset(14, 14), const Offset(14 + cornerLen, 14), p);
    canvas.drawLine(const Offset(14, 14), const Offset(14, 14 + cornerLen), p);

    // TR
    canvas.drawLine(
      Offset(size.width - 14, 14),
      Offset(size.width - 14 - cornerLen, 14),
      p,
    );
    canvas.drawLine(
      Offset(size.width - 14, 14),
      Offset(size.width - 14, 14 + cornerLen),
      p,
    );

    // BL
    canvas.drawLine(
      Offset(14, size.height - 14),
      Offset(14 + cornerLen, size.height - 14),
      p,
    );
    canvas.drawLine(
      Offset(14, size.height - 14),
      Offset(14, size.height - 14 - cornerLen),
      p,
    );

    // BR
    canvas.drawLine(
      Offset(size.width - 14, size.height - 14),
      Offset(size.width - 14 - cornerLen, size.height - 14),
      p,
    );
    canvas.drawLine(
      Offset(size.width - 14, size.height - 14),
      Offset(size.width - 14, size.height - 14 - cornerLen),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanFramePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.stroke != stroke;
  }
}

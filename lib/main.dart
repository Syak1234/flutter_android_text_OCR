import 'dart:async';

import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'ocr_controller.dart';
import 'ocr_models.dart';

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

class OcrHomePage extends StatelessWidget {
  const OcrHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(OcrController());
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;

    // Match the web sizing idea: w=min(90vw, 520px), aspect 3/4
    final viewfinderW = min(w * 0.90, 520.0);
    final viewfinderH = min(viewfinderW * (4 / 3), h * 0.62);

    return Scaffold(
      body: Obx(
        () => Stack(
          children: [
            // Background base + subtle radial “glow” like the Tailwind app
            Container(
              decoration: const BoxDecoration(color: Color(0xFF020617)),
            ),
            Positioned(
              top: -220,
              left: -180,
              child: Container(
                width: 520,
                height: 520,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [Color(0x3310B981), Color(0x00020617)],
                  ),
                ),
              ),
            ),

            // Camera preview (behind everything)
            if (controller.cameraReady.value && controller.camera.value != null)
              Positioned.fill(
                child: IgnorePointer(
                  // Equivalent to pointer-events:none on iframe/video
                  ignoring: true,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width:
                          controller.camera.value!.value.previewSize?.height ??
                          w,
                      height:
                          controller.camera.value!.value.previewSize?.width ??
                          h,
                      child: CameraPreview(controller.camera.value!),
                    ),
                  ),
                ),
              )
            else
              Positioned.fill(
                child: Center(
                  child: Text(
                    controller.error.value ?? 'Camera loading…',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                    ), // slate-400
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
                      badge: controller.history.isNotEmpty,
                      onTap: controller.openHistory,
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
                      animation: controller.scanCtrl,
                      builder: (context, _) {
                        final t = controller.scanCtrl.value;
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
                        onTap: controller.pickFromGallery,
                      ),
                      const Spacer(),
                      _ShutterButton(
                        disabled: controller.isExtracting.value,
                        onTap: controller.capture,
                      ),
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
            if (controller.error.value != null)
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
                          controller.error.value!,
                          style: const TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: controller.clearError,
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
            if (controller.currentText.value != null &&
                controller.currentImagePath.value != null)
              _ResultOverlay(
                text: controller.currentText.value!,
                imagePath: controller.currentImagePath.value!,
                onClose: controller.closeResult,
                onCopy: () async {
                  await Clipboard.setData(
                    ClipboardData(text: controller.currentText.value!),
                  );
                  if (!context.mounted) return;
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
              open: controller.historyOpen.value,
              controller: controller.historySearch,
              items: controller.filteredHistory,
              onClose: controller.closeHistory,
              onPick: controller.selectHistoryItem,
              onClearAll: controller.clearAllHistory,
            ),

            // Processing overlay
            if (controller.isExtracting.value)
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
                    : GetBuilder<OcrController>(
                        id: 'history_list',
                        builder: (controller) {
                          final filtered = controller.filteredHistory;
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                            itemBuilder: (context, i) {
                              final it = filtered[i];
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemCount: filtered.length,
                          );
                        },
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

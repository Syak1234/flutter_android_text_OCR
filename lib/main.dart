import 'dart:async';

import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_text_ocr/layout/ocrhomepage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'ocr_controller.dart';
import 'ocr_models.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class ResultOverlay extends StatelessWidget {
  final String text;
  final String imagePath;
  final VoidCallback onClose;
  final VoidCallback onCopy;

  const ResultOverlay({
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

class HistoryDrawer extends StatelessWidget {
  final bool open;
  final TextEditingController controller;
  final List<OcrHistoryItem> items;
  final VoidCallback onClose;
  final ValueChanged<OcrHistoryItem> onPick;
  final Future<void> Function() onClearAll;

  const HistoryDrawer({
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

class ScanFramePainter extends CustomPainter {
  final Color color;
  final double radius;
  final double stroke;

  ScanFramePainter({
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
  bool shouldRepaint(covariant ScanFramePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.radius != radius ||
        oldDelegate.stroke != stroke;
  }
}

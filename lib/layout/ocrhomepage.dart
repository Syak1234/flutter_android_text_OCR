import 'dart:math';
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_text_ocr/main.dart';
import 'package:flutter_text_ocr/widget/buttonwidget.dart';
import 'package:get/get.dart';

import '../ocr_controller.dart';

class OcrHomePage extends StatelessWidget {
  const OcrHomePage({super.key});
  @Preview(name: "OcrHomePage")
  static Widget preview() {
    return const OcrHomePage();
  }

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
                        // color: const Color(0xFF10B981),
                        borderRadius: BorderRadius.circular(12),
                        // boxShadow: const [
                        //   BoxShadow(
                        //     color: Color(0x3310B981),
                        //     blurRadius: 18,
                        //     offset: Offset(0, 8),
                        //   ),
                        // ],
                      ),
                      child: Image.asset("assets/logo.png"),
                      // child: const Icon(
                      //   Icons.auto_awesome,
                      //   color: Colors.black,
                      //   size: 20,
                      // ),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text(
                        'Text R Copy',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                    HeaderIconButton(
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
                        painter: ScanFramePainter(
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
                      RoundAction(
                        icon: Icons.photo_library_outlined,
                        size: 52,
                        onTap: controller.pickFromGallery,
                      ),
                      const Spacer(),
                      ShutterButton(
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
              ResultOverlay(
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
            HistoryDrawer(
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

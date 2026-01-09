import 'package:flutter/material.dart';

class RoundAction extends StatelessWidget {
  final IconData icon;
  final double size;
  final VoidCallback onTap;

  const RoundAction({
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

class ShutterButton extends StatelessWidget {
  final bool disabled;
  final VoidCallback onTap;

  const ShutterButton({required this.disabled, required this.onTap});

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

class HeaderIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final bool badge;
  final VoidCallback onTap;

  const HeaderIconButton({
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

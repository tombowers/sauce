import 'package:flutter/material.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.elevation = SurfaceCardElevation.standard,
    this.backgroundColor = Colors.white,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final SurfaceCardElevation elevation;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    final shadows = elevation == SurfaceCardElevation.standard
        ? const [
            BoxShadow(
              color: Color(0x0E0F172A),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x120F172A),
              blurRadius: 18,
              offset: Offset(0, 10),
              spreadRadius: -12,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x140F172A),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x180F172A),
              blurRadius: 24,
              offset: Offset(0, 14),
              spreadRadius: -12,
            ),
          ];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: backgroundColor,
        border: Border.all(color: const Color(0xFFE8EDF3)),
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

enum SurfaceCardElevation { standard, raised }

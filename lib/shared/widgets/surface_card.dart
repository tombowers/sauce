import 'package:flutter/material.dart';

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.elevation = SurfaceCardElevation.standard,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final SurfaceCardElevation elevation;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(18);
    final shadows = elevation == SurfaceCardElevation.standard
        ? const [
            BoxShadow(
              color: Color(0x10000000),
              blurRadius: 3,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 18,
              offset: Offset(0, 8),
              spreadRadius: -10,
            ),
          ]
        : const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 24,
              offset: Offset(0, 12),
              spreadRadius: -10,
            ),
          ];
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: Colors.white,
        boxShadow: shadows,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

enum SurfaceCardElevation { standard, raised }

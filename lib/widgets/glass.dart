import 'dart:ui';
import 'package:flutter/material.dart';

Color _w(double o) => Color.fromRGBO(255, 255, 255, o);

class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: dark ? [_w(.15), _w(.05)] : [_w(.78), _w(.34)],
            ),
            border: Border.all(color: dark ? _w(.18) : _w(.85)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});
  final Widget child;

  Widget _orb(Alignment a, double size, Color c) {
    return Align(
      alignment: a,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withAlpha(0)]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: dark ? const Color(0xFF0B0B0C) : const Color(0xFFE7E7EB),
      child: Stack(
        children: [
          _orb(const Alignment(-1, -.85), 420,
              dark ? _w(.30) : const Color.fromRGBO(110, 110, 120, .32)),
          _orb(const Alignment(1.1, .1), 420,
              dark ? const Color.fromRGBO(150, 150, 160, .32) : _w(.95)),
          _orb(const Alignment(-.6, 1), 420,
              dark ? _w(.20) : const Color.fromRGBO(90, 90, 100, .26)),
          child,
        ],
      ),
    );
  }
}

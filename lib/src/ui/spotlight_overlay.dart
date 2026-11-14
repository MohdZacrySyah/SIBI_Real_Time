import 'dart:ui';
import 'package:flutter/material.dart';

class SpotlightOverlay extends StatefulWidget {
  final Rect? targetRect;
  final bool isDark;

  const SpotlightOverlay({
    super.key,
    this.targetRect,
    required this.isDark,
  });

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Rect? _currentRect;
  Rect? _previousRect;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _currentRect = widget.targetRect;
    _previousRect = widget.targetRect;
    if (widget.targetRect != null) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(SpotlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetRect != widget.targetRect) {
      _previousRect = _currentRect ?? widget.targetRect;
      _currentRect = widget.targetRect;
      
      // If hiding
      if (widget.targetRect == null) {
         _controller.reverse();
      } else {
         _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentRect == null && _previousRect == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final curve = Curves.easeInOutCubic.transform(_controller.value);
        Rect rectToDraw = Rect.zero;
        
        if (_previousRect != null && _currentRect != null) {
          rectToDraw = Rect.lerp(_previousRect, _currentRect, curve)!;
        } else if (_currentRect != null) {
          rectToDraw = _currentRect!;
        } else if (_previousRect != null) {
          rectToDraw = _previousRect!;
        }

        // Expand the rect slightly so the button has breathing room
        if (rectToDraw != Rect.zero) {
            rectToDraw = rectToDraw.inflate(12.0); // More breathing room
        }

        double currentOpacity = 1.0;
        if (_previousRect == null && _currentRect != null) {
          currentOpacity = _controller.value;
        } else if (_currentRect == null && _previousRect != null) {
          currentOpacity = _controller.value;
        } else {
          currentOpacity = 1.0;
        }

        return IgnorePointer(
          ignoring: true, // Allow touches to pass through to the buttons
          child: CustomPaint(
            size: Size.infinite,
            painter: _SpotlightPainter(
              targetRect: rectToDraw,
              isDark: widget.isDark,
              opacity: currentOpacity,
            ),
          ),
        );
      },
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final bool isDark;
  final double opacity;

  _SpotlightPainter({
    required this.targetRect,
    required this.isDark,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;

    final backgroundPaint = Paint()
      ..color = Colors.black.withOpacity(0.75 * opacity)
      ..style = PaintingStyle.fill;
    
    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    
    if (targetRect == Rect.zero) {
        canvas.drawPath(bgPath, backgroundPaint);
        return;
    }

    final targetPath = Path()..addRRect(RRect.fromRectAndRadius(targetRect, const Radius.circular(28.0)));
    
    final finalPath = Path.combine(PathOperation.difference, bgPath, targetPath);
    
    canvas.drawPath(finalPath, backgroundPaint);
    
    // Add a glowing border around the cutout
    final borderPaint = Paint()
      ..color = (isDark ? Colors.cyanAccent : Colors.greenAccent).withOpacity(0.6 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 12);
      
    canvas.drawPath(targetPath, borderPaint);
    
    // Solid thin border
    final solidBorderPaint = Paint()
      ..color = (isDark ? Colors.cyanAccent : Colors.greenAccent).withOpacity(0.9 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
      
    canvas.drawPath(targetPath, solidBorderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect || 
           oldDelegate.isDark != isDark ||
           oldDelegate.opacity != opacity;
  }
}

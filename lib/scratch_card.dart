import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A custom scratch card widget that reveals its [child] when the user
/// scratches the overlay surface.
class ScratchCard extends StatefulWidget {
  /// The content revealed underneath the scratch surface.
  final Widget child;

  /// An optional overlay image to use as the scratch surface texture.
  final Image? image;

  /// Fallback overlay color when [image] is not provided.
  final Color color;

  /// Radius of the scratch brush.
  final double brushSize;

  /// Percentage (0-100) of the surface that must be scratched to trigger
  /// [onThreshold].
  final double threshold;

  /// Called when the scratched area exceeds [threshold].
  final VoidCallback? onThreshold;

  /// Called every time the scratch percentage changes.
  final ValueChanged<double>? onChange;

  /// Whether scratching is enabled.
  final bool enabled;

  /// Color for the top half of the gift card design.
  final Color? topColor;

  /// Color for the bottom half of the gift card design.
  final Color? bottomColor;

  /// Color for the ribbon in the gift card design.
  final Color? ribbonColor;

  /// Color for the bow in the gift card design.
  final Color? bowColor;

  const ScratchCard({
    super.key,
    required this.child,
    this.image,
    this.color = Colors.grey,
    this.brushSize = 30,
    this.threshold = 20,
    this.onThreshold,
    this.onChange,
    this.enabled = true,
    this.topColor,
    this.bottomColor,
    this.ribbonColor,
    this.bowColor,
  });

  @override
  ScratchCardState createState() => ScratchCardState();
}

class ScratchCardState extends State<ScratchCard>
    with SingleTickerProviderStateMixin {
  final List<List<Offset>> _scratchPaths = [];
  List<Offset> _currentPath = [];
  bool _thresholdReached = false;
  bool _isRevealed = false;
  double _revealProgress = 0;

  AnimationController? _revealController;
  ui.Image? _resolvedImage;
  Size _widgetSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant ScratchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _resolveImage();
    }
  }

  void _resolveImage() {
    if (widget.image == null) return;

    final ImageProvider provider = widget.image!.image;
    final ImageStream stream = provider.resolve(const ImageConfiguration());
    stream.addListener(ImageStreamListener((ImageInfo info, bool sync) {
      if (mounted) {
        setState(() {
          _resolvedImage = info.image;
        });
      }
    }));
  }

  /// Programmatically reveal the entire scratch card with an animation.
  void reveal({Duration duration = const Duration(milliseconds: 600)}) {
    _revealController?.dispose();
    _revealController = AnimationController(
      vsync: this,
      duration: duration,
    );
    _revealController!.addListener(() {
      if (mounted) {
        setState(() {
          _revealProgress = _revealController!.value;
        });
      }
    });
    _revealController!.forward();
    setState(() {
      _isRevealed = true;
    });
  }

  /// Reset the scratch card to its initial unscratched state.
  void reset() {
    _revealController?.dispose();
    _revealController = null;
    setState(() {
      _scratchPaths.clear();
      _currentPath = [];
      _thresholdReached = false;
      _isRevealed = false;
      _revealProgress = 0;
    });
  }

  @override
  void dispose() {
    _revealController?.dispose();
    super.dispose();
  }

  void _addPoint(Offset globalPosition) {
    if (!widget.enabled || _isRevealed) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Offset localPosition = box.globalToLocal(globalPosition);

    // Clamp to widget bounds
    final clampedOffset = Offset(
      localPosition.dx.clamp(0, box.size.width),
      localPosition.dy.clamp(0, box.size.height),
    );

    setState(() {
      _currentPath.add(clampedOffset);
    });
    _widgetSize = box.size;
    _calculateScratchPercentage();
  }

  void _startNewPath(Offset globalPosition) {
    if (!widget.enabled || _isRevealed) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Offset localPosition = box.globalToLocal(globalPosition);

    _currentPath = [localPosition];
    _scratchPaths.add(_currentPath);
    _widgetSize = box.size;
  }

  void _calculateScratchPercentage() {
    if (_widgetSize == Size.zero) return;

    const int gridSize = 50;
    final double cellW = _widgetSize.width / gridSize;
    final double cellH = _widgetSize.height / gridSize;
    final Set<int> scratchedCells = {};
    final double halfBrush = widget.brushSize / 2;

    for (final path in _scratchPaths) {
      for (final point in path) {
        final int col = (point.dx / cellW).clamp(0, gridSize - 1).floor();
        final int row = (point.dy / cellH).clamp(0, gridSize - 1).floor();

        // Mark cells within brush radius
        final int brushCellsW = (halfBrush / cellW).ceil();
        final int brushCellsH = (halfBrush / cellH).ceil();
        for (int dr = -brushCellsH; dr <= brushCellsH; dr++) {
          for (int dc = -brushCellsW; dc <= brushCellsW; dc++) {
            final int nr = row + dr;
            final int nc = col + dc;
            if (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
              scratchedCells.add(nr * gridSize + nc);
            }
          }
        }
      }
    }

    final double percentage =
        (scratchedCells.length / (gridSize * gridSize)) * 100;
    widget.onChange?.call(percentage);

    if (!_thresholdReached && percentage >= widget.threshold) {
      _thresholdReached = true;
      widget.onThreshold?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The reward content underneath
        widget.child,

        // The scratch overlay — uses Listener to avoid gesture arena conflicts
        if (!_isRevealed || _revealProgress < 1.0)
          Opacity(
            opacity: _isRevealed ? (1.0 - _revealProgress) : 1.0,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) => _startNewPath(event.position),
              onPointerMove: (event) => _addPoint(event.position),
              child: RepaintBoundary(
                child: CustomPaint(
                  size: Size.infinite,
                  painter: _ScratchPainter(
                    paths: _scratchPaths,
                    brushSize: widget.brushSize,
                    overlayColor: widget.color,
                    overlayImage: _resolvedImage,
                    topColor: widget.topColor,
                    bottomColor: widget.bottomColor,
                    ribbonColor: widget.ribbonColor,
                    bowColor: widget.bowColor,
                  ),
                  isComplex: true,
                  willChange: true,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScratchPainter extends CustomPainter {
  final List<List<Offset>> paths;
  final double brushSize;
  final Color overlayColor;
  final ui.Image? overlayImage;

  // Custom Colors
  final Color? topColor;
  final Color? bottomColor;
  final Color? ribbonColor;
  final Color? bowColor;

  _ScratchPainter({
    required this.paths,
    required this.brushSize,
    required this.overlayColor,
    this.overlayImage,
    this.topColor,
    this.bottomColor,
    this.ribbonColor,
    this.bowColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.saveLayer(Offset.zero & size, Paint());

    if (overlayImage != null) {
      final src = Rect.fromLTWH(
        0,
        0,
        overlayImage!.width.toDouble(),
        overlayImage!.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(overlayImage!, src, dst, Paint());
    } else {
      _drawGiftCard(canvas, size);
    }

    final erasePaint = Paint()
      ..blendMode = BlendMode.clear
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = brushSize;

    final eraseDotPaint = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.fill;

    for (final path in paths) {
      if (path.isEmpty) continue;
      if (path.length == 1) {
        canvas.drawCircle(path.first, brushSize / 2, eraseDotPaint);
      } else {
        final uiPath = ui.Path();
        uiPath.moveTo(path.first.dx, path.first.dy);
        for (int i = 1; i < path.length; i++) {
          if (i + 1 < path.length) {
            final midX = (path[i].dx + path[i + 1].dx) / 2;
            final midY = (path[i].dy + path[i + 1].dy) / 2;
            uiPath.quadraticBezierTo(path[i].dx, path[i].dy, midX, midY);
          } else {
            uiPath.lineTo(path[i].dx, path[i].dy);
          }
        }
        canvas.drawPath(uiPath, erasePaint);
      }
    }

    canvas.restore();
  }

  void _drawGiftCard(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final cx = size.width / 2;
    final cy = size.height / 2;

    // ── 1. Background ──
    final topRect = Rect.fromLTWH(0, 0, size.width, cy);
    final topPaint = Paint()..color = topColor ?? const Color(0xFF006D77);
    canvas.drawRect(topRect, topPaint);

    final bottomRect = Rect.fromLTWH(0, cy, size.width, cy);
    final bottomPaint = Paint()..color = bottomColor ?? const Color(0xFFF7F7F7);
    canvas.drawRect(bottomRect, bottomPaint);

    // ── 2. Decorative Patterns ──
    _drawTopStripePattern(canvas, topRect);

    final bokehPaint = Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    _drawBokeh(canvas, topRect, bokehPaint);

    _drawStarPattern(canvas, rect);

    // ── 3. Ribbon Lighting & Shadow ──
    final ribbonH = size.height * 0.12;
    final ribbonY = cy - ribbonH / 2;
    
    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawRect(Rect.fromLTWH(0, ribbonY + 2, size.width, ribbonH + 8), shadowPaint);

    // ── 4. Ribbon ──
    final borderCol = ribbonColor?.withOpacity(0.8) ?? const Color(0xFFAFB3B7);
    final borderPaint = Paint()..color = borderCol..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, ribbonY), Offset(size.width, ribbonY), borderPaint);
    canvas.drawLine(Offset(0, ribbonY + ribbonH), Offset(size.width, ribbonY + ribbonH), borderPaint);

    final ribbonBaseColor = ribbonColor ?? const Color(0xFFBFC3C7);
    final ribbonLighter = Color.lerp(ribbonBaseColor, Colors.white, 0.2)!;

    final ribbonPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          ribbonBaseColor,
          ribbonLighter,
          ribbonBaseColor,
        ],
      ).createShader(Rect.fromLTWH(0, ribbonY, size.width, ribbonH));
    canvas.drawRect(Rect.fromLTWH(0, ribbonY, size.width, ribbonH), ribbonPaint);

    // ── 5. Bow Glow & Realistic Bow ──
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [Colors.white.withOpacity(0.4), Colors.white.withOpacity(0.0)],
      ).createShader(Rect.fromCenter(center: Offset(cx, cy), width: 150, height: 150));
    canvas.drawCircle(Offset(cx, cy), 75, glowPaint);

    _drawRealisticBow(canvas, Offset(cx, cy), size.width * 0.45);

    // ── 6. Sparkle Stars ──
    _drawStar(canvas, Offset(size.width * 0.2, size.height * 0.25), 12, Colors.white.withOpacity(0.6));
    _drawStar(canvas, Offset(size.width * 0.8, size.height * 0.15), 10, Colors.white.withOpacity(0.5));
    _drawStar(canvas, Offset(size.width * 0.1, size.height * 0.85), 8, (topColor ?? const Color(0xFF006D77)).withOpacity(0.2));
    _drawStar(canvas, Offset(size.width * 0.9, size.height * 0.75), 9, (topColor ?? const Color(0xFF006D77)).withOpacity(0.1));
  }

  void _drawTopStripePattern(Canvas canvas, Rect area) {
    final stripePaint = Paint()
      ..color = Colors.white.withOpacity(0.04)
      ..strokeWidth = 2.0;

    const spacing = 15.0;
    for (double i = 0; i < area.width + area.height; i += spacing) {
      canvas.drawLine(
        Offset(i, area.top),
        Offset(i - area.height, area.bottom),
        stripePaint,
      );
    }
  }

  void _drawBokeh(Canvas canvas, Rect area, Paint paint) {
    final circles = [
      Offset(area.width * 0.15, area.height * 0.35),
      Offset(area.width * 0.55, area.height * 0.45),
      Offset(area.width * 0.85, area.height * 0.25),
      Offset(area.width * 0.65, area.height * 0.65),
    ];
    for (var i = 0; i < circles.length; i++) {
        canvas.drawCircle(circles[i], 20.0 + (i % 3) * 10.0, paint);
    }
  }

  void _drawStarPattern(Canvas canvas, Rect area) {
    const step = 30.0;
    for (var y = area.top + 10; y < area.bottom; y += step) {
      final starPaint = Paint()
          ..color = (y < area.height / 2) 
            ? Colors.white.withOpacity(0.04) 
            : (topColor ?? const Color(0xFF006D77)).withOpacity(0.02);
      for (var x = 15.0; x < area.width; x += step) {
        final xOffset = ((y / step).floor() % 2 == 0) ? 0.0 : step / 2;
        _drawTinyStar(canvas, Offset(x + xOffset, y), 2.2, starPaint);
      }
    }
  }

  void _drawTinyStar(Canvas canvas, Offset center, double radius, Paint paint) {
    final path = ui.Path();
    for (var i = 0; i < 5; i++) {
      final angle = (i * 72.0 - 18.0) * (pi / 180.0);
      final p = Offset(center.dx + radius * 2 * cos(angle), center.dy + radius * 2 * sin(angle));
      if (i == 0) path.moveTo(p.dx, p.dy); else path.lineTo(p.dx, p.dy);
      
      final innerAngle = (i * 72.0 + 18.0) * (pi / 180.0);
      final innerP = Offset(center.dx + radius * cos(innerAngle), center.dy + radius * sin(innerAngle));
      path.lineTo(innerP.dx, innerP.dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _drawRealisticBow(Canvas canvas, Offset center, double width) {
    final cx = center.dx;
    final cy = center.dy;
    final loopW = width * 0.45;
    final loopH = width * 0.35;

    final shadowPaint = Paint()..color = Colors.black.withOpacity(0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    
    final leftPath = ui.Path()
      ..moveTo(cx, cy)
      ..cubicTo(cx - loopW * 0.5, cy - loopH * 1.2, cx - loopW * 1.2, cy - loopH * 0.2, cx - loopW, cy + loopH * 0.2)
      ..cubicTo(cx - loopW * 0.8, cy + loopH * 1.0, cx - loopW * 0.2, cy + loopH * 0.5, cx, cy)
      ..close();
    canvas.drawPath(leftPath, shadowPaint);

    final rightPath = ui.Path()
      ..moveTo(cx, cy)
      ..cubicTo(cx + loopW * 0.5, cy - loopH * 1.2, cx + loopW * 1.2, cy - loopH * 0.2, cx + loopW, cy + loopH * 0.2)
      ..cubicTo(cx + loopW * 0.8, cy + loopH * 1.0, cx + loopW * 0.2, cy + loopH * 0.5, cx, cy)
      ..close();
    canvas.drawPath(rightPath, shadowPaint);

    final baseBowColor = bowColor ?? const Color(0xFFBFC3C7);
    final bowLighter = Color.lerp(baseBowColor, Colors.white, 0.4)!;
    final bowDarker = Color.lerp(baseBowColor, Colors.black, 0.2)!;

    final bowPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.3),
        colors: [bowLighter, baseBowColor, bowDarker],
      ).createShader(Rect.fromCenter(center: center, width: width, height: loopH * 2));

    canvas.drawPath(leftPath, bowPaint);
    canvas.drawPath(rightPath, bowPaint);

    final highlightPaint = Paint()..color = Colors.white.withOpacity(0.25)..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawPath(leftPath, highlightPaint);
    canvas.drawPath(rightPath, highlightPaint);

    final tailPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [baseBowColor, bowDarker],
      ).createShader(Rect.fromLTWH(cx - loopW, cy, loopW * 2, loopH * 1.5));

    final leftTail = ui.Path()
      ..moveTo(cx - 10, cy + 10)
      ..lineTo(cx - loopW * 0.7, cy + loopH * 1.3)
      ..lineTo(cx - loopW * 0.4, cy + loopH * 1.0)
      ..lineTo(cx - loopW * 0.3, cy + loopH * 1.4)
      ..lineTo(cx - 5, cy + 15)
      ..close();
    canvas.drawPath(leftTail, tailPaint);

    final rightTail = ui.Path()
      ..moveTo(cx + 10, cy + 10)
      ..lineTo(cx + loopW * 0.7, cy + loopH * 1.3)
      ..lineTo(cx + loopW * 0.4, cy + loopH * 1.0)
      ..lineTo(cx + loopW * 0.3, cy + loopH * 1.4)
      ..lineTo(cx + 5, cy + 15)
      ..close();
    canvas.drawPath(rightTail, tailPaint);

    final knotRect = Rect.fromCenter(center: center, width: 30, height: 24);
    final knotPaint = Paint()
      ..shader = RadialGradient(
        colors: [bowLighter, baseBowColor],
      ).createShader(knotRect);
    canvas.drawRRect(RRect.fromRectAndRadius(knotRect, const Radius.circular(6)), knotPaint);
  }

  void _drawStar(Canvas canvas, Offset center, double radius, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final path = ui.Path()
      ..moveTo(center.dx, center.dy - radius)
      ..lineTo(center.dx + radius * 0.25, center.dy - radius * 0.25)
      ..lineTo(center.dx + radius, center.dy)
      ..lineTo(center.dx + radius * 0.25, center.dy + radius * 0.25)
      ..lineTo(center.dx, center.dy + radius)
      ..lineTo(center.dx - radius * 0.25, center.dy + radius * 0.25)
      ..lineTo(center.dx - radius, center.dy)
      ..lineTo(center.dx - radius * 0.25, center.dy - radius * 0.25)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScratchPainter oldDelegate) => true;
}

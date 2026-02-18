import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class DrawingCanvas extends StatefulWidget {
  final GlobalKey repaintKey;

  const DrawingCanvas({super.key, required this.repaintKey});

  @override
  State<DrawingCanvas> createState() => DrawingCanvasState();
}

class DrawingCanvasState extends State<DrawingCanvas> {
  final List<_DrawingStroke> _strokes = [];
  List<Offset> _currentPoints = [];
  double _strokeWidth = 2.0;

  bool get hasContent => _strokes.isNotEmpty;

  void clear() {
    setState(() {
      _strokes.clear();
      _currentPoints = [];
    });
  }

  Future<Uint8List?> captureImage() async {
    try {
      final boundary = widget.repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final penColor = isDark ? Colors.white : Colors.black;
    final canvasBg = isDark ? const Color(0xFF1E1E2E) : Colors.white;

    return Column(
      children: [
        // 툴바
        Row(
          children: [
            // 펜 굵기
            _ToolButton(
              icon: Icons.edit,
              label: '가는 펜',
              selected: _strokeWidth == 2.0,
              onTap: () => setState(() => _strokeWidth = 2.0),
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.brush,
              label: '굵은 펜',
              selected: _strokeWidth == 5.0,
              onTap: () => setState(() => _strokeWidth = 5.0),
            ),
            const Spacer(),
            // 지우기
            TextButton.icon(
              onPressed: _strokes.isEmpty ? null : clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('지우기'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 캔버스
        RepaintBoundary(
          key: widget.repaintKey,
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: canvasBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: GestureDetector(
                onPanStart: (details) {
                  _currentPoints = [details.localPosition];
                },
                onPanUpdate: (details) {
                  setState(() {
                    _currentPoints = List.from(_currentPoints)
                      ..add(details.localPosition);
                  });
                },
                onPanEnd: (_) {
                  setState(() {
                    _strokes.add(_DrawingStroke(
                      points: List.from(_currentPoints),
                      color: penColor,
                      width: _strokeWidth,
                    ));
                    _currentPoints = [];
                  });
                },
                child: CustomPaint(
                  painter: _CanvasPainter(
                    strokes: _strokes,
                    currentPoints: _currentPoints,
                    currentColor: penColor,
                    currentWidth: _strokeWidth,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawingStroke {
  final List<Offset> points;
  final Color color;
  final double width;

  _DrawingStroke({
    required this.points,
    required this.color,
    required this.width,
  });
}

class _CanvasPainter extends CustomPainter {
  final List<_DrawingStroke> strokes;
  final List<Offset> currentPoints;
  final Color currentColor;
  final double currentWidth;

  _CanvasPainter({
    required this.strokes,
    required this.currentPoints,
    required this.currentColor,
    required this.currentWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 완성된 스트로크
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke.points, stroke.color, stroke.width);
    }
    // 현재 진행 중인 스트로크
    if (currentPoints.isNotEmpty) {
      _drawStroke(canvas, currentPoints, currentColor, currentWidth);
    }
  }

  void _drawStroke(
      Canvas canvas, List<Offset> points, Color color, double width) {
    if (points.length < 2) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points.first.dx, points.first.dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}

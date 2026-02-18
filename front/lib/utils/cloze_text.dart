import 'package:flutter/material.dart';

class ClozeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  const ClozeText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final blankPattern = RegExp(r'_{3,}');
    final matches = blankPattern.allMatches(text);

    if (matches.isEmpty) {
      return Text(text, style: style, textAlign: textAlign);
    }

    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in matches) {
      // 빈칸 전 텍스트
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: style,
        ));
      }

      // 빈칸 하이라이트
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: cs.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            '       ',
            style: style?.copyWith(
              color: Colors.transparent,
            ) ??
                const TextStyle(color: Colors.transparent),
          ),
        ),
      ));

      lastEnd = match.end;
    }

    // 빈칸 후 텍스트
    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: style,
      ));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: textAlign,
    );
  }
}

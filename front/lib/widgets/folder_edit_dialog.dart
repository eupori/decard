import 'package:flutter/material.dart';

const _presetColors = [
  '#C2E7DA',
  '#6290C3',
  '#9B72CF',
  '#F59E0B',
  '#EF4444',
  '#94A3B8',
];

Color _parseColor(String hex) {
  final h = hex.replaceFirst('#', '');
  return Color(int.parse('FF$h', radix: 16));
}

/// 폴더 생성/수정 공통 다이얼로그
/// 반환: {'name': String, 'color': String} 또는 null (취소)
Future<Map<String, String>?> showFolderEditDialog(
  BuildContext context, {
  String? initialName,
  String? initialColor,
  String title = '새 과목 만들기',
  String confirmLabel = '만들기',
}) async {
  final nameController = TextEditingController(text: initialName ?? '');
  String selectedColor = initialColor ?? _presetColors[0];

  return showDialog<Map<String, String>>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          final cs = Theme.of(ctx).colorScheme;
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '과목명',
                    hintText: '예: 경영학원론',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '색상',
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: _presetColors.map((c) {
                    final isSelected = c == selectedColor;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedColor = c),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _parseColor(c),
                            shape: BoxShape.circle,
                            border: isSelected
                                ? Border.all(
                                    color: cs.onSurface, width: 2.5)
                                : null,
                          ),
                          child: isSelected
                              ? Icon(Icons.check,
                                  size: 16, color: cs.onSurface)
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameController.text.trim().isEmpty) return;
                  Navigator.pop(ctx, {
                    'name': nameController.text.trim(),
                    'color': selectedColor,
                  });
                },
                style: FilledButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                ),
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

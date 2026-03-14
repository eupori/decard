class FolderModel {
  final String id;
  final String name;
  final String color;
  final String? examDate;
  final int sessionCount;
  final int cardCount;
  final String createdAt;
  final String updatedAt;

  FolderModel({
    required this.id,
    required this.name,
    required this.color,
    this.examDate,
    required this.sessionCount,
    required this.cardCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FolderModel.fromJson(Map<String, dynamic> json) {
    return FolderModel(
      id: json['id'] as String,
      name: json['name'] as String,
      color: json['color'] as String? ?? '#C2E7DA',
      examDate: json['exam_date'] as String?,
      sessionCount: json['session_count'] as int? ?? 0,
      cardCount: json['card_count'] as int? ?? 0,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  /// D-day 계산 (음수=지남, 0=오늘, 양수=남음)
  int? get dDay {
    if (examDate == null) return null;
    final exam = DateTime.tryParse(examDate!);
    if (exam == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return exam.difference(today).inDays;
  }

  String? get dDayText {
    final d = dDay;
    if (d == null) return null;
    if (d == 0) return 'D-Day';
    if (d > 0) return 'D-$d';
    return 'D+${-d}';
  }
}

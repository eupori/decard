class FolderModel {
  final String id;
  final String name;
  final String color;
  final int sessionCount;
  final int cardCount;
  final String createdAt;
  final String updatedAt;

  FolderModel({
    required this.id,
    required this.name,
    required this.color,
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
      sessionCount: json['session_count'] as int? ?? 0,
      cardCount: json['card_count'] as int? ?? 0,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}

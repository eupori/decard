import 'card_model.dart';

class SessionStats {
  final int total;
  final int accepted;
  final int rejected;
  final int pending;

  SessionStats({
    required this.total,
    required this.accepted,
    required this.rejected,
    required this.pending,
  });

  factory SessionStats.fromJson(Map<String, dynamic> json) {
    return SessionStats(
      total: json['total'] as int? ?? 0,
      accepted: json['accepted'] as int? ?? 0,
      rejected: json['rejected'] as int? ?? 0,
      pending: json['pending'] as int? ?? 0,
    );
  }
}

class SessionModel {
  final String id;
  final String filename;
  final int pageCount;
  final String templateType;
  final String status;
  final String? folderId;
  final String? displayName;
  final String createdAt;
  final List<CardModel> cards;
  final SessionStats stats;

  SessionModel({
    required this.id,
    required this.filename,
    required this.pageCount,
    required this.templateType,
    required this.status,
    this.folderId,
    this.displayName,
    required this.createdAt,
    required this.cards,
    required this.stats,
  });

  factory SessionModel.fromJson(Map<String, dynamic> json) {
    return SessionModel(
      id: json['id'] as String,
      filename: json['filename'] as String,
      pageCount: json['page_count'] as int? ?? 0,
      templateType: json['template_type'] as String? ?? 'definition',
      status: json['status'] as String,
      folderId: json['folder_id'] as String?,
      displayName: json['display_name'] as String?,
      createdAt: json['created_at'] as String,
      cards: (json['cards'] as List<dynamic>)
          .map((c) => CardModel.fromJson(c as Map<String, dynamic>))
          .toList(),
      stats: SessionStats.fromJson(json['stats'] as Map<String, dynamic>),
    );
  }
}

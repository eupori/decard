class CardModel {
  final String id;
  String front;
  String back;
  final String evidence;
  final int evidencePage;
  final String tags;
  final String templateType;
  String status; // pending / accepted / rejected

  CardModel({
    required this.id,
    required this.front,
    required this.back,
    required this.evidence,
    required this.evidencePage,
    required this.tags,
    required this.templateType,
    required this.status,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: json['id'] as String,
      front: json['front'] as String,
      back: json['back'] as String,
      evidence: json['evidence'] as String? ?? '',
      evidencePage: json['evidence_page'] as int? ?? 0,
      tags: json['tags'] as String? ?? '',
      templateType: json['template_type'] as String? ?? 'definition',
      status: json['status'] as String? ?? 'pending',
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';
  bool get isRejected => status == 'rejected';
}

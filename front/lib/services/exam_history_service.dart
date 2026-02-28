import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ExamRecord {
  final String sessionId;
  final String title;
  final DateTime date;
  final int questionCount;
  final int correctCount;
  final int partialCount;
  final int incorrectCount;
  final double score;

  ExamRecord({
    required this.sessionId,
    required this.title,
    required this.date,
    required this.questionCount,
    required this.correctCount,
    required this.partialCount,
    required this.incorrectCount,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'title': title,
        'date': date.toIso8601String(),
        'questionCount': questionCount,
        'correctCount': correctCount,
        'partialCount': partialCount,
        'incorrectCount': incorrectCount,
        'score': score,
      };

  factory ExamRecord.fromJson(Map<String, dynamic> json) => ExamRecord(
        sessionId: json['sessionId'] as String,
        title: json['title'] as String,
        date: DateTime.parse(json['date'] as String),
        questionCount: json['questionCount'] as int,
        correctCount: json['correctCount'] as int,
        partialCount: json['partialCount'] as int,
        incorrectCount: json['incorrectCount'] as int,
        score: (json['score'] as num).toDouble(),
      );
}

class ExamHistoryService {
  static const _key = 'exam_history';

  static Future<List<ExamRecord>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List;
    return list
        .map((e) => ExamRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<List<ExamRecord>> getBySession(String sessionId) async {
    final all = await getAll();
    return all.where((r) => r.sessionId == sessionId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  static Future<void> save(ExamRecord record) async {
    final all = await getAll();
    all.add(record);
    if (all.length > 100) all.removeRange(0, all.length - 100);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key, jsonEncode(all.map((r) => r.toJson()).toList()));
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/session_model.dart';
import '../models/card_model.dart';
import 'auth_service.dart';
import 'device_service.dart';

class ApiService {
  static Future<Map<String, String>> _headers() async {
    final headers = <String, String>{};
    // JWT Bearer 우선
    final token = await AuthService.getToken();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    // device_id는 항상 포함 (폴백 + link-device 용)
    final deviceId = await DeviceService.getDeviceId();
    headers['X-Device-ID'] = deviceId;
    return headers;
  }

  /// PDF 업로드 + 카드 생성 (경로 기반 — 모바일/데스크톱)
  static Future<SessionModel> generate({
    required String filePath,
    required String fileName,
    required String templateType,
  }) async {
    final uri = Uri.parse(ApiConfig.generateUrl);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _headers());

    request.files.add(
      await http.MultipartFile.fromPath('file', filePath, filename: fileName),
    );
    request.fields['template_type'] = templateType;

    return _sendGenerateRequest(request);
  }

  /// PDF 업로드 + 카드 생성 (바이트 기반 — 웹)
  static Future<SessionModel> generateFromBytes({
    required Uint8List bytes,
    required String fileName,
    required String templateType,
  }) async {
    final uri = Uri.parse(ApiConfig.generateUrl);
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _headers());

    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    request.fields['template_type'] = templateType;

    return _sendGenerateRequest(request);
  }

  static Future<SessionModel> _sendGenerateRequest(
      http.MultipartRequest request) async {
    final streamedResponse = await request.send().timeout(
          const Duration(seconds: 120),
        );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw ApiException(
        body['detail'] as String? ?? '카드 생성에 실패했습니다.',
        response.statusCode,
      );
    }

    return SessionModel.fromJson(jsonDecode(response.body));
  }

  /// 세션 조회
  static Future<SessionModel> getSession(String sessionId) async {
    final response = await http.get(
      Uri.parse(ApiConfig.sessionUrl(sessionId)),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw ApiException('세션을 찾을 수 없습니다.', response.statusCode);
    }

    return SessionModel.fromJson(jsonDecode(response.body));
  }

  /// 카드 상태/내용 업데이트
  static Future<CardModel> updateCard(
    String cardId, {
    String? status,
    String? front,
    String? back,
  }) async {
    final body = <String, String>{};
    if (status != null) body['status'] = status;
    if (front != null) body['front'] = front;
    if (back != null) body['back'] = back;

    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final response = await http.patch(
      Uri.parse(ApiConfig.cardUrl(cardId)),
      headers: hdrs,
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw ApiException('카드 업데이트에 실패했습니다.', response.statusCode);
    }

    return CardModel.fromJson(jsonDecode(response.body));
  }

  /// 전체 채택
  static Future<int> acceptAll(String sessionId) async {
    final response = await http.post(
      Uri.parse(ApiConfig.acceptAllUrl(sessionId)),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw ApiException('전체 채택에 실패했습니다.', response.statusCode);
    }

    final data = jsonDecode(response.body);
    return data['accepted'] as int;
  }

  /// 세션 목록 조회
  static Future<List<Map<String, dynamic>>> listSessions() async {
    final response = await http.get(
      Uri.parse(ApiConfig.sessionsUrl),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw ApiException('세션 목록을 불러올 수 없습니다.', response.statusCode);
    }

    final list = jsonDecode(response.body) as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// 세션 삭제
  static Future<void> deleteSession(String sessionId) async {
    final response = await http.delete(
      Uri.parse(ApiConfig.sessionUrl(sessionId)),
      headers: await _headers(),
    );

    if (response.statusCode != 200) {
      throw ApiException('삭제에 실패했습니다.', response.statusCode);
    }
  }

  /// AI 채점 (텍스트 + 선택적 손글씨 이미지)
  static Future<Map<String, dynamic>> gradeCard({
    required String cardId,
    required String userAnswer,
    Uint8List? drawingImage,
  }) async {
    final uri = Uri.parse(ApiConfig.gradeUrl(cardId));
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await _headers());

    request.fields['user_answer'] = userAnswer;

    if (drawingImage != null) {
      request.files.add(
        http.MultipartFile.fromBytes(
          'drawing',
          drawingImage,
          filename: 'drawing.png',
        ),
      );
    }

    final streamedResponse = await request.send().timeout(
          const Duration(seconds: 30),
        );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      final body = jsonDecode(response.body);
      throw ApiException(
        body['detail'] as String? ?? '채점에 실패했습니다.',
        response.statusCode,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}

String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is TimeoutException) return '서버 응답이 너무 오래 걸립니다. 잠시 후 다시 시도해주세요.';
  if (e is SocketException) return '서버에 연결할 수 없습니다. 인터넷 연결을 확인해주세요.';
  return '오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
}

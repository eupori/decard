import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart' as dio;
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../models/session_model.dart';
import '../models/card_model.dart';
import '../models/folder_model.dart';
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
          const Duration(seconds: 600),
        );
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw ApiException(
        _extractDetail(response.body) ?? '카드 생성에 실패했습니다.',
        response.statusCode,
      );
    }

    return SessionModel.fromJson(jsonDecode(response.body));
  }

  /// PDF 업로드 + 카드 생성 (업로드 진행률 콜백 지원)
  static Future<SessionModel> generateWithProgress({
    Uint8List? bytes,
    String? filePath,
    required String fileName,
    required String templateType,
    required void Function(double progress) onProgress,
  }) async {
    final headers = await _headers();

    final formData = dio.FormData.fromMap({
      'template_type': templateType,
      'file': filePath != null
          ? await dio.MultipartFile.fromFile(filePath, filename: fileName)
          : dio.MultipartFile.fromBytes(bytes!, filename: fileName),
    });

    final client = dio.Dio(dio.BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 600),
      receiveTimeout: const Duration(seconds: 600),
    ));

    try {
      final response = await client.post(
        ApiConfig.generateUrl,
        data: formData,
        options: dio.Options(headers: headers),
        onSendProgress: (sent, total) {
          if (total > 0) onProgress(sent / total);
        },
      );

      if (response.statusCode != 200) {
        final detail = response.data is Map
            ? response.data['detail'] as String?
            : null;
        throw ApiException(detail ?? '카드 생성에 실패했습니다.', response.statusCode!);
      }

      return SessionModel.fromJson(response.data as Map<String, dynamic>);
    } on dio.DioException catch (e) {
      if (e.response != null) {
        final data = e.response?.data;
        final detail =
            data is Map ? data['detail'] as String? : null;
        throw ApiException(
            detail ?? '카드 생성에 실패했습니다.', e.response?.statusCode ?? 500);
      }
      throw ApiException('서버에 연결할 수 없습니다.', 0);
    } finally {
      client.close();
    }
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

  // ── Folder API ──

  static Future<List<FolderModel>> listFolders() async {
    final response = await http.get(
      Uri.parse(ApiConfig.foldersUrl),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('폴더 목록을 불러올 수 없습니다.', response.statusCode);
    }
    final list = jsonDecode(response.body) as List;
    return list.map((e) => FolderModel.fromJson(e as Map<String, dynamic>)).toList();
  }

  static Future<FolderModel> createFolder({
    required String name,
    String? color,
  }) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final body = <String, dynamic>{'name': name};
    if (color != null) body['color'] = color;

    final response = await http.post(
      Uri.parse(ApiConfig.foldersUrl),
      headers: hdrs,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException('폴더 생성에 실패했습니다.', response.statusCode);
    }
    return FolderModel.fromJson(jsonDecode(response.body));
  }

  static Future<FolderModel> updateFolder(
    String folderId, {
    String? name,
    String? color,
  }) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (color != null) body['color'] = color;

    final response = await http.patch(
      Uri.parse(ApiConfig.folderUrl(folderId)),
      headers: hdrs,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException('폴더 수정에 실패했습니다.', response.statusCode);
    }
    return FolderModel.fromJson(jsonDecode(response.body));
  }

  static Future<void> deleteFolder(String folderId) async {
    final response = await http.delete(
      Uri.parse(ApiConfig.folderUrl(folderId)),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('폴더 삭제에 실패했습니다.', response.statusCode);
    }
  }

  static Future<List<Map<String, dynamic>>> listFolderSessions(
      String folderId) async {
    final response = await http.get(
      Uri.parse(ApiConfig.folderSessionsUrl(folderId)),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('세션 목록을 불러올 수 없습니다.', response.statusCode);
    }
    final list = jsonDecode(response.body) as List;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> saveToLibrary({
    required String sessionId,
    String? folderId,
    String? newFolderName,
    String? newFolderColor,
    String? displayName,
  }) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final body = <String, dynamic>{};
    if (folderId != null) body['folder_id'] = folderId;
    if (newFolderName != null) body['new_folder_name'] = newFolderName;
    if (newFolderColor != null) body['new_folder_color'] = newFolderColor;
    if (displayName != null) body['display_name'] = displayName;

    final response = await http.post(
      Uri.parse(ApiConfig.saveToLibraryUrl(sessionId)),
      headers: hdrs,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _extractDetail(response.body) ?? '보관함 저장에 실패했습니다.',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> removeFromLibrary(String sessionId) async {
    final response = await http.delete(
      Uri.parse(ApiConfig.removeFromLibraryUrl(sessionId)),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('보관함에서 제거 실패', response.statusCode);
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
      throw ApiException(
        _extractDetail(response.body) ?? '채점에 실패했습니다.',
        response.statusCode,
      );
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }
}

/// JSON body에서 detail 필드 추출 (nginx HTML 에러 페이지 등 비-JSON 응답 안전 처리)
String? _extractDetail(String body) {
  try {
    final json = jsonDecode(body);
    return json['detail'] as String?;
  } catch (_) {
    return null;
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
  if (e is ApiException) {
    switch (e.statusCode) {
      case 401:
        return '로그인이 만료되었습니다. 다시 로그인해주세요.';
      case 413:
        return '파일 크기가 너무 큽니다. 10MB 이하 파일을 사용해주세요.';
      case 429:
        return '요청이 너무 많습니다. 잠시 후 다시 시도해주세요.';
      case 500:
      case 502:
      case 503:
        return '서버에 문제가 발생했습니다. 잠시 후 다시 시도해주세요.';
      default:
        return e.message;
    }
  }
  if (e is TimeoutException) return '서버 응답이 너무 오래 걸립니다. 잠시 후 다시 시도해주세요.';
  if (e is SocketException) return '서버에 연결할 수 없습니다. 인터넷 연결을 확인해주세요.';
  return '오류가 발생했습니다. 잠시 후 다시 시도해주세요.';
}

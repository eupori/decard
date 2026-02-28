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

  /// PDF 업로드 + 카드 생성 (업로드 진행률 콜백 지원, 429 자동 재시도)
  static Future<SessionModel> generateWithProgress({
    Uint8List? bytes,
    String? filePath,
    required String fileName,
    required String templateType,
    required void Function(double progress) onProgress,
    void Function(int retryAfter)? onServerBusy,
  }) async {
    const maxRetries = 3;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
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
        if (e.response?.statusCode == 429 && attempt < maxRetries - 1) {
          final data = e.response?.data;
          int retryAfter = 30;
          if (data is Map) {
            final detail = data['detail'];
            if (detail is Map) {
              retryAfter = detail['retry_after_seconds'] as int? ?? 30;
            }
          }
          onServerBusy?.call(retryAfter);
          await Future.delayed(Duration(seconds: retryAfter));
          continue;
        }
        if (e.response != null) {
          final data = e.response?.data;
          String? detail;
          if (data is Map) {
            // detail이 문자열이면 그대로, Map이면 error 필드 사용
            final d = data['detail'];
            if (d is String) {
              detail = d;
            } else if (d is Map) {
              detail = d['error'] as String?;
            }
          }
          throw ApiException(
              detail ?? '카드 생성에 실패했습니다.', e.response?.statusCode ?? 500);
        }
        throw ApiException('서버에 연결할 수 없습니다.', 0);
      } finally {
        client.close();
      }
    }
    throw ApiException('서버가 바쁩니다. 잠시 후 다시 시도해주세요.', 429);
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

  /// 수동 카드 세션 생성
  static Future<SessionModel> createManualSession({
    String? displayName,
    required List<Map<String, String>> cards,
  }) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final body = <String, dynamic>{
      'cards': cards,
    };
    if (displayName != null && displayName.isNotEmpty) {
      body['display_name'] = displayName;
    }
    final response = await http.post(
      Uri.parse(ApiConfig.createManualUrl),
      headers: hdrs,
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _extractDetail(response.body) ?? '카드 생성에 실패했습니다.',
        response.statusCode,
      );
    }
    return SessionModel.fromJson(jsonDecode(response.body));
  }

  /// 파일(CSV/XLSX) 가져오기로 세션 생성
  static Future<SessionModel> importFile({
    Uint8List? bytes,
    String? filePath,
    required String fileName,
    String? displayName,
  }) async {
    final headers = await _headers();
    final formData = dio.FormData.fromMap({
      'file': filePath != null
          ? await dio.MultipartFile.fromFile(filePath, filename: fileName)
          : dio.MultipartFile.fromBytes(bytes!, filename: fileName),
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    });
    final client = dio.Dio(dio.BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 60),
    ));
    try {
      final response = await client.post(
        ApiConfig.importFileUrl,
        data: formData,
        options: dio.Options(headers: headers),
      );
      if (response.statusCode != 200) {
        final detail = response.data is Map ? response.data['detail'] as String? : null;
        throw ApiException(detail ?? '파일 가져오기에 실패했습니다.', response.statusCode!);
      }
      return SessionModel.fromJson(response.data as Map<String, dynamic>);
    } on dio.DioException catch (e) {
      if (e.response != null) {
        final data = e.response?.data;
        final detail = data is Map ? data['detail'] as String? : null;
        throw ApiException(detail ?? '파일 가져오기에 실패했습니다.', e.response?.statusCode ?? 500);
      }
      throw ApiException('서버에 연결할 수 없습니다.', 0);
    } finally {
      client.close();
    }
  }

  // ── Explore API ──

  static Future<List<Map<String, dynamic>>> getExploreCategories() async {
    final response = await http.get(
      Uri.parse(ApiConfig.exploreCategoriesUrl),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('카테고리를 불러올 수 없습니다.', response.statusCode);
    }
    final list = jsonDecode(response.body) as List;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> getExploreCardsets({
    String? category,
    String sort = 'popular',
    String? search,
  }) async {
    var url = ApiConfig.exploreCardsetsUrl;
    final params = <String>[];
    if (category != null) params.add('category=$category');
    params.add('sort=$sort');
    if (search != null && search.isNotEmpty) {
      params.add('search=${Uri.encodeComponent(search)}');
    }
    if (params.isNotEmpty) url += '?${params.join('&')}';

    final response = await http.get(
      Uri.parse(url),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('카드셋을 불러올 수 없습니다.', response.statusCode);
    }
    final list = jsonDecode(response.body) as List;
    return list.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> getExploreCardsetDetail(
      String id) async {
    final response = await http.get(
      Uri.parse(ApiConfig.exploreCardsetDetailUrl(id)),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('카드셋을 불러올 수 없습니다.', response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<SessionModel> downloadCardset(String id) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final response = await http.post(
      Uri.parse(ApiConfig.exploreDownloadUrl(id)),
      headers: hdrs,
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _extractDetail(response.body) ?? '카드셋 추가에 실패했습니다.',
        response.statusCode,
      );
    }
    return SessionModel.fromJson(jsonDecode(response.body));
  }

  static Future<Map<String, dynamic>> publishSession({
    required String sessionId,
    required String title,
    String description = '',
    String category = 'etc',
  }) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final response = await http.post(
      Uri.parse(ApiConfig.explorePublishUrl),
      headers: hdrs,
      body: jsonEncode({
        'session_id': sessionId,
        'title': title,
        'description': description,
        'category': category,
      }),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _extractDetail(response.body) ?? '카드셋 공유에 실패했습니다.',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ── SRS API ──

  /// 카드 복습 결과 기록
  static Future<Map<String, dynamic>> reviewCard({
    required String cardId,
    required int rating,
  }) async {
    final hdrs = await _headers();
    hdrs['Content-Type'] = 'application/json';
    final response = await http.post(
      Uri.parse(ApiConfig.reviewUrl(cardId)),
      headers: hdrs,
      body: jsonEncode({'rating': rating}),
    );
    if (response.statusCode != 200) {
      throw ApiException(
        _extractDetail(response.body) ?? '복습 기록에 실패했습니다.',
        response.statusCode,
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// 오늘 복습할 카드 목록
  static Future<List<Map<String, dynamic>>> getDueCards({
    String? folderId,
    int limit = 50,
  }) async {
    var url = '${ApiConfig.studyDueUrl}?limit=$limit';
    if (folderId != null) url += '&folder_id=$folderId';
    final response = await http.get(
      Uri.parse(url),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('복습 카드를 불러올 수 없습니다.', response.statusCode);
    }
    final list = jsonDecode(response.body) as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// 학습 통계
  static Future<Map<String, dynamic>> getStudyStats() async {
    final response = await http.get(
      Uri.parse(ApiConfig.studyStatsUrl),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw ApiException('학습 통계를 불러올 수 없습니다.', response.statusCode);
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
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

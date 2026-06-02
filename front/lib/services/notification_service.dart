import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import '../main.dart' show navigatorKey;
import '../screens/review_screen.dart';
import 'api_service.dart';
import 'auth_service.dart';

/// FCM 푸시 알림 통합 서비스.
///
/// 동작:
/// - Firebase 초기화 (main.dart 시작 시)
/// - 권한 요청 → FCM 토큰 획득 → 백엔드 등록
/// - 포그라운드 알림: flutter_local_notifications로 OS 알림 띄움
/// - 백그라운드/종료 알림: OS가 자동 표시 (탭 시 앱 실행)
class NotificationService {
  static final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'decard_default',
    '카드 생성 알림',
    description: '카드 생성 완료, 학습 리마인더 등 데카드 알림',
    importance: Importance.high,
  );

  static const String _tokenPrefKey = 'fcm_token_registered';
  static const String _tokenOwnerPrefKey = 'fcm_token_registered_owner';

  /// 앱 시작 시 1회 호출. Firebase 초기화 + 로컬 알림 채널 등록.
  /// 실패해도 앱 동작에는 영향 없도록 try/catch.
  static Future<void> initialize() async {
    if (kIsWeb) return; // 웹은 별도 처리 (다음 이터레이션)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 백그라운드 핸들러는 top-level 함수여야 함
      FirebaseMessaging.onBackgroundMessage(_backgroundHandler);

      // 포그라운드 알림 → 로컬 알림으로 직접 표시 (OS가 자동 안 띄움)
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      // Android 알림 채널 생성
      await _localPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // 로컬 알림 초기화 (탭 콜백 포함)
      await _localPlugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          // 포그라운드 로컬 알림 탭 → payload에 session_id
          final sessionId = response.payload;
          if (sessionId != null && sessionId.isNotEmpty) {
            _navigateToSession(sessionId);
          }
        },
      );

      // 백그라운드 상태에서 알림 탭 → 앱 활성화 시
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final sessionId = message.data['session_id']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          _navigateToSession(sessionId);
        }
      });

      // 앱 종료 상태에서 알림 탭 → 앱 시작 직후 1회
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final sessionId = initial.data['session_id']?.toString();
        if (sessionId != null && sessionId.isNotEmpty) {
          // 첫 프레임 후 네비게이션 (navigatorKey 준비 대기)
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigateToSession(sessionId);
          });
        }
      }
    } catch (e, st) {
      debugPrint('[NotificationService] init 실패 — 알림 비활성: $e\n$st');
    }
  }

  /// 알림 페이로드의 session_id로 ReviewScreen 이동.
  /// 세션 조회 실패하거나 status가 completed가 아니면 무시 (홈에서 폴링이 처리).
  static Future<void> _navigateToSession(String sessionId) async {
    try {
      final session = await ApiService.getSession(sessionId);
      if (session.status != 'completed') {
        debugPrint('[NotificationService] 세션 status=${session.status}, 라우팅 생략');
        return;
      }
      final navigator = navigatorKey.currentState;
      if (navigator == null) {
        debugPrint('[NotificationService] navigator 준비 안 됨');
        return;
      }
      navigator.push(
        MaterialPageRoute(builder: (_) => ReviewScreen(session: session)),
      );
    } catch (e) {
      debugPrint('[NotificationService] 세션 라우팅 실패: $e');
    }
  }

  /// 권한 요청 + FCM 토큰 받아서 백엔드 등록. 로그인/로그아웃/홈 진입 후 호출.
  ///
  /// 캐시 비교는 (token, ownerKey) 조합. ownerKey는 로그인 user_id 또는 비로그인 시 device_id.
  /// 로그인 상태가 바뀌면 같은 토큰이라도 서버 측 user_id가 갱신되도록 재등록.
  static Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[NotificationService] 알림 권한 거부');
        return;
      }

      final token = await messaging.getToken();
      if (token == null) {
        debugPrint('[NotificationService] FCM 토큰 획득 실패');
        return;
      }

      final ownerKey = await _currentOwnerKey();
      final prefs = await SharedPreferences.getInstance();
      final cachedToken = prefs.getString(_tokenPrefKey);
      final cachedOwner = prefs.getString(_tokenOwnerPrefKey);
      if (cachedToken == token && cachedOwner == ownerKey) {
        return; // 같은 토큰 + 같은 소유자(로그인 상태)면 스킵
      }

      final ok = await ApiService.registerFcmToken(token);
      if (ok) {
        await prefs.setString(_tokenPrefKey, token);
        await prefs.setString(_tokenOwnerPrefKey, ownerKey);
        debugPrint('[NotificationService] FCM 토큰 등록 성공 (owner=$ownerKey)');
      }

      // 토큰 갱신 핸들러 — onTokenRefresh는 별도 이벤트, 다중 listen 방지를 위해 set으로 게이팅
      _attachTokenRefreshListener();
    } catch (e) {
      debugPrint('[NotificationService] 토큰 등록 실패: $e');
    }
  }

  /// 현재 등록 소유자 식별 문자열. 로그인 시 "user:{id}", 비로그인 시 토큰 그룹 분리용 빈 문자열.
  /// 서버는 JWT/device_id로 owner를 결정하므로 클라이언트는 user_id 변경만 감지하면 됨.
  static Future<String> _currentOwnerKey() async {
    final user = await AuthService.getUser();
    final id = user?['id'] as String?;
    return id != null ? 'user:$id' : 'anon';
  }

  static bool _tokenRefreshAttached = false;
  static void _attachTokenRefreshListener() {
    if (_tokenRefreshAttached) return;
    _tokenRefreshAttached = true;
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      final ok = await ApiService.registerFcmToken(newToken);
      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenPrefKey, newToken);
        await prefs.setString(_tokenOwnerPrefKey, await _currentOwnerKey());
      }
    });
  }

  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    await _localPlugin.show(
      message.hashCode,
      notification.title ?? '데카드',
      notification.body ?? '',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['session_id'],
    );
  }
}

/// 백그라운드/종료 상태에서 메시지 수신 시 호출 (OS가 알림 자동 표시).
/// 추가 처리 필요 시 여기에. 현재는 OS 기본 표시만 사용.
@pragma('vm:entry-point')
Future<void> _backgroundHandler(RemoteMessage message) async {
  // Firebase는 이미 main isolate에서 init됐지만 background isolate에선 재init 필요
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  debugPrint('[NotificationService] background message: ${message.messageId}');
}

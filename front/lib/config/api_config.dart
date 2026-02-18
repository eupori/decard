class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.35.211:8001',
  );
  static const String apiPrefix = '/api/v1';

  static String get generateUrl => '$baseUrl$apiPrefix/generate';
  static String sessionUrl(String id) => '$baseUrl$apiPrefix/sessions/$id';
  static String cardUrl(String id) => '$baseUrl$apiPrefix/cards/$id';
  static String acceptAllUrl(String id) =>
      '$baseUrl$apiPrefix/sessions/$id/accept-all';
  static String downloadUrl(String id) =>
      '$baseUrl$apiPrefix/sessions/$id/download';
  static String get sessionsUrl => '$baseUrl$apiPrefix/sessions';
  static String gradeUrl(String id) => '$baseUrl$apiPrefix/cards/$id/grade';

  // Auth
  static String get kakaoLoginUrl => '$baseUrl$apiPrefix/auth/kakao/login';
  static String get authMeUrl => '$baseUrl$apiPrefix/auth/me';
  static String get linkDeviceUrl => '$baseUrl$apiPrefix/auth/link-device';
}

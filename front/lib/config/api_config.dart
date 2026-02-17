class ApiConfig {
  // 개발: localhost, 프로덕션: EC2 URL로 변경
  static const String baseUrl = 'http://localhost:8001';
  static const String apiPrefix = '/api/v1';

  static String get generateUrl => '$baseUrl$apiPrefix/generate';
  static String sessionUrl(String id) => '$baseUrl$apiPrefix/sessions/$id';
  static String cardUrl(String id) => '$baseUrl$apiPrefix/cards/$id';
  static String acceptAllUrl(String id) =>
      '$baseUrl$apiPrefix/sessions/$id/accept-all';
  static String downloadUrl(String id) =>
      '$baseUrl$apiPrefix/sessions/$id/download';
}

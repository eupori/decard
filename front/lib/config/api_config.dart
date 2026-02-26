class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8001',
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

  // SRS
  static String reviewUrl(String cardId) => '$baseUrl$apiPrefix/cards/$cardId/review';
  static String get studyDueUrl => '$baseUrl$apiPrefix/study/due';
  static String get studyStatsUrl => '$baseUrl$apiPrefix/study/stats';

  // Manual / Import
  static String get createManualUrl => '$baseUrl$apiPrefix/sessions/create-manual';
  static String get importFileUrl => '$baseUrl$apiPrefix/sessions/import-file';

  // Auth
  static String get kakaoLoginUrl => '$baseUrl$apiPrefix/auth/kakao/login';
  static String get authMeUrl => '$baseUrl$apiPrefix/auth/me';
  static String get linkDeviceUrl => '$baseUrl$apiPrefix/auth/link-device';

  // Folders
  static String get foldersUrl => '$baseUrl$apiPrefix/folders';
  static String folderUrl(String id) => '$baseUrl$apiPrefix/folders/$id';
  static String folderSessionsUrl(String id) =>
      '$baseUrl$apiPrefix/folders/$id/sessions';
  static String saveToLibraryUrl(String sessionId) =>
      '$baseUrl$apiPrefix/sessions/$sessionId/save-to-library';
  static String removeFromLibraryUrl(String sessionId) =>
      '$baseUrl$apiPrefix/sessions/$sessionId/remove-from-library';

  // Explore
  static String get exploreCategoriesUrl => '$baseUrl$apiPrefix/explore/categories';
  static String get exploreCardsetsUrl => '$baseUrl$apiPrefix/explore/cardsets';
  static String exploreCardsetDetailUrl(String id) => '$baseUrl$apiPrefix/explore/cardsets/$id';
  static String exploreDownloadUrl(String id) => '$baseUrl$apiPrefix/explore/cardsets/$id/download';
  static String get explorePublishUrl => '$baseUrl$apiPrefix/explore/publish';
}

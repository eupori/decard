import 'dart:convert';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// 웹: Blob URL로 파일 다운로드 트리거
void downloadFile(String fileName, Uint8List bytes) {
  final base64 = base64Encode(bytes);
  final dataUrl = 'data:application/octet-stream;base64,$base64';
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
  anchor.href = dataUrl;
  anchor.download = fileName;
  anchor.click();
}

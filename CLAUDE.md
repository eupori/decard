# CLAUDE.md - 데카드 (Decard) 프로젝트 가이드

## 프로젝트 개요

**데카드**는 PDF를 올리면 근거 포함 암기카드를 자동 생성하는 시험 대비 학습 도구입니다.
핵심: PDF 업로드 → AI 카드 생성(근거+페이지) → 검수(채택/삭제/수정) → 학습(플래시카드)

**타겟:** 대학생, 고등학생, 자격증 준비생
**현재 상태:** MVP Day 2.5 완료 (웹 + Android APK 동작)

---

## 빠른 시작

### 백엔드

```bash
cd back
source .venv/bin/activate
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

### 프론트엔드 (웹)

```bash
cd front
flutter run -d chrome --web-port 8080
```

### APK 빌드

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
export JAVA_HOME="/opt/homebrew/Cellar/openjdk@21/21.0.10/libexec/openjdk.jdk/Contents/Home"
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
cd front
flutter build apk --release
# 결과: build/app/outputs/flutter-apk/app-release.apk (약 49MB)
```

---

## 아키텍처

```
decard/
├── back/               # FastAPI (Python 3.14)
│   ├── app/
│   │   ├── main.py           # FastAPI 앱, CORS, 라우터
│   │   ├── config.py         # Pydantic Settings (환경변수)
│   │   ├── database.py       # SQLAlchemy + SQLite
│   │   ├── models.py         # Session/Card 모델 + Pydantic 스키마
│   │   ├── routes.py         # API 엔드포인트
│   │   ├── card_service.py   # Claude 카드 생성 (청크 병렬)
│   │   └── pdf_service.py    # pdfplumber 텍스트 추출
│   ├── .env                  # 환경변수 (ANTHROPIC_API_KEY 등)
│   └── requirements.txt
├── front/              # Flutter 3.41.1 (Web + Android + iOS)
│   └── lib/
│       ├── main.dart              # 앱 진입, 다크/라이트 테마
│       ├── config/
│       │   ├── api_config.dart    # API URL 설정
│       │   └── theme.dart         # Material 3 테마 (민트 팔레트)
│       ├── models/
│       │   ├── card_model.dart    # 카드 데이터 모델
│       │   └── session_model.dart # 세션 데이터 모델
│       ├── services/
│       │   └── api_service.dart   # HTTP 클라이언트
│       ├── screens/
│       │   ├── home_screen.dart   # 홈 (업로드, 템플릿, 기록)
│       │   ├── review_screen.dart # 리뷰 (채택/삭제/수정)
│       │   └── study_screen.dart  # 학습 (플래시카드)
│       └── widgets/
│           └── flash_card_item.dart  # 카드 위젯
└── docs/
    ├── BUSINESS.md       # 사업 계획서
    └── MVP_CHECKLIST.md  # MVP 체크리스트
```

---

## API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| POST | `/api/v1/generate` | PDF 업로드 + 카드 생성 |
| GET | `/api/v1/sessions` | 세션 목록 (최근 50개) |
| GET | `/api/v1/sessions/{id}` | 세션 상세 (카드 포함) |
| DELETE | `/api/v1/sessions/{id}` | 세션 삭제 |
| PATCH | `/api/v1/cards/{id}` | 카드 수정 (status/front/back) |
| POST | `/api/v1/sessions/{id}/accept-all` | 전체 채택 |
| GET | `/health` | 헬스체크 |

### 템플릿 타입
- `definition`: 정의형 ("OO란?")
- `cloze`: 빈칸형 ("___에 들어갈 말은?")
- `comparison`: 비교형 ("A vs B")

---

## 핵심 패턴

### 카드 생성 흐름

```
PDF 업로드 → pdfplumber 텍스트 추출 (페이지별)
  → 5페이지씩 청크 분할
  → asyncio.gather로 병렬 Claude API 호출
  → JSON 파싱 + 필수 필드 검증
  → DB 저장 (Session + Cards)
```

### 테마 시스템

- `themeNotifier` (ValueNotifier<ThemeMode>) — 글로벌 다크/라이트 토글
- 팔레트: 민트 `#C2E7DA`, 블루 `#6290C3`, 남색 `#1A1B41`
- 라이트: 민트 틴트 배경 `#E8F0EC` (순백 X, 눈 피로 감소)
- 다크: `#121212` 배경, navy 계열 서피스

### 웹/모바일 분기

- `kIsWeb` — file_picker에서 bytes vs path 분기
- `withData: kIsWeb` — 웹에서는 bytes로 읽기
- Android: `usesCleartextTraffic="true"` (로컬 HTTP 테스트용)

---

## 환경변수

### 백엔드 (`back/.env`)

```bash
APP_ENV=dev
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://192.168.35.211:8080
ANTHROPIC_API_KEY=sk-ant-...
LLM_MODEL=claude-sonnet-4-5-20250929
LLM_MAX_TOKENS=8000
DATABASE_URL=sqlite:///./decard.db
MAX_PDF_SIZE_MB=10
MAX_PAGES=100
```

### 프론트엔드 (`front/lib/config/api_config.dart`)

```dart
static const String baseUrl = 'http://192.168.35.211:8001'; // 로컬 테스트
// 프로덕션: https://decard-api.eupori.dev (배포 후)
```

---

## 주의사항

1. **FilledButton in Row**: 테마에서 `minimumSize: Size(double.infinity, 52)` 설정됨. Row 안에서 쓸 때는 반드시 `minimumSize: Size.zero` 오버라이드 또는 `Flexible` 래핑
2. **AnimatedCrossFade 텍스트 겹침**: 다크모드에서 특히 눈에 띔. 단순 조건부 렌더링(`_showBack ? back : front`)이 안전
3. **HTTP 헤더 한국어**: `Content-Disposition`에 한국어 파일명 → `latin-1` 에러. `filename*=UTF-8''` (RFC 5987) 사용
4. **Android cleartext**: release APK에서 HTTP 접근 시 `AndroidManifest.xml`에 `usesCleartextTraffic="true"` 필수
5. **Flutter 웹 핫리로드**: `flutter run -d chrome`이 죽으면 포트 점유 남음. `lsof -ti :8080 | xargs kill -9` 후 재시작
6. **세션 ID 형식**: `ses_{uuid.hex[:10]}`, 카드 ID: `card_{uuid.hex[:8]}`
7. **PDF**: 텍스트 PDF만 지원 (스캔/OCR은 후순위). 크기 10MB, 100페이지 제한
8. **`.env`와 `decard.db`**: 절대 커밋 금지

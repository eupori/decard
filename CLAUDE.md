# CLAUDE.md - 데카드 (Decard) 프로젝트 가이드

## 프로젝트 개요

**데카드**는 PDF를 올리면 근거 포함 암기카드를 자동 생성하는 시험 대비 학습 도구입니다.
핵심: PDF 업로드 → AI 카드 생성(근거+페이지) → 검수(채택/삭제/수정) → 학습(플래시카드)

**타겟:** 대학생, 고등학생, 자격증 준비생
**현재 상태:** Phase 2 (콘시어지 테스트 준비) — 카카오 로그인 완료, 프로덕션 배포됨

**프로덕션 URL:**
- 웹: https://decard.eupori.dev
- API: https://decard-api.eupori.dev
- VPS: `ssh eupori-server` (EC2, ~/apps/decard)

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

### 프로덕션 배포

```bash
# 1. Flutter 웹 빌드
cd front
flutter build web --dart-define=API_BASE_URL=https://decard-api.eupori.dev

# 2. VPS에 전송 + 배포
tar czf /tmp/decard-web.tar.gz -C build/web .
scp /tmp/decard-web.tar.gz eupori-server:~/apps/decard/decard-web.tar.gz
ssh eupori-server "cd ~/apps/decard && git pull origin master && docker compose build --no-cache && docker compose up -d && rm -rf web/* && tar xzf decard-web.tar.gz -C web/ && docker exec back-nginx-1 rm -rf /var/www/decard/* && docker cp web/. back-nginx-1:/var/www/decard/"
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
├── back/               # FastAPI (Python 3.11)
│   ├── app/
│   │   ├── main.py           # FastAPI 앱, CORS, 라우터
│   │   ├── config.py         # Pydantic Settings (환경변수)
│   │   ├── database.py       # SQLAlchemy + SQLite + 마이그레이션
│   │   ├── models.py         # User/Session/Card 모델 + Pydantic 스키마
│   │   ├── routes.py         # API 엔드포인트 (듀얼 인증)
│   │   ├── auth.py           # JWT + 카카오 OAuth + get_owner_filter
│   │   ├── auth_routes.py    # /auth/kakao/login, /callback, /me, /link-device
│   │   ├── card_service.py   # Claude 카드 생성 (청크 병렬)
│   │   ├── grade_service.py  # AI 채점
│   │   └── pdf_service.py    # pdfplumber 텍스트 추출
│   ├── .env                  # 로컬 환경변수
│   ├── .env.production       # 프로덕션 환경변수
│   └── requirements.txt
├── front/              # Flutter 3.41.1 (Web + Android + iOS)
│   └── lib/
│       ├── main.dart              # 앱 진입, 다크/라이트 테마
│       ├── config/
│       │   ├── api_config.dart    # API URL 설정 (auth URL 포함)
│       │   └── theme.dart         # Material 3 테마 (민트 팔레트)
│       ├── models/
│       │   ├── card_model.dart    # 카드 데이터 모델
│       │   └── session_model.dart # 세션 데이터 모델
│       ├── services/
│       │   ├── api_service.dart   # HTTP 클라이언트 (JWT Bearer + device_id)
│       │   ├── auth_service.dart  # JWT 토큰 저장, 유저 캐싱, 로그인/로그아웃
│       │   └── device_service.dart # 디바이스 ID 관리
│       ├── screens/
│       │   ├── home_screen.dart   # 홈 (업로드, 템플릿, 기록, 로그인 상태)
│       │   ├── login_screen.dart  # 로그인 (카카오/Google/Apple/이메일)
│       │   ├── review_screen.dart # 리뷰 (채택/삭제/수정)
│       │   └── study_screen.dart  # 학습 (플래시카드)
│       ├── utils/
│       │   ├── web_auth.dart      # 웹: URL fragment 토큰 추출
│       │   ├── web_auth_stub.dart # 비웹 스텁
│       │   └── snackbar_helper.dart
│       └── widgets/
│           └── flash_card_item.dart  # 카드 위젯
├── deploy/
│   └── deploy.sh             # VPS 배포 스크립트
├── docker-compose.yml        # 백엔드 Docker 설정
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
| GET | `/api/v1/sessions/{id}/download` | CSV 다운로드 (Anki 호환) |
| POST | `/api/v1/cards/{id}/grade` | AI 채점 |
| GET | `/api/v1/auth/kakao/login` | 카카오 로그인 리다이렉트 |
| GET | `/api/v1/auth/kakao/callback` | 카카오 OAuth 콜백 → JWT 발급 |
| GET | `/api/v1/auth/me` | 현재 유저 정보 |
| POST | `/api/v1/auth/link-device` | 디바이스 세션 마이그레이션 |
| GET | `/health` | 헬스체크 |

### 템플릿 타입
- `definition`: 정의형 ("OO란?")
- `cloze`: 빈칸형 ("___에 들어갈 말은?")
- `comparison`: 비교형 ("A vs B")

---

## 인증 시스템

### OAuth 플로우
```
프론트 → /auth/kakao/login → 카카오 → /auth/kakao/callback
  → 코드 교환 → 유저 생성/조회 → JWT 발급
  → 프론트로 리다이렉트 (/#token=xxx)
  → 프론트가 token 저장 → 이후 API에 Bearer 토큰 사용
```

### 듀얼 인증
- **JWT Bearer 우선**: 로그인 유저는 `user_id`로 세션 조회
- **device_id 폴백**: 비로그인 시 `X-Device-ID` 헤더로 조회 (하위 호환)
- **디바이스 연동**: 첫 로그인 시 `/auth/link-device`로 기존 세션 마이그레이션 (device_id → user_id)

### 소셜 로그인 상태
- **카카오**: 동작 (REST API 직접 사용, SDK X)
- **Google**: 목업 (준비 중 안내)
- **Apple**: 목업 (준비 중 안내)
- **이메일**: 목업 (준비 중 안내)

### 카카오 개발자 콘솔 설정
- 앱 ID: 1388478 (Decard)
- **REST API 키 > Redirect URI**에 등록 필요 (앱 > 플랫폼 키 > REST API 키 클릭)
- 로컬: `http://192.168.35.211:8001/api/v1/auth/kakao/callback`
- 프로덕션: `https://decard-api.eupori.dev/api/v1/auth/kakao/callback`

---

## 핵심 패턴

### 카드 생성 흐름

```
PDF 업로드 → pdfplumber 텍스트 추출 (페이지별)
  → 세션 생성 (status=processing) → 즉시 반환
  → asyncio.create_task로 백그라운드 실행:
    → 5페이지씩 청크 분할
    → asyncio.gather로 병렬 Claude API 호출
    → JSON 파싱 + 필수 필드 검증
    → DB 저장 (Cards) + status=completed (실패 시 status=failed)
  → 프론트: 포그라운드 대기 (5초 폴링) 또는 홈 복귀 (10초 폴링)
```

### 테마 시스템

- `themeNotifier` (ValueNotifier<ThemeMode>) — 글로벌 다크/라이트 토글
- 팔레트: 민트 `#C2E7DA`, 블루 `#6290C3`, 남색 `#1A1B41`
- 라이트: 민트 틴트 배경 `#E8F0EC` (순백 X, 눈 피로 감소)
- 다크: `#121212` 배경, navy 계열 서피스

### 웹/모바일 분기

- `kIsWeb` — file_picker에서 bytes vs path 분기
- `withData: kIsWeb` — 웹에서는 bytes로 읽기
- 조건부 임포트: `web_auth_stub.dart` if (dart.library.html) `web_auth.dart`
- Android: `usesCleartextTraffic="true"` (로컬 HTTP 테스트용)

---

## 환경변수

### 백엔드 (`back/.env`)

```bash
APP_ENV=dev
CORS_ORIGINS=http://localhost:3000,http://localhost:8080,http://192.168.35.211:8080
LLM_MODEL=claude-sonnet-4-5-20250929
DATABASE_URL=sqlite:///./decard.db
MAX_PDF_SIZE_MB=10
MAX_PAGES=100

# Kakao OAuth
KAKAO_CLIENT_ID=<REST API 키>
KAKAO_CLIENT_SECRET=<클라이언트 시크릿>
KAKAO_REDIRECT_URI=http://192.168.35.211:8001/api/v1/auth/kakao/callback

# JWT
JWT_SECRET_KEY=dev-secret-change-me
JWT_EXPIRE_HOURS=168

# Frontend (OAuth 리다이렉트 대상)
FRONTEND_URL=http://localhost:8080
```

### 프론트엔드 (`front/lib/config/api_config.dart`)

```dart
static const String baseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.35.211:8001',
);
// 프로덕션 빌드: flutter build web --dart-define=API_BASE_URL=https://decard-api.eupori.dev
```

---

## 주의사항

1. **FilledButton in Row**: 테마에서 `minimumSize: Size(double.infinity, 52)` 설정됨. Row 안에서 쓸 때는 반드시 `minimumSize: Size.zero` 오버라이드 또는 `Flexible` 래핑
2. **AnimatedCrossFade 텍스트 겹침**: 다크모드에서 특히 눈에 띔. 단순 조건부 렌더링(`_showBack ? back : front`)이 안전
3. **HTTP 헤더 한국어**: `Content-Disposition`에 한국어 파일명 → `latin-1` 에러. `filename*=UTF-8''` (RFC 5987) 사용
4. **Android cleartext**: release APK에서 HTTP 접근 시 `AndroidManifest.xml`에 `usesCleartextTraffic="true"` 필수
5. **Flutter 웹 핫리로드**: `flutter run -d chrome`이 죽으면 포트 점유 남음. `lsof -ti :8080 | xargs kill -9` 후 재시작
6. **세션 ID 형식**: `ses_{uuid.hex[:10]}`, 카드 ID: `card_{uuid.hex[:8]}`, 유저 ID: `usr_{uuid.hex[:10]}`
7. **PDF**: 텍스트 PDF만 지원 (스캔/OCR은 후순위). 크기 10MB, 100페이지 제한
8. **`.env`와 `decard.db`**: 절대 커밋 금지
9. **카카오 Redirect URI**: 카카오 콘솔 > 앱 > 플랫폼 키 > REST API 키 클릭 > 카카오 로그인 리다이렉트 URI에서 설정
10. **Flutter web_auth**: `package:web` 사용 (dart:html deprecated). `history.replaceState` 대신 `location.hash = ''` 사용 (Flutter 히스토리 충돌 방지)
11. **백그라운드 태스크와 --reload**: `uvicorn --reload`가 코드 변경 감지 시 워커를 재시작하면 `asyncio.create_task`로 생성된 백그라운드 태스크가 소멸됨. 프로덕션에서는 `--reload` 없으므로 문제없음. 로컬 테스트 중 코드 수정 시 processing 세션이 stuck될 수 있음
12. **UTC 시간**: models.py에서 `datetime.utcnow`로 저장. API 응답에서 `isoformat() + "Z"` 필수 (프론트 DateTime.tryParse가 Z를 보고 UTC로 파싱)

---

## 완료된 작업 이력

### Phase 1: MVP (Day 1~2.5)
- PDF 업로드 → AI 카드 생성 → 검수 → 학습 루프 완성
- Flutter Web + Android APK
- 3종 템플릿 (정의/빈칸/비교)
- 다크/라이트 테마

### Phase 1.5: 배포 + 폴리싱
- Docker Compose + EC2 배포
- 디바이스 인증 (device_id)
- 3단계 페르소나 병렬 검수 시스템
- 빈칸(Cloze) 스타일링 위젯
- AI 채점 (주관식)

### Phase 2: 카카오 로그인
- 카카오 OAuth 로그인 (REST API 직접, JWT 7일)
- 로그인 화면 (카카오 동작 + Google/Apple/이메일 목업)
- 듀얼 인증 (JWT user_id 우선, device_id 폴백)
- 디바이스 세션 마이그레이션 (로그인 시 자동)
- 프로덕션 배포 완료

### Phase 2.5: 백그라운드 카드 생성 (현재)
- POST /generate 즉시 반환 (status=processing) + asyncio 백그라운드 생성
- 포그라운드/백그라운드 선택 UX (업로드 → 선택지 → 대기 or 홈 복귀)
- 포그라운드 대기: 원형 프로그레스(%) + 예상 시간 + 감성 문구 로테이션 → 완료 시 ReviewScreen 자동 이동
- 백그라운드 대기: 홈에서 10초 폴링 + 완료 시 스낵바 알림
- 세션 목록에 processing/failed 상태 UI (스피너/에러 아이콘)
- UTC 시간 버그 수정 (isoformat + "Z" 접미사)
- 프로덕션 배포 완료

---

## 다음 작업 후보 (Phase 3~)

| 우선순위 | 작업 | 설명 |
|----------|------|------|
| 1 | 보관함 | 세션/카드 보관 및 관리 기능 |
| 2 | 콘시어지 테스트 배포 | 테스터에게 링크 공유 + 피드백 폼 |
| 3 | APK 업데이트 | 로그인 반영된 Android APK 빌드 |
| 4 | Google Play Store 등록 | 앱 이름, 설명, 스크린샷 |
| 5 | SRS 반복학습 | 간격 반복 알고리즘 (SM-2 등) |
| 6 | 이메일 회원가입 | 카카오 없는 유저 대응 |
| 7 | Google/Apple 로그인 | 실제 구현 (현재 목업) |

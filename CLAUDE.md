# CLAUDE.md - 데카드 (Decard) 프로젝트 가이드

## 프로젝트 개요

**데카드**는 PDF를 올리면 근거 포함 암기카드를 자동 생성하는 시험 대비 학습 도구입니다.
핵심: PDF 업로드 → AI 카드 생성(근거+페이지) → 검수(채택/삭제/수정) → 학습(플래시카드)

**타겟:** 대학생, 고등학생, 자격증 준비생
**현재 상태:** Phase 4 (자동 채택 + QA 완료) — 프로덕션 배포 완료

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
│   │   ├── card_service.py   # Claude 카드 생성 (청크 병렬 + 자체검수 통합 + 재시도)
│   │   ├── claude_cli.py     # Claude CLI 래퍼 (JSON 출력, Semaphore=3)
│   │   ├── review_service.py # 검수 서비스 (레거시, 현재 미사용)
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
│       │   ├── folder_model.dart  # 폴더(과목) 데이터 모델
│       │   └── session_model.dart # 세션 데이터 모델
│       ├── services/
│       │   ├── api_service.dart   # HTTP 클라이언트 (JWT Bearer + device_id + dio 업로드)
│       │   ├── auth_service.dart  # JWT 토큰 저장, 유저 캐싱, 로그인/로그아웃
│       │   ├── device_service.dart # 디바이스 ID 관리
│       │   └── library_prefs.dart # 보관함 자동저장 설정 (SharedPreferences)
│       ├── screens/
│       │   ├── main_screen.dart   # 메인 (바텀 네비게이션: 홈/보관함)
│       │   ├── home_screen.dart   # 홈 (업로드, 템플릿, 기록, 로그인 상태)
│       │   ├── login_screen.dart  # 로그인 (카카오/Google/Apple/이메일)
│       │   ├── library_screen.dart # 보관함 (폴더 그리드)
│       │   ├── folder_detail_screen.dart # 폴더 상세 (세션 목록)
│       │   ├── review_screen.dart # 리뷰 (채택/삭제/수정)
│       │   └── study_screen.dart  # 학습 (플래시카드)
│       ├── utils/
│       │   ├── web_auth.dart      # 웹: URL fragment 토큰 추출
│       │   ├── web_auth_stub.dart # 비웹 스텁
│       │   └── snackbar_helper.dart
│       └── widgets/
│           ├── flash_card_item.dart      # 카드 위젯
│           └── save_to_library_dialog.dart # 보관함 저장 모달
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
| GET | `/api/v1/folders` | 폴더(과목) 목록 |
| POST | `/api/v1/folders` | 폴더 생성 |
| PATCH | `/api/v1/folders/{id}` | 폴더 수정 (이름/색상) |
| DELETE | `/api/v1/folders/{id}` | 폴더 삭제 (세션 보존) |
| GET | `/api/v1/folders/{id}/sessions` | 폴더 내 세션 목록 |
| POST | `/api/v1/sessions/{id}/save-to-library` | 보관함 저장 |
| DELETE | `/api/v1/sessions/{id}/remove-from-library` | 보관함 제거 |
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
- 로컬: `http://localhost:8001/api/v1/auth/kakao/callback`
- 프로덕션: `https://decard-api.eupori.dev/api/v1/auth/kakao/callback`

---

## 핵심 패턴

### 카드 생성 흐름

```
PDF 업로드 (dio, 진행률 표시)
  → 세션 생성 (status=processing) → 즉시 반환
  → asyncio.create_task로 백그라운드 실행:
    → pdfplumber 텍스트 추출 (페이지별)
    → 5페이지씩 청크 분할
    → asyncio.gather로 병렬 Claude CLI 호출 (Semaphore=3)
      → 각 청크: 카드 생성 + 교수 관점 자체검수 (1회 호출로 통합)
      → --output-format json 강제, 실패 시 3회 재시도 (2/5/10초 백오프)
      → recommend 필드로 자동 채택 (recommend=true → accepted, 최소 10장)
    → DB 저장 (Cards, status=accepted/pending) + session status=completed
  → 프론트: 포그라운드 대기 (5초 폴링) 또는 홈 복귀 (10초 폴링)
  → 프로그레스: 80%까지 선형, 이후 99%까지 점근적 증가 (멈춤 방지)
```

### 테마 시스템

- `themeNotifier` (ValueNotifier<ThemeMode>) — 글로벌 다크/라이트 토글
- SharedPreferences `theme_mode` 키로 설정 캐싱 (앱 재시작 시 복원)
- 팔레트: 민트 `#C2E7DA`, 블루 `#6290C3`, 남색 `#1A1B41`
- 라이트: 민트 틴트 배경 `#E8F0EC` (순백 X, 눈 피로 감소)
- 다크: `#121212` 배경, navy 계열 서피스

### 네비게이션 구조

- `MainScreen` — BottomNavigationBar 2탭 (홈/보관함) + IndexedStack
- `hideBottomNav` (ValueNotifier<bool>) — 카드 생성 로딩 시 바텀바 숨김
- `mainTabIndex` (ValueNotifier<int>) — push된 화면에서 탭 전환용
- `buildAppBottomNav()` — ReviewScreen, FolderDetailScreen 등에서 공유 바텀바
- 보관함 탭은 로그인 유저만 접근 가능 (비로그인 시 로그인 유도 화면)

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
CORS_ORIGINS=http://localhost:3000,http://localhost:8080
LLM_MODEL=claude-sonnet-4-5-20250929
DATABASE_URL=sqlite:///./decard.db
MAX_PDF_SIZE_MB=10
MAX_PAGES=100

# Kakao OAuth
KAKAO_CLIENT_ID=<REST API 키>
KAKAO_CLIENT_SECRET=<클라이언트 시크릿>
KAKAO_REDIRECT_URI=http://localhost:8001/api/v1/auth/kakao/callback

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
  defaultValue: 'http://localhost:8001',  // 로컬: IP 대신 localhost (와이파이 변경 무관)
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
6. **ID 형식**: 세션 `ses_{uuid.hex[:10]}`, 카드 `card_{uuid.hex[:8]}`, 유저 `usr_{uuid.hex[:10]}`, 폴더 `fld_{uuid.hex[:10]}`
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

### Phase 2.5: 백그라운드 카드 생성
- POST /generate 즉시 반환 (status=processing) + asyncio 백그라운드 생성
- 포그라운드/백그라운드 선택 UX (업로드 → 선택지 → 대기 or 홈 복귀)
- 포그라운드 대기: 원형 프로그레스(%) + 예상 시간 + 감성 문구 로테이션 → 완료 시 ReviewScreen 자동 이동
- 백그라운드 대기: 홈에서 10초 폴링 + 완료 시 스낵바 알림
- 세션 목록에 processing/failed 상태 UI (스피너/에러 아이콘)
- UTC 시간 버그 수정 (isoformat + "Z" 접미사)

### Phase 3: 보관함 + UX 개선
- **보관함 기능**: 폴더(과목)별 세션 관리 — CRUD + 6색 프리셋
- **바텀 네비게이션**: 홈/보관함 2탭 (IndexedStack 상태 유지)
- **보관함 저장 모달**: ChoiceChip 폴더 선택 + 새 과목 생성 + 자동 저장 옵션
- **자동 저장**: SharedPreferences 기반, 카드 생성 완료 시 마지막 폴더에 자동 저장
- **카드 검수 개선**: 전체 채택 + 전체 해제 + 카드별 되돌리기
- **이전 기록 5개 제한**: 홈 화면 세션 목록 최대 5개
- **보관함 로그인 전용**: 비로그인 유저는 보관함 탭에서 로그인 유도
- **테마 캐싱**: 다크/라이트 설정 SharedPreferences 저장·복원
- **이용 가이드**: 좌상단 ? 버튼 → 6단계 가이드 바텀시트

### Phase 3.5: 성능 최적화 + 안정성
- **검수 통합**: 별도 review_service 호출 제거, 생성 프롬프트에 교수 관점 자체검수 통합 (CLI 호출 4→3회)
- **Semaphore 3**: 청크 3개 동시 실행 가능 (기존 2)
- **JSON 강제 출력**: Claude CLI `--output-format json` 적용
- **재시도 로직**: JSON 파싱 실패 시 1회 자동 재시도 (MAX_RETRIES=2)
- **프로그레스 개선**: 90% 고정 → 99%까지 점근적 증가 (멈춤 현상 제거)
- **예상 시간 현실화**: pageCount×20 → pageCount×35 (clamp 90~900초)
- **업로드 진행률**: dio 패키지로 PDF 업로드 진행률 실시간 표시
- **localhost 기본값**: API URL을 localhost로 변경 (와이파이 IP 변경 시 수정 불필요)
- **SSH keepalive**: eupori-server에 ServerAliveInterval=30 설정 (SCP 끊김 방지)
- **동시 요청 테스트**: 5명 동시 → 5/5 성공 (재시도 2회 발동, 모두 복구)

### Phase 4: AI 자동 채택 + QA 검증 (현재)
- **AI 자동 채택**: 카드 생성 시 `recommend: true/false` → recommend=true 카드 자동 accepted (최소 10장 보장)
- **카드 수 안정화**: 프롬프트 "페이지당 3~5장" + MAX_CARDS=30 truncate (기존: "페이지당 1~3장, 최대 80장")
- **학습 필터**: 채택(accepted) 카드만 학습 대상 (기존: rejected 제외 전부)
- **학습 버튼**: "학습하기 (N장)" — 채택 카드 수 표시
- **재시도 보강**: MAX_RETRIES 2→3, 지수 백오프 (2/5/10초), 빈 응답·CLI 오류도 재시도
- **프로덕션 QA**: 20명 시뮬레이션 자동 테스트 — 97.1% → 재시도 보강 후 100% 통과
  - Group A (10명): Full E2E (업로드→생성→자동채택→수정→학습→CSV→삭제)
  - Group B (10명): 스트레스(3동시), 악성입력(SQL injection/XSS/빈파일), 데이터격리, 엣지케이스, 사이드이펙트

---

## 다음 작업 후보 (Phase 5~)

| 우선순위 | 작업 | 설명 |
|----------|------|------|
| 1 | 콘시어지 테스트 배포 | 테스터에게 링크 공유 + 피드백 폼 |
| 2 | APK 업데이트 | 자동 채택 반영된 Android APK 빌드 |
| 3 | Google Play Store 등록 | 앱 이름, 설명, 스크린샷 |
| 4 | SRS 반복학습 | 간격 반복 알고리즘 (SM-2 등) |
| 5 | 이메일 회원가입 | 카카오 없는 유저 대응 |
| 6 | Google/Apple 로그인 | 실제 구현 (현재 목업) |
| 7 | 큐 시스템 | 동시 사용자 20명+ 대응 (대기 순번 UI) |

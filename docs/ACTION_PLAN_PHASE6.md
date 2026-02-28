# Phase 6 작업 계획 — 수익화 전 필수 기반 구축

> 작성일: 2026-02-26
> 근거: `docs/PRODUCT_STRATEGY.md` (15인 분석 보고서)
> 목표: 4월 중간고사 시즌 전까지 "학습 앱"으로 전환

---

## 작업 총괄

| # | 작업 | 예상 소요 | 우선순위 | 상태 |
|---|------|-----------|----------|------|
| 1 | DB 백업 자동화 | 1시간 | 🔴 즉시 | ⬜ |
| 2 | 개인정보처리방침 작성 | 2시간 | 🔴 즉시 | ⬜ |
| 3 | 목업 로그인 버튼 제거 | 30분 | 🔴 즉시 | ⬜ |
| 4 | 샘플 PDF 원클릭 체험 | 3시간 | 🔴 즉시 | ⬜ |
| 5 | SRS (간격 반복) 구현 | 2주 | 🔴 핵심 | ⬜ |
| 6 | 학습 통계 기본 | 1주 | 🟡 중요 | ⬜ |
| 7 | 이벤트 로깅 체계 | 3일 | 🟡 중요 | ⬜ |
| 8 | Google/Apple 로그인 | 3일 | 🟡 중요 | ⬜ |

---

## 1. DB 백업 자동화 (1시간)

### 문제
- SQLite 단일 파일이 유일한 데이터 저장소
- 서버 장애 시 모든 사용자 데이터 소실
- 현재 백업 체계 **전무**

### 작업 내용
- cron 스케줄러로 SQLite DB 일별 자동 백업
- S3 버킷에 업로드 (최근 30일분 보관)
- 백업 실패 시 Slack 알림

### 파일
- `back/scripts/backup_db.sh` (신규)
- VPS crontab 설정

---

## 2. 개인정보처리방침 작성 (2시간)

### 문제
- Google Play Store 등록 필수 요건
- 카카오 OAuth 사용 시 법적 의무
- 현재 **문서 자체가 없음**

### 작업 내용
- 개인정보처리방침 웹페이지 작성
- 수집 항목: 카카오 닉네임/프로필, 디바이스 ID, 학습 기록
- PDF 파일 처리 정책 명시 (생성 완료 후 미보관)
- nginx 정적 페이지로 서빙 (`/privacy`)
- 앱 내 설정에서 링크 연결

### 파일
- `front/web/privacy.html` (신규)
- `back/` nginx 설정에 라우팅 추가

---

## 3. 목업 로그인 버튼 제거 (30분)

### 문제
- Google/Apple/이메일 로그인 버튼이 있으나 "준비 중입니다" 토스트만 표시
- 반복 노출 시 신뢰 하락

### 작업 내용
- `login_screen.dart`에서 카카오 외 목업 버튼 제거
- 카카오 로그인 버튼만 남기고, 하단에 "더 많은 로그인 방식이 추가될 예정입니다" 텍스트

### 파일
- `front/lib/screens/login_screen.dart`

---

## 4. 샘플 PDF 원클릭 체험 (3시간)

### 문제
- 현재 Time to Value = 3분 (PDF 선택 → 업로드 → 대기 → 확인)
- PDF가 없는 첫 사용자는 가치 체감 전에 이탈
- 고등학생 패널: "PDF가 없으면 시작을 못 함"

### 작업 내용
- 샘플 PDF 1~2개 준비 (예: "교육학개론 샘플 10페이지")
- 홈 화면에 "샘플로 체험하기" 버튼 추가
- 탭하면 즉시 카드 생성 시작 (업로드 과정 스킵)
- 또는 사전 생성된 샘플 세션을 보여주기 (서버 부하 없음)

### 파일
- `front/lib/screens/home_screen.dart` — 체험 버튼 추가
- `back/` — 샘플 세션 API 또는 사전 생성 데이터
- 샘플 PDF 파일 1~2개

### 설계 결정 필요
- [ ] 실시간 생성 vs 사전 생성 결과 보여주기 (서버 비용 vs 실감)
- [ ] 샘플 PDF 과목 선정 (교육학? 심리학? 한국사?)

---

## 5. SRS (간격 반복) 구현 (2주) — 핵심 작업

> 15인 전원 합의: "SRS 없으면 학습 앱이 아니다"

### 문제
- 현재 학습 = 플래시카드 한 번 넘기기 → 끝
- 반복학습/복습 스케줄 없음 → 매일 돌아올 이유 없음
- 경쟁사 3사 모두 SRS 보유 (Anki FSRS, Quizlet Scheduled Reviews, Brainscape CBR)
- 사용자 패널 3/4명이 최대 단점으로 지적

### 5-1. 백엔드 — 데이터 모델 + API

#### 새 테이블: `card_reviews`
```
id: String (PK)
card_id: String (FK → cards)
user_id: String (FK → users, nullable)
device_id: String
rating: Integer (1=Again, 2=Hard, 3=Good, 4=Easy)
interval_days: Float (다음 복습까지 간격)
ease_factor: Float (SM-2 난이도 계수, 기본 2.5)
due_date: DateTime (다음 복습 예정일)
reviewed_at: DateTime
```

#### 새 API 엔드포인트

| Method | Path | 설명 |
|--------|------|------|
| POST | `/api/v1/cards/{id}/review` | 카드 복습 결과 기록 (rating 1~4) |
| GET | `/api/v1/study/due` | 오늘 복습할 카드 목록 (due_date ≤ today) |
| GET | `/api/v1/study/stats` | 학습 통계 (총 복습, 마스터 카드, 스트릭) |

#### SRS 알고리즘
- **1단계: SM-2 기본 구현** (검증된 알고리즘, 구현 단순)
- 2단계 (데이터 축적 후): FSRS 전환 고려

#### SM-2 핵심 로직
```
rating 1 (Again): interval = 1일, ease_factor 감소
rating 2 (Hard): interval = interval × 1.2, ease_factor 소폭 감소
rating 3 (Good): interval = interval × ease_factor
rating 4 (Easy): interval = interval × ease_factor × 1.3
```

### 5-2. 프론트엔드

#### 홈 화면 변경
- "오늘 복습할 카드 N장" 배너 추가 (보관함에 저장된 카드 기준)
- 탭하면 복습 세션 시작

#### 학습 화면 변경 (`study_screen.dart`)
- 카드 뒷면 확인 후 4버튼 셀프 평가: **다시(1) / 어려움(2) / 좋음(3) / 쉬움(4)**
- 기존 "다음 카드" 넘기기 → 평가 후 넘기기로 변경
- 복습 완료 화면: "오늘 N장 복습 완료! 연속 M일 학습 중"

#### 학습 스트릭
- 연속 학습 일수 카운트
- 홈 화면에 스트릭 표시 (🔥 7일 연속)
- SharedPreferences에 마지막 학습일 저장

### 파일 목록

| 파일 | 변경 |
|------|------|
| `back/app/models.py` | CardReview 모델 + Pydantic 스키마 추가 |
| `back/app/database.py` | 마이그레이션 |
| `back/app/routes.py` | /review, /study/due, /study/stats 엔드포인트 |
| `back/app/srs_service.py` | SM-2 알고리즘 로직 (신규) |
| `front/lib/services/api_service.dart` | 복습/통계 API 호출 |
| `front/lib/screens/home_screen.dart` | "오늘의 복습" 위젯 + 스트릭 |
| `front/lib/screens/study_screen.dart` | 4단계 셀프 평가 UI |
| `front/lib/models/` | 복습/통계 모델 (신규) |

---

## 6. 학습 통계 기본 (1주)

### 작업 내용
- 총 학습 카드 수
- 기억률 (정답률 기반)
- 연속 학습일 (스트릭)
- 과목별(폴더별) 진도 %
- 홈 화면 또는 별도 통계 탭에 표시

### 의존성
- SRS (#5) 완료 후 구현 (복습 데이터 기반)

### 파일
- `front/lib/screens/stats_screen.dart` (신규) 또는 홈 화면 내 섹션
- `back/app/routes.py` — `/study/stats` 엔드포인트 (SRS와 함께)

---

## 7. 이벤트 로깅 체계 (3일)

### 문제
- 사용자 행동 데이터 수집 전무
- PMF 측정, 리텐션 분석, AI 품질 개선 불가

### 작업 내용
- `analytics_events` 테이블 생성
- 핵심 이벤트 10종 서버사이드 로깅:
  1. `pdf_uploaded` (파일 크기, 페이지 수)
  2. `cards_generated` (카드 수, 소요시간, 템플릿)
  3. `card_accepted` / `card_rejected` / `card_edited`
  4. `study_started` / `study_completed` (카드 수, 소요시간)
  5. `review_completed` (rating, 카드ID)
  6. `session_saved_to_library`
  7. `user_login` / `user_signup`

### 파일
- `back/app/models.py` — AnalyticsEvent 모델
- `back/app/analytics.py` — 로깅 유틸 (신규)
- `back/app/routes.py` — 각 엔드포인트에 이벤트 호출 추가

---

## 8. Google/Apple 로그인 (3일)

### 문제
- 카카오 로그인만 동작
- Google/Apple/이메일이 목업 → #3에서 제거
- 카카오 없는 유저(고등학생 등) 대응 필요

### 작업 내용
- Google OAuth 연동 (google_sign_in 패키지)
- Apple Sign In 연동 (sign_in_with_apple 패키지)
- 백엔드 `/auth/google/callback`, `/auth/apple/callback` 추가
- 기존 JWT 체계에 통합

### 파일
- `back/app/auth_routes.py` — Google/Apple OAuth 엔드포인트
- `front/lib/screens/login_screen.dart` — 실제 동작하는 버튼으로 교체
- `front/lib/services/auth_service.dart` — Google/Apple 로그인 로직

---

## 작업 순서 (권장)

```
Week 0 (즉시, 반나절):
  ├── #1 DB 백업 자동화 (1h)
  ├── #2 개인정보처리방침 (2h)
  └── #3 목업 버튼 제거 (30m)

Week 1:
  ├── #5-1 SRS 백엔드 (모델 + API + SM-2 로직)
  └── #4 샘플 PDF 체험 (홈 화면)

Week 2:
  ├── #5-2 SRS 프론트 (셀프 평가 + 오늘의 복습 + 스트릭)
  └── #7 이벤트 로깅 체계

Week 3:
  ├── #6 학습 통계 기본
  └── #8 Google/Apple 로그인

Week 4:
  └── 테스트 + 배포 + 에브리타임 마케팅 준비
```

---

## 완료 기준

- [ ] DB 백업이 매일 자동으로 S3에 저장됨
- [ ] 개인정보처리방침 페이지가 `/privacy`에서 접근 가능
- [ ] 로그인 화면에 목업 버튼 없음 (카카오만 또는 Google/Apple 추가)
- [ ] 홈 화면에서 샘플 PDF로 즉시 체험 가능
- [ ] 학습 시 1~4 등급 셀프 평가 → SRS 스케줄링 동작
- [ ] 홈에 "오늘 복습할 카드 N장" 표시
- [ ] 학습 스트릭 (연속 학습일) 표시
- [ ] 기본 학습 통계 (총 복습, 기억률, 스트릭) 표시
- [ ] 핵심 이벤트 10종이 DB에 자동 기록
- [ ] `flutter analyze` 에러 0

---

## 참고 문서

- `docs/PRODUCT_STRATEGY.md` — 15인 분석 종합 보고서
- `docs/COMPETITOR_ANALYSIS.md` — 경쟁사 분석 (Anki/Quizlet/Brainscape)
- `docs/BUSINESS.md` — 사업 계획서
- `CLAUDE.md` — 프로젝트 기술 가이드

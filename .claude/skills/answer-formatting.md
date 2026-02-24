# 답변 포매팅 스킬

학습 카드 답변(back) 텍스트의 가독성을 높이기 위한 포매팅 규칙 및 구현 참고.

## 현재 구현 위치

`front/lib/screens/study_screen.dart` — `_formatAnswer()`, `_buildBackContent()`, `_responsiveTextStyle()`

---

## 1. 자동 줄바꿈 규칙 (`_formatAnswer`)

| 패턴 | 동작 | 예시 |
|------|------|------|
| 온점(`.`) + 공백 | 온점 뒤 줄바꿈 | `~이다. 또한~` → `~이다.\n또한~` |
| `다` + 공백 (한국어 문장 종결) | 뒤에 줄바꿈 | `~한다. 이는~` → `~한다.\n이는~` |
| `1.` `2)` 등 번호 | 번호 앞 줄바꿈 | `항목 1. 내용` → `항목\n1. 내용` |
| `1단계` `2단계` | 단계 앞 줄바꿈 | `과정 1단계 분석` → `과정\n1단계 분석` |
| `①②③...⑩` 원문자 | 원문자 앞 줄바꿈 | `방법 ①수집 ②분석` → `방법\n①수집\n②분석` |
| `·` `-` `•` 항목 기호 | 기호 앞 줄바꿈 | `특징 · 빠름 · 정확` → `특징\n· 빠름\n· 정확` |
| 연속 줄바꿈 3개+ | 2개로 정리 | `\n\n\n` → `\n\n` |

### 한글 단어 기준 줄바꿈 (Word Joiner)

Flutter 기본 동작은 한글을 **글자 단위**로 줄바꿈하여 단어가 중간에 잘리는 문제 발생:
- Bad: `시작되는 시\n기.` / `안전과 초\n기 사회화를`
- Good: `시작되는\n시기.` / `안전과\n초기 사회화를`

**해결**: 각 단어 내 글자 사이에 Unicode Word Joiner(`\u2060`)를 삽입하여 공백에서만 줄바꿈되도록 강제:

```dart
result = result.split('\n').map((line) {
  return line.split(' ').map((word) {
    if (word.isEmpty) return word;
    return word.split('').join('\u2060');
  }).join(' ');
}).join('\n');
```

- 줄바꿈(`\n`)은 보존 (라인별 처리)
- 공백(` `)은 유효한 줄바꿈 지점으로 유지
- Word Joiner는 화면에 표시되지 않음 (zero-width)

### 주의사항
- 이미 줄바꿈이 있는 경우 중복 삽입 안 함 (`(?<!\n)` lookaround)
- 소수점(`3.14`) 오탐 가능성 있음 — 현재는 허용 (학습 카드 특성상 드묾)
- Word Joiner 처리는 반드시 모든 줄바꿈 규칙 적용 **이후** 마지막 단계에서 수행

---

## 2. 반응형 텍스트 크기 (`_responsiveTextStyle`)

질문(front) 텍스트 길이에 따라 폰트 크기 자동 조절:

| 텍스트 길이 | TextTheme | 대략 크기 |
|------------|-----------|----------|
| ≤ 20자 | `headlineSmall` | 24px |
| 21~80자 | `titleLarge` | 22px |
| 81자+ | `titleMedium` | 16px |

공통: `height: 1.6`, `fontWeight: w600`

---

## 3. 답변 텍스트 스타일 (`_buildBackContent`)

- **폰트**: `titleLarge` (22px), `fontWeight: w500`, `height: 1.8`
- **정렬**: 40자 이하 & 줄바꿈 없음 → `TextAlign.center`, 그 외 → `TextAlign.left`
- **줄바꿈**: `softWrap: true`, `overflow: TextOverflow.visible`
- **단어 간격**: `wordSpacing: 1.2`

---

## 4. 근거(evidence) 표시

- 카드 하단에 배치 (정답과 분리)
- 앞면: 힌트 텍스트 표시 (처음 2장만)
- 뒷면: 근거 컨테이너 표시
- 스타일: `bodySmall`, italic, `evidenceColor` 배경 (alpha 0.06)

---

## 5. 향후 개선 후보

- [ ] 마크다운 파싱 (볼드, 이탤릭 등)
- [ ] 콜론(`:`) 뒤 줄바꿈 (정의형 답변)
- [ ] 괄호 안 내용 축소 표시
- [ ] 답변 길이별 폰트 크기 반응형 (질문처럼)
- [ ] 테이블/비교형 답변 전용 레이아웃

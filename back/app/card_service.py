import asyncio
import json
import logging
from typing import List, Dict

from .config import settings
from .claude_cli import run_claude

logger = logging.getLogger(__name__)

TEMPLATE_INSTRUCTIONS = {
    "definition": """정의형 카드를 만드세요.
- 앞면: "OO란?", "OO의 정의는?", "OO을 설명하시오" 형태
- 뒷면: 간결하고 정확한 답변 (1~3문장)

예시:
- 앞면: "피아제의 감각운동기란?"
- 뒷면: "출생~2세, 감각과 운동을 통해 세계를 탐색하는 인지 발달 단계"
""",

    "cloze": """빈칸형 카드를 만드세요.
- 앞면: 문장에서 **핵심 전문 용어/개념**을 _____로 대체
- 뒷면: 빈칸에 들어갈 정답 (정확한 용어)

## 빈칸 규칙 (매우 중요)
1. 빈칸은 반드시 **시험에 출제될 핵심 전문 용어, 고유명사, 학술 개념**이어야 합니다.
2. "할 수", "있게", "하는" 같은 일반적인 조사/동사를 빈칸으로 만들지 마세요.
3. 빈칸의 정답이 **하나로 특정**되어야 합니다. 여러 답이 가능한 빈칸은 만들지 마세요.
4. 문장만 읽고도 정답을 유추할 수 있을 정도로 **충분한 맥락**을 포함하세요.

좋은 예시:
- 앞면: "피아제의 인지발달 단계 중 _____기는 출생부터 약 2세까지의 시기이다."
- 뒷면: "감각운동"

- 앞면: "에릭슨의 심리사회적 발달 이론에서 영아기의 핵심 과업은 _____이다."
- 뒷면: "기본적 신뢰감 대 불신감"

나쁜 예시 (절대 이렇게 만들지 마세요):
- 앞면: "효과적인 한계 설정을 위해 규칙은 _____ 유지되어야 한다." → 답이 여러 개 가능
- 앞면: "자아통제는 타인의 요구에 _____ 하는 수준이다." → 빈칸이 핵심 용어가 아님
""",

    "comparison": """비교형 카드를 만드세요.
- 앞면: 헷갈리기 쉬운 두 개념을 비교하는 질문
- 뒷면: 각 개념의 핵심 차이를 간결히 대비

예시:
- 앞면: "동화(assimilation) vs 조절(accommodation)의 차이점은?"
- 뒷면: "동화: 기존 스키마에 새 정보를 맞춤 / 조절: 새 정보에 맞게 스키마를 변경"
""",

    "subjective": """주관식(서술형) 카드를 만드세요.
- 앞면: 서술형 개방 질문 ("~를 서술하시오", "~의 과정을 설명하시오", "~의 의의를 논하시오")
- 뒷면: 모범답안 3~5문장 (핵심 키워드를 반드시 포함 — AI 채점 기준이 됩니다)

예시:
- 앞면: "피아제의 인지발달 이론에서 동화와 조절의 개념을 설명하고, 두 과정의 관계를 서술하시오."
- 뒷면: "동화(assimilation)란 새로운 정보를 기존의 인지 구조(스키마)에 맞추어 해석하는 과정이다. 조절(accommodation)은 기존 스키마로 설명할 수 없는 새 정보에 맞게 스키마를 수정하거나 새로 만드는 과정이다. 두 과정은 상호보완적이며, 동화와 조절의 균형을 통해 평형화(equilibration)가 이루어지고, 이것이 인지 발달의 핵심 원동력이 된다."
""",
}

MATH_SECTION = """
## 수학 수식 복원 (매우 중요)

이 텍스트는 PDF에서 자동 추출된 것으로, **수학 공식이 깨져 있을 수 있습니다.**
아래 패턴을 인식하고 정확한 수학 표기로 복원하세요:

**접합 단어 복원:**
- "Orthogonalmatrix" → "Orthogonal matrix"
- "A3-dimensionalvectorv" → "A 3-dimensional vector v"
- "0fori > j" → "0 for i > j"

**수식 기호 복원:**
- "QTQ=I" → "Q^T Q = I" (T는 전치 행렬)
- "R ij" → "R_{ij}" (아래첨자)
- "x2" 또는 "x 2" (문맥상 제곱) → "x²" 또는 "x^2"
- "Anx = λnx" → "A^n x = λ^n x"
- "UΣVT" → "UΣV^T"
- "v1,v2,v3" → "v₁, v₂, v₃"

**행렬/벡터 복원:**
- 공백으로 흩어진 숫자 행 ("3 2 5 / 4 0 4") → 행렬 원소로 해석
- 중괄호, 대괄호가 누락된 벡터 표기 복원

**카드 작성 시 수식 표기:**
- 간단한 수식: 유니코드 사용 (², ³, ₁, ₂, →, ≤, ≥, ≠, ∈, ∀, ∃)
- 복잡한 수식: LaTeX 표기 사용 (예: "∫₀¹ f(x)dx", "Σᵢ₌₁ⁿ aᵢ")
- 행렬: 텍스트로 명확하게 설명 (예: "[1 2; 3 4]는 2×2 행렬")

"""


# ── Step 2: 내용 분석 프롬프트 ──

def _build_analysis_prompt(is_math: bool = False) -> str:
    """5관점 통합 분석 시스템 프롬프트"""
    math_section = MATH_SECTION if is_math else ""

    return f"""당신은 5가지 전문가 관점을 통합한 학습 콘텐츠 분석가입니다.
{math_section}
## 분석 관점

### 1. 교수 관점 (출제자)
- 시험에 반드시 나올 핵심 개념/정의/공식
- "이건 시험에 낸다" 수준의 중요도 판별
- 학생들이 자주 틀리는 함정 포인트

### 2. 전공 교재 관점 (학문적 정확성)
- 용어의 정확한 학술적 정의
- 개념 간 위계 구조와 선후 관계
- 전공 분야에서 합의된 핵심 원리

### 3. 유명 강사 관점 (설명력)
- 복잡한 개념을 쉽게 풀어내는 핵심 비유/예시
- "이것만 기억하면 된다" 식의 압축 포인트
- 학생 눈높이의 설명 방식

### 4. 문제 출제자 관점 (변별력)
- 헷갈리기 쉬운 유사 개념 쌍 (비교형 적합)
- 빈칸으로 만들었을 때 답이 하나로 특정되는 핵심 용어
- 단계/분류/유형을 묻는 포인트

### 5. 학생 관점 (학습 효율)
- 이해하기 어려운 부분 (추가 설명 필요)
- 암기 부담이 큰 항목 (니모닉/연상 가능?)
- 실제 시험에서 시간 압박 하에 떠올릴 수 있는 수준

## 분석 지침
- **손글씨 메모/필기**가 있으면 강의 보충 자료로 간주하고 적극 분석하세요.
  (단, 낙서·낙서체·학습과 무관한 메모는 무시)
- 텍스트가 슬라이드/요약형이면 키워드에서 **숨겨진 의미**를 추론하세요.
- 표지, 목차만 있는 경우 빈 결과를 반환하세요.

## 출력 형식 (가장 중요)
반드시 JSON만 출력하세요. 다른 텍스트, 설명, 마크다운을 추가하지 마세요.
계획을 작성하지 마세요. 질문하지 마세요. 첫 글자가 반드시 `{{` 이어야 합니다.

{{
  "subject": "과목/단원명",
  "key_concepts": [
    {{
      "concept": "개념명",
      "definition": "정확한 정의 (교재 관점)",
      "why_important": "왜 시험에 나오는지 (교수 관점)",
      "exam_type": "definition|cloze|comparison",
      "confusion_pairs": ["혼동되는 개념"],
      "key_terms": ["빈칸 적합 핵심 용어"],
      "simple_explanation": "쉬운 설명 (강사 관점)",
      "source_page": 페이지번호,
      "evidence": "원문 근거"
    }}
  ],
  "comparison_pairs": [
    {{
      "concept_a": "A",
      "concept_b": "B",
      "key_differences": ["차이점1", "차이점2"],
      "source_page": 페이지번호
    }}
  ],
  "cloze_candidates": [
    {{
      "sentence": "빈칸으로 만들 원문 문장",
      "blank_term": "빈칸 정답 (핵심 용어만)",
      "source_page": 페이지번호
    }}
  ]
}}"""


# ── Step 3: 카드 생성 프롬프트 ──

def _build_card_creation_prompt(template_type: str) -> str:
    """분석 기반 카드 생성 시스템 프롬프트"""
    template_guide = TEMPLATE_INSTRUCTIONS.get(template_type, TEMPLATE_INSTRUCTIONS["definition"])

    return f"""당신은 최적의 암기카드를 만드는 전문가입니다.

## 입력
1. 전문가 분석 결과 (JSON) — 5관점 통합 분석
2. 원문 텍스트 — 근거 확인용

## Wozniak의 효과적 학습카드 원칙
- **최소 정보 원칙**: 한 카드 = 한 개념. 복합 질문 금지
- **빈칸 삭제 우선**: 문장 속 핵심 용어를 빈칸으로 → 문맥 기억 강화
- **중복 허용**: 같은 개념을 다른 각도(정의/빈칸/비교)로 물으면 기억 강화
- **구체적 질문**: "설명하시오" 대신 "X의 3가지 특징은?"

## 템플릿 규칙

{template_guide}

## 카드 생성 규칙

1. **근거 필수**: 원문에서 발췌한 근거(evidence)를 1~2문장으로 포함. 근거 없는 카드는 만들지 마세요.
2. **페이지 번호 필수**: 근거의 출처 페이지를 정확히 표기.
3. **한 카드 = 한 개념**: 하나의 카드는 하나의 개념만 테스트.
4. **언어**: 원문 언어와 동일하게 작성 (한국어 원문 → 한국어 카드).
5. **카드 수**: 분석의 key_concepts 각각 최소 1장. 페이지당 4~7장.
   텍스트가 짧아도(슬라이드, 요약, 필기) 개념이 있으면 반드시 카드를 만드세요.
6. **난이도 태그**: easy(기본 개념), medium(응용), hard(심화/비교).

## 채택 판단 (recommend 필드)

분석에서 why_important가 강한 개념 → recommend: true
**가중치 판단 기준:**
- **출제 가능성**: 시험에 실제로 나올 확률이 높은가?
- **학습 효율**: 이 카드를 암기하면 시험 점수에 직접 도움이 되는가?
- **개념 핵심도**: 해당 과목/단원의 뼈대가 되는 개념인가?
- **독립성**: 다른 카드와 중복되거나 지나치게 유사하지 않은가?
- recommend: true → 위 기준에서 2개 이상 해당하는 핵심 카드
- recommend: false → 보충 학습용, 세부사항, 또는 다른 카드와 유사한 카드
- 전체 카드 중 **60~75%** 를 recommend: true로 설정하세요.

## 자체 검수 (출력 전 필수)

출력 전 모든 카드를 검수하세요:
- 원문 evidence와 **사실적으로 일치**하는가?
- 답이 **학술적으로 정확**한가?
- 빈칸형: 정답이 하나로 특정되는가? 핵심 용어인가?
- 비교형: 실제로 헷갈리는 쌍인가?
- 부정확한 카드 → 수정 또는 제외

## 출력 형식 (가장 중요)

반드시 JSON 배열만 출력하세요. 다른 텍스트, 설명, 마크다운을 추가하지 마세요.
학습 내용이 전혀 없는 경우(표지, 목차만)에만 빈 배열 []을 출력하세요.

**절대 금지:**
- 계획을 작성하지 마세요 (Plan Mode 금지)
- 질문하거나 확인을 요청하지 마세요
- 분석 과정을 텍스트로 설명하지 마세요
- JSON 배열 외의 어떤 텍스트도 출력하지 마세요
첫 글자가 반드시 `[` 이어야 합니다.

[
  {{
    "front": "질문 또는 빈칸 문장",
    "back": "정답 또는 설명",
    "evidence": "원문에서 발췌한 근거 문장",
    "evidence_page": 페이지번호,
    "tags": "type:{template_type}, difficulty:easy|medium|hard",
    "recommend": true
  }}
]"""


def _build_user_prompt(pages: List[Dict]) -> str:
    parts = []
    for page in pages:
        parts.append(f"=== 페이지 {page['page_num']} ===\n{page['text']}")
    return "\n\n".join(parts)


def _parse_analysis_json(text: str) -> dict:
    """분석 결과 JSON 파싱 (key_concepts, comparison_pairs, cloze_candidates)"""
    content = text.strip()

    if "```json" in content:
        content = content.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in content:
        content = content.split("```", 1)[1].split("```", 1)[0]

    start = content.find("{")
    end = content.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("분석 JSON 객체를 찾을 수 없습니다.")

    result = json.loads(content[start:end + 1])

    # 최소 구조 검증
    if "key_concepts" not in result:
        result["key_concepts"] = []
    if "comparison_pairs" not in result:
        result["comparison_pairs"] = []
    if "cloze_candidates" not in result:
        result["cloze_candidates"] = []

    return result


def _parse_cards_json(text: str) -> List[Dict]:
    """Claude 응답에서 JSON 카드 배열을 추출합니다."""
    content = text.strip()

    if "```json" in content:
        content = content.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in content:
        content = content.split("```", 1)[1].split("```", 1)[0]

    start = content.find("[")
    end = content.rfind("]")
    if start == -1 or end == -1:
        raise ValueError("JSON 배열을 찾을 수 없습니다.")

    return json.loads(content[start:end + 1])


def _validate_cards(cards_raw: List[Dict], template_type: str) -> List[Dict]:
    """파싱된 카드 원본에서 필수 필드를 검증하고 정규화합니다."""
    validated = []
    required_keys = ("front", "back", "evidence", "evidence_page")
    for i, card in enumerate(cards_raw):
        missing = [k for k in required_keys if k not in card]
        if missing:
            logger.warning("카드 검증 실패 [%d/%d]: 누락 필드 %s | card keys=%s",
                           i, len(cards_raw), missing, list(card.keys()))
            continue
        try:
            validated.append({
                "front": str(card["front"]).strip(),
                "back": str(card["back"]).strip(),
                "evidence": str(card["evidence"]).strip(),
                "evidence_page": int(card["evidence_page"]),
                "tags": str(card.get("tags", f"type:{template_type}")),
                "template_type": template_type,
                "recommend": bool(card.get("recommend", True)),
            })
        except (ValueError, TypeError) as e:
            logger.warning("카드 검증 예외 [%d/%d]: %s | card=%s", i, len(cards_raw), e, card)
    return validated


MAX_RETRIES = 3  # 최초 1회 + 재시도 2회
RETRY_DELAYS = [2, 5, 10]  # 재시도 간 대기 (초)


async def _run_cli_with_retry(
    system_prompt: str, user_prompt: str,
    chunk_idx: int, step_name: str,
    session_id: str | None = None,
) -> str:
    """CLI 호출 + 재시도 공통 로직. 원본 텍스트 반환."""
    last_error = None
    raw_text = ""
    for attempt in range(MAX_RETRIES):
        try:
            raw_text = await run_claude(system_prompt, user_prompt, model=settings.LLM_MODEL, session_id=session_id)
            if not raw_text or not raw_text.strip():
                raise ValueError("빈 응답")
            return raw_text
        except Exception as e:
            last_error = e
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
                logger.warning("청크 #%d %s 오류 (시도 %d/%d, %ds 후): %s: %s",
                               chunk_idx, step_name, attempt + 1, MAX_RETRIES, delay, type(e).__name__, e)
                await asyncio.sleep(delay)
            else:
                logger.error("청크 #%d %s 최종 실패: %s: %s", chunk_idx, step_name, type(e).__name__, e)
                raise
    raise last_error  # unreachable but satisfies type checker


async def _analyze_chunk(
    pages: List[Dict], chunk_idx: int,
    session_id: str | None = None, is_math: bool = False,
) -> dict:
    """Step 2: 5관점 통합 분석 (CLI 1회)"""
    system_prompt = _build_analysis_prompt(is_math=is_math)
    user_prompt = _build_user_prompt(pages)

    page_nums = [p["page_num"] for p in pages]
    total_text_len = sum(len(p["text"]) for p in pages)
    logger.info("청크 #%d 분석 시작: pages=%s, 텍스트=%d자", chunk_idx, page_nums, total_text_len)

    raw_text = await _run_cli_with_retry(system_prompt, user_prompt, chunk_idx, "분석", session_id=session_id)

    # JSON 파싱 재시도
    last_error = None
    for attempt in range(MAX_RETRIES):
        try:
            analysis = _parse_analysis_json(raw_text)
            concept_count = len(analysis.get("key_concepts", []))
            comparison_count = len(analysis.get("comparison_pairs", []))
            cloze_count = len(analysis.get("cloze_candidates", []))
            logger.info("청크 #%d 분석 완료: 핵심개념 %d개, 비교쌍 %d개, 빈칸후보 %d개",
                        chunk_idx, concept_count, comparison_count, cloze_count)
            return analysis
        except (ValueError, json.JSONDecodeError) as e:
            last_error = e
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
                logger.warning("청크 #%d 분석 JSON 파싱 실패 (시도 %d/%d, %ds 후): %s | 앞 300자: %s",
                               chunk_idx, attempt + 1, MAX_RETRIES, delay, e, raw_text[:300])
                await asyncio.sleep(delay)
                # CLI 재호출
                raw_text = await _run_cli_with_retry(system_prompt, user_prompt, chunk_idx, "분석(재)", session_id=session_id)
            else:
                logger.error("청크 #%d 분석 JSON 최종 실패: %s | 앞 500자: %s", chunk_idx, e, raw_text[:500])
                raise
    raise last_error


async def _create_cards_from_analysis(
    analysis: dict, pages: List[Dict],
    template_type: str, chunk_idx: int,
    session_id: str | None = None,
) -> List[Dict]:
    """Step 3: 분석 기반 카드 생성 (CLI 1회)"""
    system_prompt = _build_card_creation_prompt(template_type)

    # 분석 JSON + 원문을 함께 전달
    source_text = _build_user_prompt(pages)
    analysis_text = json.dumps(analysis, ensure_ascii=False, indent=2)

    user_prompt = f"""## 전문가 분석 결과
{analysis_text}

## 원문 텍스트 (근거 확인용)
{source_text}"""

    logger.info("청크 #%d 카드 생성 시작: 분석 기반", chunk_idx)

    raw_text = await _run_cli_with_retry(system_prompt, user_prompt, chunk_idx, "카드생성", session_id=session_id)

    # JSON 파싱 재시도
    last_error = None
    for attempt in range(MAX_RETRIES):
        try:
            cards_raw = _parse_cards_json(raw_text)
            logger.info("청크 #%d 카드 파싱 성공: %d장", chunk_idx, len(cards_raw))
            return _validate_cards(cards_raw, template_type)
        except (ValueError, json.JSONDecodeError) as e:
            last_error = e
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_DELAYS[min(attempt, len(RETRY_DELAYS) - 1)]
                logger.warning("청크 #%d 카드 JSON 파싱 실패 (시도 %d/%d, %ds 후): %s | 앞 300자: %s",
                               chunk_idx, attempt + 1, MAX_RETRIES, delay, e, raw_text[:300])
                await asyncio.sleep(delay)
                raw_text = await _run_cli_with_retry(system_prompt, user_prompt, chunk_idx, "카드생성(재)", session_id=session_id)
            else:
                logger.error("청크 #%d 카드 JSON 최종 실패: %s | 앞 500자: %s", chunk_idx, e, raw_text[:500])
                raise
    raise last_error


async def _generate_chunk(
    pages: List[Dict], template_type: str,
    chunk_idx: int = 0, session_id: str | None = None,
    is_math: bool = False,
) -> List[Dict]:
    """3단계 파이프라인: 분석(CLI 1회) → 카드 생성(CLI 1회). 검수는 카드 생성 프롬프트에 내장."""
    # Step 2: 내용 분석
    analysis = await _analyze_chunk(pages, chunk_idx, session_id=session_id, is_math=is_math)

    # 분석 결과가 비어있으면 (표지/목차만 있는 경우) 빈 리스트 반환
    if not analysis.get("key_concepts") and not analysis.get("comparison_pairs") and not analysis.get("cloze_candidates"):
        logger.info("청크 #%d: 분석 결과 비어있음 (표지/목차), 카드 생성 건너뜀", chunk_idx)
        return []

    # Step 3: 카드 생성
    cards = await _create_cards_from_analysis(analysis, pages, template_type, chunk_idx, session_id=session_id)

    if not cards:
        logger.warning("청크 #%d: 분석은 성공했으나 카드 0장 생성", chunk_idx)

    logger.info("청크 #%d 파이프라인 완료: %d장", chunk_idx, len(cards))
    return cards


MIN_RECOMMEND = 10
MAX_CARDS = 120
CHUNK_SIZE = 5  # 5페이지씩 분할


async def generate_cards(
    pages: List[Dict],
    template_type: str = "definition",
    session_id: str | None = None,
    on_progress=None,
    is_math: bool = False,
) -> List[Dict]:
    """PDF 텍스트에서 Claude를 이용해 암기카드를 생성합니다. 3단계 파이프라인 (분석→카드생성)."""
    total_text_len = sum(len(p["text"]) for p in pages)
    logger.info("카드 생성 시작: %d페이지, 총 %d자, 템플릿=%s", len(pages), total_text_len, template_type)

    if len(pages) <= CHUNK_SIZE:
        chunks_list = [pages]
    else:
        # 5페이지씩 분할 후, 텍스트가 너무 적은 청크는 이전 청크에 합침
        raw_chunks = [pages[i:i + CHUNK_SIZE] for i in range(0, len(pages), CHUNK_SIZE)]
        MIN_CHUNK_CHARS = 200
        chunks_list: List[List[Dict]] = []
        for chunk in raw_chunks:
            chunk_len = sum(len(p["text"]) for p in chunk)
            if chunks_list and chunk_len < MIN_CHUNK_CHARS:
                chunks_list[-1].extend(chunk)
                logger.info("짧은 청크 (%d자, %d페이지) → 이전 청크에 병합", chunk_len, len(chunk))
            else:
                chunks_list.append(list(chunk))
        logger.info("PDF %d페이지 → %d청크 병렬 처리", len(pages), len(chunks_list))

    total_chunks = len(chunks_list)
    if on_progress:
        await on_progress(completed_chunks=0, total_chunks=total_chunks, phase="generating")

    if total_chunks == 1:
        result = await _generate_chunk(chunks_list[0], template_type, chunk_idx=0, session_id=session_id, is_math=is_math)
        if on_progress:
            await on_progress(completed_chunks=1, total_chunks=total_chunks, phase="generating")
    else:
        # 실시간 진행률: 각 청크 완료 시마다 콜백 호출
        _completed_count = 0
        _progress_lock = asyncio.Lock()
        result = []
        failed_chunks = 0

        async def _chunk_with_progress(chunk, idx):
            nonlocal _completed_count, failed_chunks
            try:
                cards = await _generate_chunk(chunk, template_type, chunk_idx=idx, session_id=session_id, is_math=is_math)
                logger.info("청크 #%d 결과: %d장", idx, len(cards))
                return cards
            except Exception as e:
                logger.error("청크 #%d 예외 실패: %s: %s", idx, type(e).__name__, e)
                return e
            finally:
                async with _progress_lock:
                    _completed_count += 1
                    if on_progress:
                        await on_progress(completed_chunks=_completed_count, total_chunks=total_chunks, phase="generating")

        tasks = [_chunk_with_progress(chunk, i) for i, chunk in enumerate(chunks_list)]
        results = await asyncio.gather(*tasks)

        for i, r in enumerate(results):
            if isinstance(r, Exception):
                failed_chunks += 1
            else:
                result.extend(r)

        if failed_chunks > 0:
            logger.warning("전체 %d청크 중 %d개 실패, %d장 수집", len(chunks_list), failed_chunks, len(result))

    if not result:
        if total_chunks > 1:
            raise ValueError(f"전체 {total_chunks}개 청크 모두 실패했습니다. PDF 내용을 확인해주세요.")
        raise ValueError("생성된 카드가 없습니다. PDF 내용을 확인해주세요.")

    # MAX_CARDS 초과 시 truncate
    if len(result) > MAX_CARDS:
        result = result[:MAX_CARDS]

    # recommend=true 카드 자동 채택 (최소 10장 보장)
    recommended = [c for c in result if c.get("recommend", False)]
    if len(recommended) < MIN_RECOMMEND:
        non_rec = [c for c in result if not c.get("recommend", False)]
        recommended.extend(non_rec[:MIN_RECOMMEND - len(recommended)])
    rec_set = set(id(c) for c in recommended)
    for c in result:
        c["status"] = "accepted" if id(c) in rec_set else "pending"

    if not result:
        raise ValueError("생성된 카드가 없습니다. PDF 내용을 확인해주세요.")

    logger.info("최종 카드: %d장 (3단계 파이프라인 완료)", len(result))
    return result

import asyncio
import json
import logging
from typing import List, Dict

from .config import settings
from .claude_cli import run_claude
from .review_service import review_cards

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


def _build_system_prompt(template_type: str) -> str:
    template_guide = TEMPLATE_INSTRUCTIONS.get(template_type, TEMPLATE_INSTRUCTIONS["definition"])

    return f"""당신은 시험 대비 암기카드를 만드는 전문가입니다.
주어진 PDF 텍스트를 분석하여 시험에 나올 핵심 내용으로 암기카드를 생성합니다.

## 카드 유형
{template_guide}

## 규칙 (반드시 준수)

1. **근거 필수**: 모든 카드에 원문에서 발췌한 근거(evidence)를 포함하세요.
   - 근거가 불확실하면 해당 카드를 만들지 마세요.
   - 근거는 원문 그대로 인용, 1~2문장으로 제한하세요.

2. **페이지 번호 필수**: 근거가 어느 페이지에서 나왔는지 정확히 표기하세요.

3. **한 카드 = 한 개념**: 하나의 카드는 하나의 개념만 테스트하세요.

4. **언어**: 원문 언어와 동일하게 카드를 만드세요 (한국어 원문 → 한국어 카드).

5. **카드 수**: 페이지당 1~3장 정도. 내용이 적으면 더 적게, 많으면 더 많이 만드세요.
   단, 전체 최대 80장을 넘기지 마세요.

6. **난이도 태그**: easy(기본 개념), medium(응용), hard(심화/비교)로 분류하세요.

## 출력 형식

반드시 아래 JSON 배열만 출력하세요. 다른 텍스트, 설명, 마크다운 코드블록을 추가하지 마세요.

[
  {{
    "front": "질문 또는 빈칸 문장",
    "back": "정답 또는 설명",
    "evidence": "원문에서 발췌한 근거 문장",
    "evidence_page": 페이지번호,
    "tags": "type:{template_type}, difficulty:easy|medium|hard"
  }}
]"""


def _build_user_prompt(pages: List[Dict]) -> str:
    parts = []
    for page in pages:
        parts.append(f"=== 페이지 {page['page_num']} ===\n{page['text']}")
    return "\n\n".join(parts)


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


async def _generate_chunk(pages: List[Dict], template_type: str) -> List[Dict]:
    """페이지 청크 하나에 대해 카드를 생성합니다."""
    system_prompt = _build_system_prompt(template_type)
    user_prompt = _build_user_prompt(pages)

    raw_text = await run_claude(system_prompt, user_prompt, model=settings.LLM_MODEL)
    cards_raw = _parse_cards_json(raw_text)

    validated = []
    for card in cards_raw:
        if not all(k in card for k in ("front", "back", "evidence", "evidence_page")):
            logger.warning("필수 필드 누락 카드 스킵: %s", card)
            continue
        validated.append({
            "front": str(card["front"]).strip(),
            "back": str(card["back"]).strip(),
            "evidence": str(card["evidence"]).strip(),
            "evidence_page": int(card["evidence_page"]),
            "tags": str(card.get("tags", f"type:{template_type}")),
            "template_type": template_type,
        })

    return validated


CHUNK_SIZE = 5  # 5페이지씩 분할


async def generate_cards(pages: List[Dict], template_type: str = "definition") -> List[Dict]:
    """PDF 텍스트에서 Claude를 이용해 암기카드를 생성합니다. 청크 병렬 처리 + 3단계 검수."""
    if len(pages) <= CHUNK_SIZE:
        result = await _generate_chunk(pages, template_type)
    else:
        chunks = [pages[i:i + CHUNK_SIZE] for i in range(0, len(pages), CHUNK_SIZE)]
        logger.info("PDF %d페이지 → %d청크 병렬 처리", len(pages), len(chunks))

        tasks = [_generate_chunk(chunk, template_type) for chunk in chunks]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        result = []
        for r in results:
            if isinstance(r, Exception):
                logger.warning("청크 처리 실패: %s", r)
                continue
            result.extend(r)

    if not result:
        raise ValueError("생성된 카드가 없습니다. PDF 내용을 확인해주세요.")

    # 3단계 페르소나 검수 (교수 → 출제위원 → 수험생)
    source_text = _build_user_prompt(pages)
    logger.info("카드 검수 시작: %d장", len(result))
    result = await review_cards(result, source_text, template_type)

    if not result:
        raise ValueError("검수 후 유효한 카드가 없습니다. PDF 내용을 확인해주세요.")

    logger.info("최종 카드: %d장 (검수 완료)", len(result))
    return result

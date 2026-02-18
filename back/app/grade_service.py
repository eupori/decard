import json
import logging
import os
import tempfile

from .config import settings
from .claude_cli import run_claude

logger = logging.getLogger(__name__)

GRADE_SYSTEM_PROMPT = """당신은 시험 답안 채점 전문가입니다.
학생의 답안을 모범답안과 비교하여 채점합니다.

## 채점 기준

1. **correct** (정답): 핵심 키워드와 개념이 모두 포함되고, 논리적으로 올바른 경우
2. **partial** (부분 정답): 일부 핵심 키워드/개념은 맞지만 누락되거나 부정확한 부분이 있는 경우
3. **incorrect** (오답): 핵심 개념이 대부분 빠져있거나 틀린 경우

## 출력 형식

반드시 아래 JSON만 출력하세요. 다른 텍스트를 추가하지 마세요.

{
  "score": "correct 또는 partial 또는 incorrect",
  "feedback": "채점 피드백 2~3문장. 맞은 부분과 틀린/부족한 부분을 구체적으로 설명."
}"""


async def grade_answer(
    question: str,
    model_answer: str,
    user_answer: str,
    drawing_image: bytes | None = None,
) -> dict:
    """학생 답안을 AI로 채점합니다."""

    tmp_path = None
    tools = ""
    user_prompt_parts = []

    # 손글씨 이미지가 있으면 임시 파일로 저장 후 Read 도구로 전달
    if drawing_image:
        tmp = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
        tmp.write(drawing_image)
        tmp.close()
        tmp_path = tmp.name
        user_prompt_parts.append(
            f"첨부된 이미지 파일({tmp_path})은 학생이 손글씨로 작성한 답안입니다. "
            "이미지의 텍스트를 인식하여 아래 텍스트 답안과 합쳐서 채점해주세요.\n"
        )
        tools = "Read"

    user_prompt_parts.append(
        f"## 질문\n{question}\n\n"
        f"## 모범답안\n{model_answer}\n\n"
        f"## 학생 답안 (텍스트)\n{user_answer if user_answer.strip() else '(텍스트 답안 없음)'}\n\n"
        "위 학생 답안을 모범답안과 비교하여 채점해주세요."
    )

    try:
        raw_text = await run_claude(
            GRADE_SYSTEM_PROMPT,
            "\n\n".join(user_prompt_parts),
            model=settings.LLM_MODEL,
            tools=tools,
        )
        result = _parse_grade_json(raw_text)
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass

    # 유효성 검증
    if result.get("score") not in ("correct", "partial", "incorrect"):
        result["score"] = "partial"
    if not result.get("feedback"):
        result["feedback"] = "채점 결과를 확인해주세요."

    return result


def _parse_grade_json(text: str) -> dict:
    """Claude 응답에서 JSON 채점 결과를 추출합니다."""
    content = text.strip()

    # 마크다운 코드블록 제거
    if "```json" in content:
        content = content.split("```json", 1)[1].split("```", 1)[0]
    elif "```" in content:
        content = content.split("```", 1)[1].split("```", 1)[0]

    # { 로 시작하는 JSON 객체 찾기
    start = content.find("{")
    end = content.rfind("}")
    if start == -1 or end == -1:
        raise ValueError("JSON 객체를 찾을 수 없습니다.")

    return json.loads(content[start:end + 1])

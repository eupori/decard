import asyncio
import logging
import os

from .config import settings

logger = logging.getLogger(__name__)


async def run_claude(
    system_prompt: str,
    user_prompt: str,
    model: str | None = None,
    tools: str = "",
) -> str:
    """Claude Code CLI `-p` 모드로 AI 호출. API 키 불필요."""

    cmd = ["claude", "-p", "--output-format", "text"]

    if system_prompt:
        cmd += ["--system-prompt", system_prompt]
    if model:
        cmd += ["--model", model]

    # tools 플래그: 값이 있을 때만 추가
    if tools:
        cmd += ["--tools", tools]

    # 중첩 실행 차단 우회: CLAUDE_CODE 관련 env 키 제거
    env = {k: v for k, v in os.environ.items() if not k.startswith("CLAUDECODE")}

    logger.debug("CLI 실행: %s", " ".join(cmd))

    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdin=asyncio.subprocess.PIPE,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
    )

    try:
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=user_prompt.encode("utf-8")),
            timeout=settings.CLAUDE_TIMEOUT_SECONDS,
        )
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        raise RuntimeError(f"Claude CLI 타임아웃 ({settings.CLAUDE_TIMEOUT_SECONDS}초)")

    if proc.returncode != 0:
        err_msg = stderr.decode("utf-8", errors="replace").strip()
        logger.error("Claude CLI 오류 (code %d): %s", proc.returncode, err_msg)
        raise RuntimeError(f"Claude CLI 실패 (code {proc.returncode}): {err_msg}")

    result = stdout.decode("utf-8").strip()
    logger.debug("CLI 응답 길이: %d chars", len(result))
    return result

import asyncio
import logging
import os
import psutil

from .config import settings

logger = logging.getLogger(__name__)

# Claude CLI는 Node.js 프로세스 — 동시 실행 수 제한 (메모리 보호)
_cli_semaphore = asyncio.Semaphore(5)

MEMORY_WARN_MB = 150  # 가용 메모리가 이 이하면 Slack 경고
_memory_alert_sent = False  # 중복 알림 방지


def _check_memory() -> dict:
    """시스템 메모리 상태를 반환합니다."""
    mem = psutil.virtual_memory()
    return {
        "total_mb": round(mem.total / 1024 / 1024),
        "available_mb": round(mem.available / 1024 / 1024),
        "percent_used": mem.percent,
    }


async def _warn_if_low_memory():
    """가용 메모리가 임계값 이하면 Slack 경고를 보냅니다."""
    global _memory_alert_sent
    mem = _check_memory()
    if mem["available_mb"] < MEMORY_WARN_MB and not _memory_alert_sent:
        _memory_alert_sent = True
        from .slack import send_slack_alert
        await send_slack_alert(
            "메모리 부족 경고",
            f"가용 메모리: {mem['available_mb']}MB / 전체: {mem['total_mb']}MB ({mem['percent_used']}% 사용)\n"
            f"Semaphore=5, CLI 동시 실행 수를 줄이는 것을 검토하세요.",
            "warn",
        )
        logger.warning("메모리 부족 경고: %s", mem)
    elif mem["available_mb"] >= MEMORY_WARN_MB * 2:
        _memory_alert_sent = False  # 메모리 회복 시 알림 리셋


async def run_claude(
    system_prompt: str,
    user_prompt: str,
    model: str | None = None,
    tools: str = "",
) -> str:
    """Claude Code CLI `-p` 모드로 AI 호출. JSON 출력 강제."""
    import json

    cmd = ["claude", "-p", "--output-format", "json"]

    if system_prompt:
        cmd += ["--system-prompt", system_prompt]
    if model:
        cmd += ["--model", model]

    # tools 플래그: 값이 있을 때만 추가
    if tools:
        cmd += ["--tools", tools]

    # 중첩 실행 차단 우회: CLAUDECODE 키만 제거
    # CLAUDE_CODE_OAUTH_TOKEN 등 인증 관련 env는 유지
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    logger.debug("CLI 실행 대기: %s", " ".join(cmd))

    async with _cli_semaphore:
        await _warn_if_low_memory()
        raw = await _run_cli(cmd, env, user_prompt)

    # --output-format json → {"type":"result","result":"..."}
    try:
        parsed = json.loads(raw)
        return parsed.get("result", raw)
    except (json.JSONDecodeError, AttributeError):
        return raw


async def _run_cli(cmd: list, env: dict, user_prompt: str) -> str:
    logger.debug("CLI 실행 시작")

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
    if not result:
        err_hint = stderr.decode("utf-8", errors="replace").strip()[:200]
        raise RuntimeError(f"Claude CLI 빈 응답 (stderr: {err_hint or 'none'})")
    logger.debug("CLI 응답 길이: %d chars", len(result))
    return result

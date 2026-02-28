import asyncio
import logging
import os
import psutil

from .config import settings

logger = logging.getLogger(__name__)

# 글로벌 Semaphore (서버 전체 동시 CLI 수)
MAX_CONCURRENT_CLI = settings.MAX_CONCURRENT_CLI
_cli_semaphore = asyncio.Semaphore(MAX_CONCURRENT_CLI)

# 세션별 Semaphore (한 세션이 글로벌 슬롯 독점 방지)
MAX_CLI_PER_SESSION = settings.MAX_CLI_PER_SESSION
_session_semaphores: dict[str, asyncio.Semaphore] = {}


def _get_session_semaphore(session_id: str) -> asyncio.Semaphore:
    if session_id not in _session_semaphores:
        _session_semaphores[session_id] = asyncio.Semaphore(MAX_CLI_PER_SESSION)
    return _session_semaphores[session_id]


def release_session_semaphore(session_id: str):
    """세션 완료 후 세션 semaphore 정리."""
    _session_semaphores.pop(session_id, None)


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
    session_id: str | None = None,
) -> str:
    """Claude Code CLI `-p` 모드로 AI 호출. JSON 출력 강제."""
    import json

    cmd = ["claude", "-p", "--output-format", "json", "--permission-mode", "default"]

    if system_prompt:
        cmd += ["--system-prompt", system_prompt]
    if model:
        cmd += ["--model", model]

    # tools 플래그: 값이 있을 때만 추가
    if tools:
        cmd += ["--tools", tools]

    # 중첩 실행 차단 우회 + plan mode 전파 방지
    # CLAUDECODE 제거: 중첩 실행 차단 우회
    # CLAUDE_CODE_OAUTH_TOKEN 등 인증 관련 env는 유지
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}

    logger.info("CLI 실행 대기 (model=%s, prompt=%d chars, session=%s)", model or "default", len(user_prompt), session_id or "none")

    # 이중 Semaphore: 세션별 제한 → 글로벌 제한
    session_sem = _get_session_semaphore(session_id) if session_id else None

    if session_sem:
        await session_sem.acquire()
    try:
        async with _cli_semaphore:
            await _warn_if_low_memory()
            raw = await _run_cli(cmd, env, user_prompt)
    finally:
        if session_sem:
            session_sem.release()

    logger.info("CLI 응답 수신: %d chars", len(raw))

    # --output-format json → {"type":"result","result":"..."}
    try:
        parsed = json.loads(raw)
        result_text = parsed.get("result", raw)
        logger.info("CLI 결과 파싱 완료: %d chars, 앞 200자: %s", len(result_text), result_text[:200])
        return result_text
    except (json.JSONDecodeError, AttributeError):
        logger.warning("CLI JSON 파싱 실패, raw 반환: 앞 200자: %s", raw[:200])
        return raw


async def _run_cli(cmd: list, env: dict, user_prompt: str) -> str:
    logger.info("CLI 프로세스 시작")

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
        logger.error("Claude CLI 오류 (code %d): %s", proc.returncode, err_msg[:500])
        raise RuntimeError(f"Claude CLI 실패 (code {proc.returncode}): {err_msg[:300]}")

    result = stdout.decode("utf-8").strip()
    if not result:
        err_hint = stderr.decode("utf-8", errors="replace").strip()[:300]
        logger.error("Claude CLI 빈 응답. stderr: %s", err_hint or "none")
        raise RuntimeError(f"Claude CLI 빈 응답 (stderr: {err_hint or 'none'})")
    logger.info("CLI 프로세스 완료: stdout=%d chars, returncode=%d", len(result), proc.returncode)
    return result

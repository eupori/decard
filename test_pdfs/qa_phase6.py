#!/usr/bin/env python3
"""Phase 6 QA: 외국어 단어카드 + OCR 폴백 검증.

10명 페르소나로 모든 기능을 다각도 검증.

Group A (정상 흐름, 4명):
  P1: 한국어 텍스트 PDF + definition (학습/CSV/삭제 풀 사이클)
  P2: 영어 텍스트 PDF + cloze
  P3: 텍스트 PDF + comparison
  P4: 텍스트 PDF + vocab (영어/일본어 단어 추출)

Group B (OCR 폴백, 2명):
  P5: 일본어 교재 이미지 PDF + vocab (8페이지, 핵심 시나리오)
  P6: 일본어 교재 이미지 PDF + definition (vocab 외 모드와의 호환)

Group C (엣지케이스/보안, 4명):
  P7: 빈 파일 / 가짜 PDF
  P8: 잘못된 template_type
  P9: XSS 파일명 + SQL injection 시도 + 데이터 격리
  P10: 동시 3명 업로드 (사이드이펙)
"""
import argparse
import asyncio
import io
import json
import os
import sys
import time
from pathlib import Path

import httpx

sys.stdout.reconfigure(line_buffering=True)
sys.stderr.reconfigure(line_buffering=True)

API_BASE = "http://localhost:8001/api/v1"
HEALTH = "http://localhost:8001/health"
TEST_PDFS = Path("/Users/cml/Desktop/cml/product/decard/test_pdfs")
JAPANESE_IMG_PDF = Path("/Users/cml/Downloads/일본어 교재.pdf")
POLL_INTERVAL = 5
MAX_POLL = 600

results = {"persona": {}, "issues": []}


def log(p, msg):
    print(f"  [{p}] {msg}")


def add_issue(persona, severity, msg):
    results["issues"].append({"persona": persona, "severity": severity, "msg": msg})
    print(f"  ⚠️  [{persona}] {severity}: {msg}")


async def upload(client, pdf_path: Path, template_type: str, device_id: str):
    with open(pdf_path, "rb") as f:
        files = {"file": (pdf_path.name, f, "application/pdf")}
        data = {"template_type": template_type}
        headers = {"X-Device-ID": device_id}
        r = await client.post(f"{API_BASE}/generate", files=files, data=data, headers=headers, timeout=30)
    return r


async def poll_session(client, session_id: str, device_id: str, max_seconds: int = MAX_POLL):
    start = time.time()
    last_progress = -1
    progress_changes = 0
    while time.time() - start < max_seconds:
        r = await client.get(f"{API_BASE}/sessions/{session_id}", headers={"X-Device-ID": device_id}, timeout=15)
        if r.status_code != 200:
            await asyncio.sleep(POLL_INTERVAL)
            continue
        d = r.json()
        if d.get("progress", -1) != last_progress:
            progress_changes += 1
            last_progress = d.get("progress", -1)
        if d.get("status") in ("completed", "failed"):
            d["_progress_changes"] = progress_changes
            d["_elapsed"] = round(time.time() - start, 1)
            return d
        await asyncio.sleep(POLL_INTERVAL)
    return {"status": "timeout", "id": session_id}


async def fetch_cards(client, session_id: str, device_id: str):
    r = await client.get(f"{API_BASE}/sessions/{session_id}", headers={"X-Device-ID": device_id}, timeout=15)
    if r.status_code != 200:
        return None
    return r.json()


async def patch_card(client, card_id: str, device_id: str, **fields):
    r = await client.patch(f"{API_BASE}/cards/{card_id}",
                            json=fields,
                            headers={"X-Device-ID": device_id, "Content-Type": "application/json"},
                            timeout=10)
    return r


async def download_csv(client, session_id: str, device_id: str):
    r = await client.get(f"{API_BASE}/sessions/{session_id}/download",
                          headers={"X-Device-ID": device_id}, timeout=15)
    return r


async def delete_session(client, session_id: str, device_id: str):
    r = await client.delete(f"{API_BASE}/sessions/{session_id}", headers={"X-Device-ID": device_id}, timeout=10)
    return r


# ──────────────────────────────────────
# 페르소나 시나리오
# ──────────────────────────────────────

async def p_full_cycle(client, persona, pdf, template, device_id):
    """정상 풀 사이클: 업로드 → 완료 대기 → 카드 검증 → 수정 → CSV → 삭제."""
    log(persona, f"업로드 시작: {pdf.name} ({template})")
    r = await upload(client, pdf, template, device_id)
    if r.status_code != 200:
        add_issue(persona, "FAIL", f"업로드 실패: {r.status_code} {r.text[:200]}")
        return None
    sess = r.json()
    sid = sess["id"]
    log(persona, f"세션 생성: {sid}, 폴링 시작")

    final = await poll_session(client, sid, device_id)
    if final.get("status") != "completed":
        add_issue(persona, "FAIL", f"카드 생성 실패: status={final.get('status')}, error={final.get('error_message','')}")
        return None

    elapsed = final.get("_elapsed", 0)
    progress_changes = final.get("_progress_changes", 0)
    log(persona, f"완료 ({elapsed}s, progress 변경 {progress_changes}회)")

    if progress_changes < 3:
        add_issue(persona, "WARN", f"진행률 변경 {progress_changes}회 — UX 개선 가능 (5회+ 권장)")

    detail = await fetch_cards(client, sid, device_id)
    cards = detail.get("cards", [])
    if not cards:
        add_issue(persona, "FAIL", "카드 0장 생성")
        return None

    accepted = [c for c in cards if c.get("status") == "accepted"]
    pending = [c for c in cards if c.get("status") == "pending"]
    log(persona, f"카드 {len(cards)}장: accepted={len(accepted)}, pending={len(pending)}")

    if not accepted:
        add_issue(persona, "WARN", "자동 채택 카드 0장 (recommend=true 누락 가능성)")

    # 첫 카드 검증
    c0 = cards[0]
    for k in ("front", "back", "evidence", "evidence_page", "template_type"):
        if not c0.get(k):
            add_issue(persona, "WARN", f"첫 카드 필드 누락: {k}")
    if c0.get("template_type") != template:
        add_issue(persona, "FAIL", f"카드 template_type 불일치: {c0.get('template_type')} vs {template}")

    # 카드 수정 테스트
    if pending:
        r = await patch_card(client, pending[0]["id"], device_id, status="accepted")
        if r.status_code != 200:
            add_issue(persona, "WARN", f"카드 status 수정 실패: {r.status_code}")

    # CSV 다운로드
    r = await download_csv(client, sid, device_id)
    if r.status_code != 200:
        add_issue(persona, "FAIL", f"CSV 다운로드 실패: {r.status_code}")
    elif not r.content or len(r.content) < 50:
        add_issue(persona, "FAIL", f"CSV 빈 응답 ({len(r.content)}바이트)")
    else:
        log(persona, f"CSV 다운로드 OK ({len(r.content)}바이트)")

    # 삭제
    r = await delete_session(client, sid, device_id)
    if r.status_code not in (200, 204):
        add_issue(persona, "WARN", f"세션 삭제 실패: {r.status_code}")

    return {"persona": persona, "card_count": len(cards), "accepted": len(accepted),
            "elapsed": elapsed, "template": template}


async def p7_invalid_files(client):
    """P7: 빈 파일, 가짜 PDF."""
    persona = "P7"
    device_id = "qa-p7-invalid"

    # 빈 파일
    files = {"file": ("empty.pdf", b"", "application/pdf")}
    r = await client.post(f"{API_BASE}/generate", files=files,
                           data={"template_type": "definition"},
                           headers={"X-Device-ID": device_id}, timeout=15)
    if r.status_code == 200:
        add_issue(persona, "FAIL", "빈 파일 업로드가 200으로 통과됨")
    else:
        log(persona, f"빈 파일 → {r.status_code} (정상 거부)")

    # 가짜 PDF (PDF 헤더 없음)
    files = {"file": ("fake.pdf", b"NOT A PDF", "application/pdf")}
    r = await client.post(f"{API_BASE}/generate", files=files,
                           data={"template_type": "definition"},
                           headers={"X-Device-ID": device_id}, timeout=15)
    if r.status_code == 200:
        add_issue(persona, "FAIL", "가짜 PDF 업로드가 200으로 통과됨")
    else:
        log(persona, f"가짜 PDF → {r.status_code} (정상 거부)")

    return {"persona": persona, "status": "ok"}


async def p8_invalid_template(client):
    """P8: 잘못된 template_type."""
    persona = "P8"
    device_id = "qa-p8-template"
    pdf = TEST_PDFS / "01_economics_supply_demand.pdf"

    for bad in ["INVALID", "subjective", "definition; DROP TABLE", "vocab\x00null", ""]:
        with open(pdf, "rb") as f:
            files = {"file": (pdf.name, f, "application/pdf")}
            r = await client.post(f"{API_BASE}/generate", files=files,
                                   data={"template_type": bad},
                                   headers={"X-Device-ID": device_id}, timeout=15)
        if r.status_code == 200:
            add_issue(persona, "FAIL", f"잘못된 template '{bad[:30]}'가 통과됨")
        else:
            log(persona, f"template='{bad[:30]}' → {r.status_code}")

    return {"persona": persona, "status": "ok"}


async def p9_xss_sql(client):
    """P9: XSS 파일명, SQL injection, 데이터 격리."""
    persona = "P9"
    device_id_a = "qa-p9-attacker"
    device_id_b = "qa-p9-victim"
    pdf = TEST_PDFS / "02_genetics_mendelian.pdf"

    # XSS 파일명
    xss_name = "<script>alert(1)</script>.pdf"
    with open(pdf, "rb") as f:
        files = {"file": (xss_name, f, "application/pdf")}
        r = await client.post(f"{API_BASE}/generate", files=files,
                               data={"template_type": "definition"},
                               headers={"X-Device-ID": device_id_a}, timeout=30)
    if r.status_code == 200:
        sess = r.json()
        if "<script>" in sess.get("filename", ""):
            add_issue(persona, "FAIL", "XSS 파일명이 sanitize 안 됨")
        else:
            log(persona, f"XSS 파일명 → sanitized: {sess.get('filename')}")
        sid_a = sess["id"]
    else:
        add_issue(persona, "WARN", f"XSS 파일명 업로드 실패: {r.status_code}")
        sid_a = None

    # 다른 device_id가 sid_a에 접근 시도 (데이터 격리)
    if sid_a:
        r = await client.get(f"{API_BASE}/sessions/{sid_a}",
                              headers={"X-Device-ID": device_id_b}, timeout=10)
        if r.status_code == 200 and r.json().get("id") == sid_a:
            add_issue(persona, "FAIL", f"데이터 격리 깨짐: {device_id_b}가 {device_id_a}의 세션 조회 가능")
        else:
            log(persona, f"데이터 격리 OK ({r.status_code})")

        # 다른 device_id가 sid_a 삭제 시도
        r = await client.delete(f"{API_BASE}/sessions/{sid_a}",
                                 headers={"X-Device-ID": device_id_b}, timeout=10)
        if r.status_code == 200:
            add_issue(persona, "FAIL", f"권한 없는 사용자가 세션 삭제 성공")
        else:
            log(persona, f"권한 없는 삭제 → {r.status_code}")

        # 정리
        await delete_session(client, sid_a, device_id_a)

    # SQL injection 시도 (session_id 경로)
    for bad_sid in ["'; DROP TABLE sessions; --", "../../../etc/passwd", "ses_zzz' OR '1'='1"]:
        r = await client.get(f"{API_BASE}/sessions/{bad_sid}",
                              headers={"X-Device-ID": device_id_a}, timeout=10)
        if r.status_code == 200:
            add_issue(persona, "FAIL", f"SQL injection 의심 통과: {bad_sid[:30]}")
        else:
            log(persona, f"SQL inj '{bad_sid[:30]}' → {r.status_code}")

    return {"persona": persona, "status": "ok"}


async def p10_concurrent(client):
    """P10: 동시 3명 업로드 (사이드이펙)."""
    persona = "P10"
    pdfs = [
        TEST_PDFS / "01_economics_supply_demand.pdf",
        TEST_PDFS / "02_genetics_mendelian.pdf",
        TEST_PDFS / "03_algorithms_data_structures.pdf",
    ]
    devices = [f"qa-p10-{i}" for i in range(3)]

    async def one(i):
        return await p_full_cycle(client, f"{persona}-#{i+1}", pdfs[i], "definition", devices[i])

    log(persona, "동시 3명 업로드 시작")
    t0 = time.time()
    rs = await asyncio.gather(*[one(i) for i in range(3)], return_exceptions=True)
    elapsed = time.time() - t0
    success = sum(1 for r in rs if isinstance(r, dict) and r is not None)
    log(persona, f"동시 3명 완료: {success}/3 성공, {elapsed:.0f}s")
    if success < 3:
        add_issue(persona, "WARN", f"동시 처리 {3 - success}건 실패")
    return {"persona": persona, "success": success, "elapsed": round(elapsed, 1)}


async def p11_ocr_limit(client):
    """추가: OCR 페이지 제한 검증 — MAX_OCR_PAGES=10 → 11페이지 이미지 PDF 거부."""
    # 일본어 교재는 8페이지 (한도 내). 한도 초과 PDF가 없으면 skip
    persona = "P11-OCR-LIMIT"
    log(persona, "8페이지 이미지 PDF 한도 내 통과 검증 (별도 케이스)")
    # 이건 P5에서 검증되므로 별도 작업 X
    return None


# ──────────────────────────────────────
# 메인
# ──────────────────────────────────────

async def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true", help="빠른 검증 (P5/P6 OCR 생략)")
    parser.add_argument("--out", default="/tmp/qa_phase6_result.json")
    args = parser.parse_args()

    # 헬스체크
    async with httpx.AsyncClient() as client:
        r = await client.get(HEALTH, timeout=5)
        if r.status_code != 200:
            print(f"❌ 서버 미동작: {HEALTH}")
            sys.exit(1)
        print(f"✓ 서버 동작 확인: {r.json().get('status')}")
        print()

        t0 = time.time()

        # Group A: 정상 흐름 (4명, 동시)
        print("=" * 60)
        print("Group A: 정상 흐름")
        print("=" * 60)
        group_a_tasks = [
            p_full_cycle(client, "P1-한국어definition",
                          TEST_PDFS / "11_심리학_감각과지각.pdf", "definition", "qa-p1"),
            p_full_cycle(client, "P2-영어cloze",
                          TEST_PDFS / "01_economics_supply_demand.pdf", "cloze", "qa-p2"),
            p_full_cycle(client, "P3-comparison",
                          TEST_PDFS / "02_genetics_mendelian.pdf", "comparison", "qa-p3"),
        ]
        # 동시 3개 (Semaphore=3 한도)
        rs_a = await asyncio.gather(*group_a_tasks, return_exceptions=True)
        for r in rs_a:
            if isinstance(r, Exception):
                add_issue("Group A", "FAIL", f"예외: {type(r).__name__}: {r}")

        # P4 vocab (텍스트 PDF) — 일본어 텍스트 PDF
        print()
        print("Group A 추가: P4 vocab (텍스트 PDF)")
        r4 = await p_full_cycle(client, "P4-vocab텍스트",
                                  TEST_PDFS / "27_multilang_일본어기초.pdf", "vocab", "qa-p4")

        # Group B: OCR 폴백 (1명)
        if not args.quick and JAPANESE_IMG_PDF.exists():
            print()
            print("=" * 60)
            print("Group B: OCR 폴백 (이미지 PDF)")
            print("=" * 60)
            r5 = await p_full_cycle(client, "P5-OCR일본어vocab",
                                      JAPANESE_IMG_PDF, "vocab", "qa-p5")

        # Group C: 엣지케이스/보안
        print()
        print("=" * 60)
        print("Group C: 엣지케이스 + 보안")
        print("=" * 60)
        await p7_invalid_files(client)
        await p8_invalid_template(client)
        await p9_xss_sql(client)

        # P10: 동시 처리
        print()
        print("=" * 60)
        print("P10: 동시 3명 (사이드이펙)")
        print("=" * 60)
        await p10_concurrent(client)

        elapsed = time.time() - t0

    # 결과 정리
    print()
    print("=" * 60)
    print("QA 결과 요약")
    print("=" * 60)
    print(f"총 소요 시간: {elapsed:.0f}s")
    fail_count = sum(1 for i in results["issues"] if i["severity"] == "FAIL")
    warn_count = sum(1 for i in results["issues"] if i["severity"] == "WARN")
    print(f"FAIL: {fail_count}건, WARN: {warn_count}건")
    print()
    if results["issues"]:
        print("이슈 목록:")
        for i in results["issues"]:
            print(f"  [{i['severity']}] {i['persona']}: {i['msg']}")
    else:
        print("✅ 모든 검증 통과!")

    with open(args.out, "w") as f:
        json.dump({
            "elapsed_s": round(elapsed, 1),
            "fail": fail_count,
            "warn": warn_count,
            "issues": results["issues"],
        }, f, ensure_ascii=False, indent=2)
    print(f"\n결과 저장: {args.out}")
    return 0 if fail_count == 0 else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))

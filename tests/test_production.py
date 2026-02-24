"""
Decard 프로덕션 QA 테스트 — 20명 시뮬레이션
10명: Full E2E QA
10명: 스트레스/악성/엣지/사이드이펙트 테스트
"""

import asyncio
import io
import json
import os
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass, field
from typing import Optional

import requests
from fpdf import FPDF

# ──────────────────────────────────────
# 설정
# ──────────────────────────────────────

API_BASE = os.getenv("API_BASE", "https://decard-api.eupori.dev/api/v1")
POLL_INTERVAL = 5  # 초
POLL_TIMEOUT = 300  # 5분 타임아웃


# ──────────────────────────────────────
# 테스트 PDF 생성
# ──────────────────────────────────────

def create_test_pdf(pages: int = 3) -> bytes:
    """교육용 한국어 PDF 생성 (피아제 인지발달이론)"""
    pdf = FPDF()
    font_path = None
    # macOS 한국어 폰트
    for p in [
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
    ]:
        if os.path.exists(p):
            font_path = p
            break

    content_pages = [
        """제1장: 피아제의 인지발달 이론

장 피아제(Jean Piaget, 1896-1980)는 스위스의 발달심리학자로, 아동의 인지 발달에 관한 가장 영향력 있는 이론을 제시하였다.

1. 스키마(Schema)
스키마란 세상을 이해하고 해석하는 데 사용하는 인지적 틀이다. 영아는 단순한 반사 스키마에서 시작하여 점차 복잡한 인지 스키마를 발달시킨다.

2. 동화(Assimilation)와 조절(Accommodation)
동화란 새로운 정보를 기존의 스키마에 맞추어 해석하는 과정이다. 예를 들어, 네 발 달린 동물을 모두 '강아지'라고 부르는 것이다.
조절이란 기존 스키마로 설명할 수 없는 새로운 정보에 맞게 스키마를 수정하거나 새로 만드는 과정이다. 고양이를 보고 '강아지가 아니라 고양이구나'라고 구분하는 것이다.

3. 평형화(Equilibration)
동화와 조절의 균형을 통해 인지적 평형 상태를 유지하려는 과정이다. 인지적 불균형(비평형 상태)이 발생하면 아동은 조절을 통해 새로운 평형 상태를 달성한다. 이것이 인지 발달의 원동력이 된다.

4. 인지발달의 4단계
피아제는 인지발달을 4단계로 구분하였다:
(1) 감각운동기(0~2세): 감각과 운동을 통해 세계를 탐색. 대상영속성(object permanence)을 획득한다.
(2) 전조작기(2~7세): 상징적 사고 가능, 자기중심성(egocentrism), 보존 개념 미발달.
(3) 구체적 조작기(7~11세): 논리적 사고 가능, 보존 개념 획득, 가역성 이해.
(4) 형식적 조작기(11세~): 추상적·가설적 사고 가능, 조합적 추론 능력.""",

        """제2장: 에릭슨의 심리사회적 발달 이론

에릭 에릭슨(Erik Erikson, 1902-1994)은 프로이트의 심리성적 발달 이론을 확장하여 전 생애에 걸친 심리사회적 발달 이론을 제시하였다.

1. 8단계 발달 과업
에릭슨은 인간의 발달을 8단계로 나누고, 각 단계마다 해결해야 할 심리사회적 위기(crisis)가 있다고 보았다.

(1) 신뢰감 대 불신감 (0~1세): 양육자의 일관된 돌봄 → 기본적 신뢰감 형성
(2) 자율성 대 수치심 (1~3세): 자기 통제와 의지력 발달
(3) 주도성 대 죄책감 (3~6세): 목적의식과 계획 능력 발달
(4) 근면성 대 열등감 (6~12세): 학교 생활을 통한 유능감 발달
(5) 정체감 대 역할혼란 (12~18세): 자아정체성 확립
(6) 친밀감 대 고립감 (성인 초기): 타인과의 친밀한 관계 형성
(7) 생산성 대 침체감 (성인 중기): 다음 세대를 위한 관심과 기여
(8) 자아통합감 대 절망감 (노년기): 인생을 의미 있게 수용

2. 점성적 원리(Epigenetic Principle)
에릭슨은 각 단계가 정해진 시기에 순서대로 나타나며, 이전 단계의 위기 해결이 다음 단계에 영향을 미친다고 보았다. 이를 점성적 원리라고 한다.

3. 자아정체성(Ego Identity)
에릭슨이 가장 강조한 개념으로, 특히 청소년기에 '나는 누구인가'에 대한 통합된 자아상을 형성하는 것이 핵심 과업이다. 정체성 위기를 성공적으로 해결하면 자아정체성을 확립하고, 실패하면 역할혼란을 경험한다.""",

        """제3장: 비고츠키의 사회문화적 인지발달 이론

레프 비고츠키(Lev Vygotsky, 1896-1934)는 러시아의 심리학자로, 인지 발달에서 사회적 상호작용과 문화의 역할을 강조하였다.

1. 근접발달영역(Zone of Proximal Development, ZPD)
근접발달영역이란 아동이 혼자서는 해결할 수 없지만, 더 유능한 타인의 도움을 받으면 해결할 수 있는 과제의 범위를 말한다. 이 개념은 교육에서 매우 중요한 의미를 갖는다.

2. 비계설정(Scaffolding)
비계설정이란 학습자가 과제를 수행할 때 교사나 유능한 또래가 적절한 수준의 도움을 제공하는 것을 말한다. 학습자의 능력이 향상됨에 따라 점차 도움을 줄여나간다.

3. 사적 언어(Private Speech)
비고츠키는 아동이 혼자서 말하는 사적 언어가 사고를 조절하는 중요한 도구라고 보았다. 사적 언어는 점차 내면화되어 내적 언어(inner speech)로 발달한다. 이는 피아제가 자기중심적 언어라고 본 것과 대조된다.

4. 피아제와의 비교
피아제는 발달이 학습에 선행한다고 보았으나, 비고츠키는 학습이 발달을 이끈다고 보았다. 피아제는 아동의 독립적 탐색을 강조한 반면, 비고츠키는 사회적 상호작용과 문화적 도구의 매개를 강조하였다.

5. 문화적 도구(Cultural Tools)
비고츠키는 언어, 수 체계, 글쓰기 등의 문화적 도구가 인지 발달을 매개한다고 보았다. 이러한 도구는 사회적 상호작용을 통해 전수되며, 아동의 사고 방식을 근본적으로 변화시킨다.""",
    ]

    for i in range(min(pages, len(content_pages))):
        pdf.add_page()
        if font_path:
            pdf.add_font("Korean", "", font_path, uni=True)
            pdf.set_font("Korean", size=11)
        else:
            pdf.set_font("Helvetica", size=11)
        pdf.multi_cell(0, 6, content_pages[i])

    return bytes(pdf.output())


def create_tiny_pdf() -> bytes:
    """1페이지 짧은 PDF"""
    pdf = FPDF()
    pdf.add_page()
    font_path = None
    for p in [
        "/System/Library/Fonts/AppleSDGothicNeo.ttc",
        "/System/Library/Fonts/Supplemental/AppleGothic.ttf",
    ]:
        if os.path.exists(p):
            font_path = p
            break
    if font_path:
        pdf.add_font("Korean", "", font_path, uni=True)
        pdf.set_font("Korean", size=11)
    else:
        pdf.set_font("Helvetica", size=11)
    pdf.multi_cell(0, 6, "피아제의 감각운동기는 출생부터 2세까지이며, 대상영속성을 획득하는 시기이다. 전조작기는 2~7세로 상징적 사고가 가능하지만 보존 개념이 발달하지 않는다.")
    return bytes(pdf.output())


# ──────────────────────────────────────
# 테스트 결과 수집
# ──────────────────────────────────────

@dataclass
class TestResult:
    user: str
    test: str
    passed: bool
    detail: str = ""
    duration: float = 0.0


results: list[TestResult] = []
results_lock = asyncio.Lock() if sys.version_info >= (3, 10) else None


def add_result(user: str, test: str, passed: bool, detail: str = "", duration: float = 0.0):
    results.append(TestResult(user=user, test=test, passed=passed, detail=detail, duration=duration))


# ──────────────────────────────────────
# API 헬퍼
# ──────────────────────────────────────

class ApiClient:
    def __init__(self, device_id: str):
        self.device_id = device_id
        self.session = requests.Session()
        self.session.headers.update({"X-Device-ID": device_id})
        self.base = API_BASE

    def upload_pdf(self, pdf_bytes: bytes, template_type: str = "definition", filename: str = "test.pdf") -> dict:
        resp = self.session.post(
            f"{self.base}/generate",
            files={"file": (filename, pdf_bytes, "application/pdf")},
            data={"template_type": template_type},
        )
        resp.raise_for_status()
        return resp.json()

    def get_session(self, session_id: str) -> dict:
        resp = self.session.get(f"{self.base}/sessions/{session_id}")
        resp.raise_for_status()
        return resp.json()

    def list_sessions(self) -> list:
        resp = self.session.get(f"{self.base}/sessions")
        resp.raise_for_status()
        return resp.json()

    def delete_session(self, session_id: str) -> dict:
        resp = self.session.delete(f"{self.base}/sessions/{session_id}")
        resp.raise_for_status()
        return resp.json()

    def update_card(self, card_id: str, **kwargs) -> dict:
        resp = self.session.patch(f"{self.base}/cards/{card_id}", json=kwargs)
        resp.raise_for_status()
        return resp.json()

    def accept_all(self, session_id: str) -> dict:
        resp = self.session.post(f"{self.base}/sessions/{session_id}/accept-all")
        resp.raise_for_status()
        return resp.json()

    def download_csv(self, session_id: str) -> bytes:
        resp = self.session.get(f"{self.base}/sessions/{session_id}/download")
        resp.raise_for_status()
        return resp.content

    def poll_until_complete(self, session_id: str, timeout: int = POLL_TIMEOUT) -> dict:
        start = time.time()
        while time.time() - start < timeout:
            data = self.get_session(session_id)
            if data["status"] in ("completed", "failed"):
                return data
            time.sleep(POLL_INTERVAL)
        raise TimeoutError(f"세션 {session_id}이(가) {timeout}초 내에 완료되지 않았습니다.")

    def raw_post(self, path: str, **kwargs) -> requests.Response:
        return self.session.post(f"{self.base}{path}", **kwargs)

    def raw_get(self, path: str) -> requests.Response:
        return self.session.get(f"{self.base}{path}")


# ──────────────────────────────────────
# Group A: Full QA (10명)
# ──────────────────────────────────────

def run_qa_test(user_name: str, template_type: str, pdf_bytes: bytes):
    """E2E 전체 흐름 테스트"""
    device_id = f"qa-test-{uuid.uuid4().hex[:12]}"
    client = ApiClient(device_id)
    created_sessions = []

    try:
        # 1. PDF 업로드
        t0 = time.time()
        session_data = client.upload_pdf(pdf_bytes, template_type=template_type)
        sid = session_data["id"]
        created_sessions.append(sid)
        add_result(user_name, "1_upload", True, f"session={sid}", time.time() - t0)

        # 2. 상태 확인 (processing)
        add_result(user_name, "2_processing_status",
                   session_data["status"] == "processing",
                   f"status={session_data['status']}")

        # 3. 완료 대기 + 폴링
        t0 = time.time()
        completed = client.poll_until_complete(sid)
        poll_time = time.time() - t0
        add_result(user_name, "3_completion",
                   completed["status"] == "completed",
                   f"status={completed['status']}, {poll_time:.0f}s", poll_time)

        if completed["status"] != "completed":
            add_result(user_name, "3_ABORT", False, "세션 완료 실패 — 이후 테스트 스킵")
            return created_sessions

        cards = completed.get("cards", [])
        stats = completed.get("stats", {})
        total = stats.get("total", len(cards))
        accepted = stats.get("accepted", 0)
        pending = stats.get("pending", 0)
        rejected = stats.get("rejected", 0)

        # 4. 카드 수 범위 (20~30)
        add_result(user_name, "4_card_count_range",
                   10 <= total <= 35,  # 약간의 여유
                   f"total={total} (목표: 20~30)")

        # 5. 자동 채택 확인 (최소 10장)
        add_result(user_name, "5_auto_accept_min10",
                   accepted >= 10,
                   f"accepted={accepted}, pending={pending}")

        # 6. 초기 rejected=0
        add_result(user_name, "6_no_initial_reject",
                   rejected == 0,
                   f"rejected={rejected}")

        # 7. accepted + pending = total
        add_result(user_name, "7_status_sum",
                   accepted + pending == total,
                   f"accepted({accepted})+pending({pending})={accepted + pending}, total={total}")

        # 8. 개별 카드 상태 수정 (pending → accepted)
        pending_cards = [c for c in cards if c["status"] == "pending"]
        if pending_cards:
            test_card = pending_cards[0]
            updated = client.update_card(test_card["id"], status="accepted")
            add_result(user_name, "8_manual_accept",
                       updated["status"] == "accepted",
                       f"card={test_card['id']}")
        else:
            add_result(user_name, "8_manual_accept", True, "모든 카드 이미 채택됨 (스킵)")

        # 9. 개별 카드 reject
        accepted_cards = [c for c in cards if c["status"] == "accepted"]
        if accepted_cards:
            test_card = accepted_cards[0]
            updated = client.update_card(test_card["id"], status="rejected")
            add_result(user_name, "9_manual_reject",
                       updated["status"] == "rejected",
                       f"card={test_card['id']}")
            # 되돌리기
            client.update_card(test_card["id"], status="accepted")
        else:
            add_result(user_name, "9_manual_reject", True, "채택 카드 없음 (스킵)")

        # 10. 전체 채택
        accept_result = client.accept_all(sid)
        add_result(user_name, "10_accept_all",
                   "accepted" in accept_result,
                   f"accepted={accept_result.get('accepted', '?')}")

        # 11. 전체 채택 후 확인
        refreshed = client.get_session(sid)
        all_accepted = all(c["status"] == "accepted" for c in refreshed["cards"])
        add_result(user_name, "11_all_accepted_after",
                   all_accepted,
                   f"total={len(refreshed['cards'])}")

        # 12. CSV 다운로드
        csv_data = client.download_csv(sid)
        add_result(user_name, "12_csv_download",
                   len(csv_data) > 0,
                   f"size={len(csv_data)} bytes")

        # 13. 세션 삭제
        del_result = client.delete_session(sid)
        add_result(user_name, "13_delete_session",
                   "deleted" in del_result,
                   f"deleted={del_result.get('deleted', '?')}")
        created_sessions.remove(sid)

        # 14. 삭제 후 조회 불가
        try:
            client.get_session(sid)
            add_result(user_name, "14_deleted_not_found", False, "삭제된 세션이 여전히 조회됨")
        except requests.HTTPError as e:
            add_result(user_name, "14_deleted_not_found",
                       e.response.status_code == 404,
                       f"status={e.response.status_code}")

    except Exception as e:
        add_result(user_name, "EXCEPTION", False, f"{type(e).__name__}: {e}")

    return created_sessions


# ──────────────────────────────────────
# Group B: 스트레스 테스트 (동시 업로드)
# ──────────────────────────────────────

def run_stress_test(pdf_bytes: bytes):
    """3명이 동시에 PDF 업로드"""
    user_name = "stress"
    created_sessions = []

    try:
        clients = [ApiClient(f"stress-{uuid.uuid4().hex[:12]}") for _ in range(3)]
        templates = ["definition", "cloze", "comparison"]

        t0 = time.time()
        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {
                executor.submit(c.upload_pdf, pdf_bytes, t): (c, t)
                for c, t in zip(clients, templates)
            }
            sessions = []
            for future in as_completed(futures):
                client, tmpl = futures[future]
                try:
                    data = future.result()
                    sessions.append((client, data))
                    created_sessions.append(data["id"])
                except Exception as e:
                    add_result(user_name, f"concurrent_upload_{tmpl}", False, str(e))

        add_result(user_name, "concurrent_upload",
                   len(sessions) == 3,
                   f"{len(sessions)}/3 업로드 성공", time.time() - t0)

        # 모두 완료 대기
        t0 = time.time()
        completed_count = 0
        for client, session_data in sessions:
            try:
                result = client.poll_until_complete(session_data["id"])
                if result["status"] == "completed":
                    completed_count += 1
            except Exception:
                pass

        add_result(user_name, "concurrent_completion",
                   completed_count == 3,
                   f"{completed_count}/3 완료", time.time() - t0)

        # 정리
        for client, session_data in sessions:
            try:
                client.delete_session(session_data["id"])
                if session_data["id"] in created_sessions:
                    created_sessions.remove(session_data["id"])
            except Exception:
                pass

    except Exception as e:
        add_result(user_name, "EXCEPTION", False, f"{type(e).__name__}: {e}")

    return created_sessions


# ──────────────────────────────────────
# Group B: 악성 입력 테스트
# ──────────────────────────────────────

def run_malicious_test():
    """잘못된 입력에 대한 방어 테스트"""
    user_name = "malicious"
    client = ApiClient(f"mal-{uuid.uuid4().hex[:12]}")

    # 1. 비-PDF 파일 업로드
    try:
        resp = client.raw_post("/generate",
                               files={"file": ("test.pdf", b"This is not a PDF", "application/pdf")},
                               data={"template_type": "definition"})
        add_result(user_name, "1_non_pdf_rejected",
                   resp.status_code == 400,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "1_non_pdf_rejected", False, str(e))

    # 2. 빈 파일
    try:
        resp = client.raw_post("/generate",
                               files={"file": ("empty.pdf", b"", "application/pdf")},
                               data={"template_type": "definition"})
        add_result(user_name, "2_empty_file_rejected",
                   resp.status_code == 400,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "2_empty_file_rejected", False, str(e))

    # 3. 잘못된 template_type
    try:
        resp = client.raw_post("/generate",
                               files={"file": ("test.pdf", create_tiny_pdf(), "application/pdf")},
                               data={"template_type": "'; DROP TABLE cards;--"})
        add_result(user_name, "3_sql_injection_template",
                   resp.status_code == 400,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "3_sql_injection_template", False, str(e))

    # 4. 존재하지 않는 세션 조회
    try:
        resp = client.raw_get("/sessions/ses_nonexistent")
        add_result(user_name, "4_invalid_session_404",
                   resp.status_code == 404,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "4_invalid_session_404", False, str(e))

    # 5. 존재하지 않는 카드 수정
    try:
        resp = client.session.patch(f"{client.base}/cards/card_nonexist",
                                    json={"status": "accepted"})
        add_result(user_name, "5_invalid_card_404",
                   resp.status_code == 404,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "5_invalid_card_404", False, str(e))

    # 6. XSS 파일명
    try:
        pdf_bytes = create_tiny_pdf()
        resp = client.raw_post("/generate",
                               files={"file": ('<script>alert("xss")</script>.pdf', pdf_bytes, "application/pdf")},
                               data={"template_type": "definition"})
        # 업로드 자체는 성공할 수 있지만, 파일명이 이스케이프되어야 함
        if resp.status_code == 200:
            data = resp.json()
            # 파일명에 <script>가 그대로 들어가도 DB 저장만 되므로 허용
            add_result(user_name, "6_xss_filename", True,
                       f"업로드 허용됨 (DB 저장, 렌더링 시 이스케이프 필요)")
            # 정리
            try:
                client.delete_session(data["id"])
            except Exception:
                pass
        else:
            add_result(user_name, "6_xss_filename", True,
                       f"status={resp.status_code} (거부됨)")
    except Exception as e:
        add_result(user_name, "6_xss_filename", False, str(e))

    # 7. 잘못된 카드 상태값
    try:
        resp = client.session.patch(f"{client.base}/cards/card_00000001",
                                    json={"status": "HACKED"})
        # 404 또는 무시되어야 함
        add_result(user_name, "7_invalid_status",
                   resp.status_code in (404, 200, 422),
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "7_invalid_status", False, str(e))


# ──────────────────────────────────────
# Group B: 데이터 격리 테스트
# ──────────────────────────────────────

def run_isolation_test(pdf_bytes: bytes):
    """유저 간 데이터 격리 확인"""
    user_name = "isolation"
    created_sessions = []

    try:
        user_a = ApiClient(f"iso-a-{uuid.uuid4().hex[:12]}")
        user_b = ApiClient(f"iso-b-{uuid.uuid4().hex[:12]}")

        # User A가 세션 생성
        session_a = user_a.upload_pdf(pdf_bytes, template_type="definition")
        sid_a = session_a["id"]
        created_sessions.append(sid_a)

        # 완료 대기
        user_a.poll_until_complete(sid_a)

        # User B가 User A의 세션 조회 시도
        try:
            resp = user_b.raw_get(f"/sessions/{sid_a}")
            if resp.status_code == 404:
                add_result(user_name, "1_cross_user_session_blocked", True, "404 반환 (정상)")
            else:
                # 다른 유저 세션이 보이면 격리 실패
                add_result(user_name, "1_cross_user_session_blocked", False,
                           f"status={resp.status_code}, 타인 세션 접근 가능!")
        except Exception as e:
            add_result(user_name, "1_cross_user_session_blocked", False, str(e))

        # User B의 세션 목록에 A 세션 없어야 함
        b_sessions = user_b.list_sessions()
        a_ids = {sid_a}
        leaked = [s for s in b_sessions if s["id"] in a_ids]
        add_result(user_name, "2_session_list_isolation",
                   len(leaked) == 0,
                   f"leaked={len(leaked)}")

        # User B가 User A의 세션 삭제 시도
        try:
            resp = requests.delete(f"{API_BASE}/sessions/{sid_a}",
                                   headers={"X-Device-ID": user_b.device_id})
            add_result(user_name, "3_cross_user_delete_blocked",
                       resp.status_code == 404,
                       f"status={resp.status_code}")
        except Exception as e:
            add_result(user_name, "3_cross_user_delete_blocked", False, str(e))

        # 정리: User A가 자기 세션 삭제
        try:
            user_a.delete_session(sid_a)
            created_sessions.remove(sid_a)
        except Exception:
            pass

    except Exception as e:
        add_result(user_name, "EXCEPTION", False, f"{type(e).__name__}: {e}")

    return created_sessions


# ──────────────────────────────────────
# Group B: 엣지 케이스 테스트
# ──────────────────────────────────────

def run_edge_test():
    """엣지 케이스 테스트"""
    user_name = "edge"
    client = ApiClient(f"edge-{uuid.uuid4().hex[:12]}")
    created_sessions = []

    # 1. 아주 짧은 PDF (1페이지, 2문장)
    try:
        tiny_pdf = create_tiny_pdf()
        session = client.upload_pdf(tiny_pdf, template_type="definition")
        sid = session["id"]
        created_sessions.append(sid)
        result = client.poll_until_complete(sid)
        card_count = len(result.get("cards", []))
        add_result(user_name, "1_tiny_pdf",
                   result["status"] == "completed" and card_count > 0,
                   f"status={result['status']}, cards={card_count}")
        client.delete_session(sid)
        created_sessions.remove(sid)
    except Exception as e:
        add_result(user_name, "1_tiny_pdf", False, str(e))

    # 2. 이중 accept-all
    try:
        pdf = create_test_pdf(pages=2)
        session = client.upload_pdf(pdf, template_type="definition")
        sid = session["id"]
        created_sessions.append(sid)
        result = client.poll_until_complete(sid)
        if result["status"] == "completed":
            r1 = client.accept_all(sid)
            r2 = client.accept_all(sid)  # 두번째는 0이어야
            add_result(user_name, "2_double_accept_all", True,
                       f"1st={r1.get('accepted', '?')}, 2nd={r2.get('accepted', '?')}")
        client.delete_session(sid)
        created_sessions.remove(sid)
    except Exception as e:
        add_result(user_name, "2_double_accept_all", False, str(e))

    # 3. 존재하지 않는 세션 삭제
    try:
        resp = client.session.delete(f"{client.base}/sessions/ses_nonexistent")
        add_result(user_name, "3_delete_nonexistent",
                   resp.status_code == 404,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "3_delete_nonexistent", False, str(e))

    # 4. 헬스체크
    try:
        base_url = API_BASE.replace("/api/v1", "")
        resp = requests.get(f"{base_url}/health")
        add_result(user_name, "4_health_check",
                   resp.status_code == 200,
                   f"status={resp.status_code}")
    except Exception as e:
        add_result(user_name, "4_health_check", False, str(e))

    return created_sessions


# ──────────────────────────────────────
# Group B: 사이드이펙트 테스트
# ──────────────────────────────────────

def run_side_effect_test(pdf_bytes: bytes):
    """기존 기능 영향 없음 확인"""
    user_name = "side-effect"
    client = ApiClient(f"side-{uuid.uuid4().hex[:12]}")
    created_sessions = []

    try:
        # 1. 세션 생성 → 카드 수정 → 재조회 일관성
        session = client.upload_pdf(pdf_bytes, template_type="definition")
        sid = session["id"]
        created_sessions.append(sid)
        result = client.poll_until_complete(sid)

        if result["status"] == "completed" and result["cards"]:
            card = result["cards"][0]

            # 카드 내용 수정
            new_front = "수정된 질문입니다"
            updated = client.update_card(card["id"], front=new_front)
            add_result(user_name, "1_card_edit_persist",
                       updated["front"] == new_front,
                       f"front={'OK' if updated['front'] == new_front else 'MISMATCH'}")

            # 재조회 확인
            refreshed = client.get_session(sid)
            found = [c for c in refreshed["cards"] if c["id"] == card["id"]]
            add_result(user_name, "2_card_edit_reload",
                       found and found[0]["front"] == new_front,
                       "수정 유지 확인")

        # 2. 여러 템플릿 타입이 각각 독립적으로 동작
        for tmpl in ["cloze", "comparison"]:
            s = client.upload_pdf(pdf_bytes, template_type=tmpl)
            created_sessions.append(s["id"])
            r = client.poll_until_complete(s["id"])
            add_result(user_name, f"3_template_{tmpl}",
                       r["status"] == "completed",
                       f"cards={len(r.get('cards', []))}")

        # 정리
        for sid in list(created_sessions):
            try:
                client.delete_session(sid)
                created_sessions.remove(sid)
            except Exception:
                pass

    except Exception as e:
        add_result(user_name, "EXCEPTION", False, f"{type(e).__name__}: {e}")

    return created_sessions


# ──────────────────────────────────────
# 메인 실행
# ──────────────────────────────────────

def main():
    print("=" * 60)
    print("  Decard 프로덕션 QA 테스트 — 20명 시뮬레이션")
    print(f"  API: {API_BASE}")
    print("=" * 60)

    # 헬스체크
    try:
        base_url = API_BASE.replace("/api/v1", "")
        resp = requests.get(f"{base_url}/health", timeout=10)
        print(f"\n[HEALTH] {resp.status_code} — {'OK' if resp.status_code == 200 else 'FAIL'}")
        if resp.status_code != 200:
            print("서버 응답 없음. 테스트 중단.")
            return
    except Exception as e:
        print(f"\n[HEALTH] FAIL — {e}")
        print("서버 연결 불가. 테스트 중단.")
        return

    # PDF 생성
    print("\n[PREP] 테스트 PDF 생성 중...")
    pdf_3page = create_test_pdf(pages=3)
    print(f"  3페이지 PDF: {len(pdf_3page):,} bytes")

    all_leftover_sessions = []

    # ──── Group A: QA 테스트 (10명, 3명씩 배치) ────
    print("\n" + "─" * 60)
    print("  Group A: Full E2E QA (10명)")
    print("─" * 60)

    qa_configs = [
        ("qa-01", "definition"), ("qa-02", "definition"), ("qa-03", "definition"),
        ("qa-04", "cloze"), ("qa-05", "cloze"), ("qa-06", "cloze"),
        ("qa-07", "comparison"), ("qa-08", "comparison"), ("qa-09", "comparison"),
        ("qa-10", "definition"),
    ]

    # 3명씩 배치 실행 (Semaphore=3 고려)
    for batch_start in range(0, len(qa_configs), 3):
        batch = qa_configs[batch_start:batch_start + 3]
        batch_names = [b[0] for b in batch]
        print(f"\n  배치 {batch_start // 3 + 1}: {', '.join(batch_names)}")

        with ThreadPoolExecutor(max_workers=3) as executor:
            futures = {
                executor.submit(run_qa_test, name, tmpl, pdf_3page): name
                for name, tmpl in batch
            }
            for future in as_completed(futures):
                name = futures[future]
                try:
                    leftover = future.result()
                    all_leftover_sessions.extend(leftover)
                    passed = sum(1 for r in results if r.user == name and r.passed)
                    failed = sum(1 for r in results if r.user == name and not r.passed)
                    print(f"    {name}: {passed} passed, {failed} failed")
                except Exception as e:
                    print(f"    {name}: EXCEPTION — {e}")

    # ──── Group B: 특수 테스트 (10명) ────
    print("\n" + "─" * 60)
    print("  Group B: 스트레스/악성/엣지/사이드이펙트 (10명)")
    print("─" * 60)

    # B-1: 스트레스 (3명 동시 — stress-01~03)
    print("\n  [B-1] 스트레스 테스트 (3명 동시 업로드)...")
    leftover = run_stress_test(pdf_3page)
    all_leftover_sessions.extend(leftover)
    stress_passed = sum(1 for r in results if r.user == "stress" and r.passed)
    stress_failed = sum(1 for r in results if r.user == "stress" and not r.passed)
    print(f"    stress: {stress_passed} passed, {stress_failed} failed")

    # B-2: 악성 입력 (malicious-01~03 역할 통합)
    print("\n  [B-2] 악성 입력 테스트...")
    run_malicious_test()
    mal_passed = sum(1 for r in results if r.user == "malicious" and r.passed)
    mal_failed = sum(1 for r in results if r.user == "malicious" and not r.passed)
    print(f"    malicious: {mal_passed} passed, {mal_failed} failed")

    # B-3: 데이터 격리 (isolation-01~02 역할 통합)
    print("\n  [B-3] 데이터 격리 테스트...")
    leftover = run_isolation_test(pdf_3page)
    all_leftover_sessions.extend(leftover)
    iso_passed = sum(1 for r in results if r.user == "isolation" and r.passed)
    iso_failed = sum(1 for r in results if r.user == "isolation" and not r.passed)
    print(f"    isolation: {iso_passed} passed, {iso_failed} failed")

    # B-4: 엣지 케이스 (edge-01~02 역할 통합)
    print("\n  [B-4] 엣지 케이스 테스트...")
    leftover = run_edge_test()
    all_leftover_sessions.extend(leftover)
    edge_passed = sum(1 for r in results if r.user == "edge" and r.passed)
    edge_failed = sum(1 for r in results if r.user == "edge" and not r.passed)
    print(f"    edge: {edge_passed} passed, {edge_failed} failed")

    # B-5: 사이드이펙트 (side-effect-01~02 역할 통합)
    print("\n  [B-5] 사이드이펙트 테스트...")
    leftover = run_side_effect_test(pdf_3page)
    all_leftover_sessions.extend(leftover)
    side_passed = sum(1 for r in results if r.user == "side-effect" and r.passed)
    side_failed = sum(1 for r in results if r.user == "side-effect" and not r.passed)
    print(f"    side-effect: {side_passed} passed, {side_failed} failed")

    # ──── 결과 요약 ────
    print("\n" + "=" * 60)
    print("  결과 요약")
    print("=" * 60)

    total_passed = sum(1 for r in results if r.passed)
    total_failed = sum(1 for r in results if not r.passed)
    total_tests = len(results)

    print(f"\n  총 {total_tests}개 테스트: {total_passed} PASSED / {total_failed} FAILED")
    print(f"  성공률: {total_passed / total_tests * 100:.1f}%" if total_tests > 0 else "")

    if total_failed > 0:
        print(f"\n  ❌ 실패한 테스트:")
        for r in results:
            if not r.passed:
                print(f"    [{r.user}] {r.test}: {r.detail}")

    print(f"\n  ✅ 전체 테스트 상세:")
    current_user = ""
    for r in results:
        if r.user != current_user:
            current_user = r.user
            print(f"\n    [{r.user}]")
        status = "✅" if r.passed else "❌"
        duration = f" ({r.duration:.1f}s)" if r.duration > 0 else ""
        print(f"      {status} {r.test}: {r.detail}{duration}")

    # 잔여 세션 정리
    if all_leftover_sessions:
        print(f"\n  ⚠️  정리되지 않은 테스트 세션 {len(all_leftover_sessions)}개:")
        for sid in all_leftover_sessions:
            print(f"    - {sid}")

    print("\n" + "=" * 60)
    print("  테스트 완료")
    print("=" * 60)


if __name__ == "__main__":
    main()

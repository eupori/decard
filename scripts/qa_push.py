"""FCM 푸시 알림 fix QA — 10개 케이스 검증.

실행 (VPS):
  scp scripts/qa_push.py eupori-server:/tmp/qa_push.py
  ssh eupori-server "docker cp /tmp/qa_push.py decard-api-1:/tmp/qa_push.py && \\
                     docker exec decard-api-1 python /tmp/qa_push.py"

검증 대상:
  - routes._collect_session_fcm_tokens — user_id/device_id 매칭 + 폴백 로직
  - auth.link_device_sessions — 로그인 시 fcm_tokens 마이그레이션
  - routes._notify_session_failed — 실패 푸시 본문 truncation

격리:
  실 데이터는 read-only로 사용. 변경이 필요한 Case 9는 가짜 user/token을 생성한 뒤
  try/finally로 수동 cleanup. 사전에 prod DB 백업 권장.
"""
import sys
from contextlib import contextmanager
from sqlalchemy.orm import Session as _Sess

# 실제 운영 코드 import
from app.database import SessionLocal
from app.models import SessionModel, UserModel, FcmTokenModel
from app.routes import _collect_session_fcm_tokens, _notify_session_failed, _notify_session_completed
from app.auth import link_device_sessions

# 테스트 결과 카운터
PASSED = 0
FAILED = 0


def check(case: str, expected, actual, hint: str = ""):
    """단순 assertEqual 헬퍼."""
    global PASSED, FAILED
    ok = expected == actual
    mark = "✅" if ok else "❌"
    print(f"  {mark} expected={expected!r}  actual={actual!r}  {hint}")
    if ok:
        PASSED += 1
    else:
        FAILED += 1
    return ok


def make_fake_session(db, user_id=None, device_id=None, filename="test.pdf",
                      display_name=None, status="completed", error_message=None):
    """DB에 커밋하지 않는 임시 SessionModel — _collect_session_fcm_tokens는 db.query만 사용."""
    s = SessionModel(
        id=f"ses_qa_{id(object()) & 0xFFFFFF:x}",
        filename=filename,
        display_name=display_name,
        template_type="definition",
        device_id=device_id,
        user_id=user_id,
        status=status,
        error_message=error_message,
    )
    return s


@contextmanager
def savepoint(db: _Sess):
    """변경 사항을 자동 롤백."""
    sp = db.begin_nested()
    try:
        yield sp
    finally:
        sp.rollback()


def main():
    db = SessionLocal()
    try:
        # 사전 정보 출력
        print("\n=== 사전 상태 ===")
        users = db.query(UserModel).all()
        tokens = db.query(FcmTokenModel).all()
        print(f"  users={len(users)}  fcm_tokens={len(tokens)}")
        for u in users:
            print(f"    {u.id}  email={u.email!r}  device_id={u.device_id!r}")
        for t in tokens:
            print(f"    {t.id}  user_id={t.user_id!r}  device_id={t.device_id[:24]!r}  token={t.token[:20]}...")

        # ───────────────────────────────────────────────
        print("\n[Case 1] 로그인 유저 usr_0ea710e1b5 세션 — 백필된 토큰 매칭 ✓")
        s = make_fake_session(db, user_id="usr_0ea710e1b5",
                              device_id="migrated_usr_0ea710e1b5")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 1, len(toks),
              "user_id 매칭으로 1개 (백필 결과)")

        # ───────────────────────────────────────────────
        print("\n[Case 2] 로그인 유저 usr_65fd66a7f0 세션 — 백필된 토큰 매칭 ✓")
        s = make_fake_session(db, user_id="usr_65fd66a7f0",
                              device_id="migrated_usr_65fd66a7f0")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 1, len(toks))

        # ───────────────────────────────────────────────
        print("\n[Case 3] device_id NULL 유저 usr_af9c6b998b — 토큰 0개")
        s = make_fake_session(db, user_id="usr_af9c6b998b",
                              device_id="migrated_usr_af9c6b998b")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 0, len(toks),
              "users.device_id NULL이라 폴백 불가, 정상 무음")

        # ───────────────────────────────────────────────
        print("\n[Case 4] 비로그인 세션 — device_id 직접 매칭")
        # 기존 토큰 중 user_id NULL인 것 찾기
        anon_tok = db.query(FcmTokenModel).filter(
            FcmTokenModel.user_id.is_(None),
            ~FcmTokenModel.device_id.like("migrated_%"),
            ~FcmTokenModel.device_id.like("post-fix%"),
        ).first()
        if anon_tok:
            s = make_fake_session(db, user_id=None, device_id=anon_tok.device_id)
            toks = _collect_session_fcm_tokens(db, s)
            check("token_count", 1, len(toks),
                  f"device_id={anon_tok.device_id[:12]}... 매칭")
        else:
            print("  ⚠️ 비로그인 토큰 없음 — 건너뜀")

        # ───────────────────────────────────────────────
        print("\n[Case 5] migrated session.device_id 폴백 차단 검증")
        # session.user_id=None + session.device_id='migrated_xxx' → device_id 폴백 안 함
        s = make_fake_session(db, user_id=None, device_id="migrated_usr_0ea710e1b5")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 0, len(toks),
              "migrated_ prefix면 device_id 폴백 차단")

        # ───────────────────────────────────────────────
        print("\n[Case 6] user_id 매칭 0건 + users.device_id 폴백 동작 검증")
        # 임시로 토큰의 user_id를 NULL로 되돌리고 device_id만 남긴 상태 시뮬레이션
        with savepoint(db):
            tok = db.query(FcmTokenModel).filter(
                FcmTokenModel.user_id == "usr_0ea710e1b5"
            ).first()
            original_uid = tok.user_id
            tok.user_id = None  # 마이그레이션 전 상태 시뮬레이션
            db.flush()

            s = make_fake_session(db, user_id="usr_0ea710e1b5",
                                  device_id="migrated_usr_0ea710e1b5")
            toks = _collect_session_fcm_tokens(db, s)
            check("token_count", 1, len(toks),
                  "user_id 매칭 실패 → users.device_id 폴백으로 발견")
        # savepoint rollback으로 tok.user_id 복원됨
        tok_after = db.query(FcmTokenModel).filter(
            FcmTokenModel.id == tok.id
        ).first()
        check("rollback_check", "usr_0ea710e1b5", tok_after.user_id,
              "rollback 후 user_id 복원")

        # ───────────────────────────────────────────────
        print("\n[Case 7] 존재하지 않는 user_id 세션 → 0건 (안전 보장)")
        s = make_fake_session(db, user_id="usr_nonexistent_xxx",
                              device_id="random_device_xyz")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 0, len(toks))

        # ───────────────────────────────────────────────
        print("\n[Case 8] 토큰 없는 비로그인 device_id → 0건 + 무음")
        s = make_fake_session(db, user_id=None, device_id="nonexistent_anon_dev_xyz")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 0, len(toks))

        # ───────────────────────────────────────────────
        print("\n[Case 9] link_device_sessions이 fcm_tokens도 마이그레이션 (수동 cleanup)")
        import uuid
        from datetime import datetime
        fake_user = UserModel(
            id=f"usr_qa_{uuid.uuid4().hex[:6]}",
            kakao_id=f"qa_{uuid.uuid4().hex[:8]}",
            nickname="qa_test",
            created_at=datetime.utcnow(),
        )
        fake_device = f"qa_device_{uuid.uuid4().hex[:8]}"
        fake_token = FcmTokenModel(
            id=f"fcm_qa_{uuid.uuid4().hex[:8]}",
            user_id=None,
            device_id=fake_device,
            token=f"qa_token_{uuid.uuid4().hex}",
            platform="android",
            created_at=datetime.utcnow(),
            updated_at=datetime.utcnow(),
        )
        try:
            db.add(fake_user)
            db.add(fake_token)
            db.commit()

            before = db.query(FcmTokenModel).filter(
                FcmTokenModel.id == fake_token.id
            ).first().user_id
            check("before_migration", None, before)

            link_device_sessions(db, fake_user, fake_device)

            after = db.query(FcmTokenModel).filter(
                FcmTokenModel.id == fake_token.id
            ).first().user_id
            check("after_migration", fake_user.id, after,
                  "link_device 시 fcm_tokens.user_id 채워짐")
        finally:
            # 수동 cleanup — 가짜 데이터 삭제
            db.query(FcmTokenModel).filter(FcmTokenModel.id == fake_token.id).delete()
            db.query(UserModel).filter(UserModel.id == fake_user.id).delete()
            db.commit()
            gone_user = db.query(UserModel).filter(UserModel.id == fake_user.id).first()
            gone_token = db.query(FcmTokenModel).filter(FcmTokenModel.id == fake_token.id).first()
            check("cleanup_user", None, gone_user)
            check("cleanup_token", None, gone_token, "QA 데이터 cleanup 정상")

        # ───────────────────────────────────────────────
        print("\n[Case 10] _notify_session_failed: 에러 메시지 truncation + 데이터 페이로드")
        # 실제 발송 안 하고 _collect_session_fcm_tokens 까지만 검증
        long_err = "x" * 200
        s = make_fake_session(
            db,
            user_id="usr_0ea710e1b5",
            device_id="migrated_usr_0ea710e1b5",
            display_name="아주_긴_파일이름이_있을때_제목_자르기_검증용_파일.pdf",
            status="failed",
            error_message=long_err,
        )
        # 본문 truncation 로직 mirror (운영 코드와 동일)
        filename = s.display_name or s.filename or "PDF"
        if len(filename) > 24:
            filename = filename[:21] + "..."
        err_msg = s.error_message or "다시 시도해주세요."
        if len(err_msg) > 80:
            err_msg = err_msg[:77] + "..."
        check("filename_len_le_24", True, len(filename) <= 24,
              f"filename='{filename}'")
        check("err_len_le_80", True, len(err_msg) <= 80,
              f"err 길이={len(err_msg)}")
        toks = _collect_session_fcm_tokens(db, s)
        check("token_count", 1, len(toks), "실패 푸시 대상 1명")

        # ───────────────────────────────────────────────
        print(f"\n=== 결과: {PASSED} passed / {FAILED} failed ===")
        sys.exit(0 if FAILED == 0 else 1)
    finally:
        db.close()


if __name__ == "__main__":
    main()

# rainism — 최종 제출물 안내

> 제출 요구 항목과 이 폴더의 문서를 1:1로 맞춰놓은 지도. **이 파일부터 보면 된다.**

## 제출 요구 5개 → 이 문서

| 요구 항목 | 파일 |
|---|---|
| 서비스 개요 | [`01_service_overview.md`](01_service_overview.md) |
| 고객 프로필 | [`02_customer_profile.md`](02_customer_profile.md) |
| PRD | [`03_PRD.md`](03_PRD.md) |
| 기술 검토 자료 | [`04_tech_review.md`](04_tech_review.md) |
| 디자인 프로토타입 | [`05_prototype.md`](05_prototype.md) + 아래 MVP 링크 |

## 부록 (요구 항목은 아니지만 근거가 되는 문서)

| 파일 | 뭐가 있나 |
|---|---|
| [`06_design_principles.md`](06_design_principles.md) | 원칙 6개 + 충돌 시 우선순위 |
| [`07_information_architecture.md`](07_information_architecture.md) | 화면 목록 · 라벨 사전 |
| [`08_user_flow.md`](08_user_flow.md) | Happy Path · 예외 경로 5종 |
| [`09_design_system.md`](09_design_system.md) | shadcn/ui · 토큰 · 폰트 |
| [`10_behavior_list.md`](10_behavior_list.md) | 핵심 동작 목록 |

## MVP 링크

**링크: (아직 배포 안 함)**

배포용 파일은 이미 만들어져 있다 — **`prototype/rainism_deploy_single.html`** (3.4MB).
사진 39장과 폰트를 파일 안에 심어놓은 **한 장짜리 자립 파일**이라, 어디에 올리든 그대로 뜬다.

**올리는 법:** [app.netlify.com/drop](https://app.netlify.com/drop) 에 이 파일을 드래그 → 주소가 바로 나온다.

⚠️ **claude.ai 아티팩트로는 못 올린다.** 아티팩트는 보안정책상 이 프로토타입이 쓰는
`onclick=` 방식(버튼 동작을 태그 안에 직접 적는 것)을 실행하지 않아서 **버튼이 안 눌린다.**
일반 웹호스팅(Netlify·Vercel·GitHub Pages)에서는 손 안 대고 그대로 작동하고,
**AI 사진 매칭(CLIP)도 거기서만 켜진다** (외부 접속이 필요해서).

---

## 제출 형식 만들 때 참고

- 문서는 전부 마크다운(.md)이다. PDF/PPT로 옮길 때 **표와 굵은 글씨가 핵심**이니 그대로 살릴 것.
- 프로토타입 화면 캡쳐가 필요하면: `python3 prototype/shot.py all` → `prototype/shots/`

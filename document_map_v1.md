# rainism 문서 정본 지도 (Source of Truth Map)

> 2026-08-07 갱신 · **문서가 헷갈리면 여기부터 본다**
>
> ⚠️ **요구사항의 정본은 [`final-submission/03_PRD.md`](final-submission/03_PRD.md)다.** `submission/03_PRD.md`는 통합 전 원문이고, 2026-08-07 정합성 보정은 최종본에만 반영돼 있다. 둘이 다르면 최종본이 이긴다.

## 0. 지금의 제품 (현행 정답 · canonical)

**한 줄:** "날씨에 맞춰 내 취향대로 오늘 입을 코디를 아침마다 골라주는 앱." (= **분위기 매칭형**, 2026-07-09 확정)

| 항목 | 현행 정답 |
|---|---|
| 코어 동작 | 취향 퀴즈 → (선택)참고 사진 → **오늘 날씨+취향에 맞는 코디 사진 3개를 큐레이션 라이브러리에서 벡터 유사도로 검색** |
| 사진 출처 | **라이선스/큐레이션 라이브러리** · **실사진만**(AI 생성 노출 금지) |
| 배경제거 | **안 함(폐기)** — 옷을 조각내지 않음 |
| 탭 구조 | **3탭: 오늘(코어) · 날씨 · My**(비공개 기록 캘린더). 소셜/피드 없음 |
| 데이터 | `library_looks`·`reference_photos`·`recommendations`·`saved_looks` + **pgvector** |
| 스택 | Next.js(PWA)·Vercel·Supabase(+pgvector)·비전 LLM(오프라인 태깅)·임베딩 모델(🔬미정)·기상청 |
| "내 옷이 아님" 갭 | **수용+완화**(취향 퀴즈 + '오늘 입을 만한' 현실 코디) |

**최상위 권위 문서 = [`CLAUDE.md`](CLAUDE.md)**

---

## 1. 폴더 구조 (2026-07-13 재편)

```
rainism/
├── submission/           ← 제출용 5종 (여기가 최종 산출물)
├── research/           ← 고객·리서치 원자료
├── tech/           ← 현행 기술 문서 (구버전 제거됨)
├── prototype/      ← 작동하는 프로토타입 + 실사진 39장
├── seed_photos/    ← 라이브러리 시드 후보 이미지
└── _보관(구버전)/   ← 옷 조합형(피벗 이전) 폐기 문서. ⚠️ 참고 금지
```

---

## 2. 제출용 문서 (정본 · 여기를 먼저 본다)

| 문서 | 다루는 것 |
|---|---|
| [`submission/01_service_overview.md`](submission/01_service_overview.md) | 한 줄 정의·문제·동작·차별점·타깃·범위·수익모델·리스크 |
| [`submission/02_customer_profile.md`](submission/02_customer_profile.md) | 페르소나 "서연" + VOC 6테마 + 감정 지도 + 경쟁 앱 빈틈 (통합본) |
| [`submission/03_PRD.md`](submission/03_PRD.md) | **MVP PRD** — 목적·범위·FR·추천 규칙·제약·수용기준 (+ 부록 A 스파이크 / 부록 B 미결정) |
| [`submission/04_tech_review.md`](submission/04_tech_review.md) | 아키텍처·스택·추천 엔진·데이터모델·비용·라이브러리 소싱·규제·리스크 (통합본) |
| [`submission/05_prototype.md`](submission/05_prototype.md) | 프로토타입 안내·PRD 대응표·자리표시·MVP 링크 배포법 |

---

## 3. 근거·상세 문서

### research/ (고객·리서치)
| 문서 | 유효성 |
|---|---|
| `research/persona_seoyeon_v1.md` | 🟢 (2026-07-13 신모델 반영) |
| `research/voc_analysis_v1.md` | 🟢 |
| `research/emotion_map_v1.md` | 🟢 (2026-07-13 신모델 반영) |
| `research/rainism_ux_research_v1.md` | 🟡 문제정의·감정은 유효 / **§2 JTBD 문장은 낡음** — "가진 것 안에서"·"내 옷으로"는 옷 등록형(피벗 이전) 전제다. **JTBD 정본은 [`submission/06_design_principles.md` §②](submission/06_design_principles.md)**, 인용은 거기서 할 것 |
| `research/ux_standards_benchmark_v1.md` | 🟡 UX 표준·용어는 유효 / 옷장 온보딩 flow는 낡음 |
| `research/rainism_planning_research_notes_v1.md` | 🟡 VOC·문제정의·규제는 유효 / "내 옷"·배경제거는 낡음 |

### tech/ (전부 현행)
| 문서 | 다루는 것 |
|---|---|
| `tech/data_model_v2_mood_matching.md` | **데이터 정본** — 스키마·ERD·흐름·개선안 |
| `tech/tech_feasibility_v2_search.md` | 타당성·비용·규제·권고 |
| `tech/additional_tech_review_v1.md` | **갭 12항목 + 3 스파이크** (가장 최신 관점) |
| `tech/external_dependencies_v1.md` | 의존성 지도·SPOF·비용 롤업 |
| `tech/dependency_risk_mitigation_v1.md` | 과잉의존 완화·포트&어댑터 |
| `tech/library_sourcing_plan_v1.md` | **소싱 정본** — ~700장/350만원 |
| `tech/rainism_mvp_implementation_plan_v2.md` | Phase 0~4 게이트·임계경로 (**v2, 2026-07-13**: 스파이크①에 태그 대조군 / 기록탭·착용계측 신설 / AI생성 파일럿 삭제 / 안전태그 사람검수). v1은 `_보관(구버전)/` |
| `tech/outfit_rules_v1_summer_women.csv` | 날씨 하드필터 규칙 원본 |
| `tech/diagrams/*.html` | 데이터모델·외부의존성 다이어그램 |

---

## 4. 착수 전 미해결 "3 스파이크" (설계를 바꿀 수 있음) 🔴

> 상세: [`tech/additional_tech_review_v1.md`](tech/additional_tech_review_v1.md) · [PRD 부록 A](submission/03_PRD.md)

1. **임베딩 바이크오프** — "이미지 표현이 '무드'를 잡나?" (**가장 중요 · 제품의 상한**. FashionCLIP은 잠정 후보일 뿐 미검증)
2. **라이브러리 커버리지 매트릭스** — 셀별 최소 장수 → 총 목표 규모
3. **규제 체크** — PIPA(사진·위치 동의) + 2026.7 이미지 모더레이션

---

## 5. 아직 없는 문서 (보완하면 좋음)

1. **화면 설계·IA 문서** — 07_information_architecture + PRD 부록 C로 해소됨
2. **디자인 시스템** — 09_design_system + 04_tech_review로 해소됨
3. **취향 퀴즈 상세 설계** — 문항·앵커룩 매핑·`taste_vector` 도출 (스파이크① 결과에 의존)
4. **참고사진 업로드 UX + PIPA 처리** — 동의·보관·삭제 (스파이크③)
5. **검증 계획서** *(2026-08-07 신규)* — 몇 명에게 몇 주 돌리고, D1 리텐션이 몇 %면 계속 가고 몇 %면 접는가. PRD §4.2가 이걸 🔬로 열어뒀다. **유저가 정해야 한다.**

---

## 6. 폐기된 방향 (되살리기 금지) 🚫

핀터레스트 연동 · 웹/SNS 스크래핑 · 배경제거·의류 세그멘테이션 · 노출 라이브러리의 AI 생성 이미지 · 옷 조각 태깅·조합 스코어 · 요청마다 LLM 재랭킹 · 날씨 다매체 스크래핑 · 소셜/피드/커머스(검증 단계).

이 방향의 문서들은 [`_보관(구버전)/`](_보관(구버전)/)에 있다. **참고하지 말 것.**

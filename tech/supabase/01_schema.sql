-- rainism · library_looks 표 만들기
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 Run.
--
-- 근거: tech/data_model_v2_mood_matching.md 의 LIBRARY_LOOKS 설계를 그대로 따랐다.
--       새로 지어내지 않았다. 프로토타입에만 있던 필드 2개(safe·boots)만 덧붙였고,
--       그건 아래에 이유를 적어뒀다.

-- ── 임베딩용 확장. 지금은 안 쓰지만 나중에 컬럼만 살리면 되게 미리 켜둔다.
create extension if not exists vector;

create table if not exists library_looks (
  id            uuid primary key default gen_random_uuid(),

  -- ── 사진 ───────────────────────────────────────────────────
  image_path    text not null,           -- 사진 위치. 지금은 './proto_img/01.jpg' 같은 상대경로,
                                         -- 나중에 Storage로 옮기면 그 경로로 바뀐다
  thumb_path    text,                    -- 목록용 작은 사진. 없으면 image_path를 쓴다

  -- ── 🔴 합법성 근거 (RG-4). 비워두지 말 것 ────────────────────
  source_url     text,                   -- 어디서 왔나 (핀 주소 등)
  source_license text not null default 'unverified',
                                         -- 'unverified'  = 출처 확인 안 됨 → 🚫 배포 금지, 내 컴퓨터 데모 전용
                                         -- 'crowdpic-ext'= 크라우드픽 확장 라이선스
                                         -- 'creator'     = 크리에이터 직접 계약
                                         -- 'cc0'         = Unsplash/Pexels 등
                                         -- ⚠️ 'unverified' 인 사진은 인터넷에 올리면 안 된다 (RG-4)

  -- ── 보여줄 내용 ────────────────────────────────────────────
  name          text not null,           -- '비 오는 날 크림 블라우스'
  items         jsonb not null default '[]'::jsonb,
                                         -- ['크림 블라우스','화이트 미니스커트','레인부츠']
                                         -- 결정한 뒤 '옷장에서 꺼낼 것' 체크리스트가 된다 (FR-12)

  -- ── 취향 태그 (소프트랭킹용 — 틀려도 되는 것) ────────────────
  mood          text not null,           -- 미니멀 | 러블리 | 캐주얼 | 시크
  color_primary text not null,           -- 뉴트럴 | 다크 | 쿨톤 | 웜톤
  formality     smallint not null default 2,   -- 격식 0~5. 프로토타입은 1~3만 쓴다

  -- ── 🔴 날씨 태그 (하드필터용 — 틀리면 안 되는 것 · 원칙 2) ────
  temp_min      smallint not null,       -- 적용 체감온도 하한 (°C)
  temp_max      smallint not null,       -- 적용 체감온도 상한 (°C)
                                         -- 구간 근거 = tech/rainism_outfit_rules_v1_summer_women.csv [1]
                                         --   무더위·폭염 28↑ / 따뜻함 23–27 / 선선함 20–22 / 서늘 17–19
  rain_ok       boolean not null default false,   -- 비 오는 날 입어도 되나
  boots         boolean not null default false,   -- 레인부츠 포함. 이유 문장에 쓴다
                                                  -- ("레인부츠라 발도 안 젖어요")

  -- ── 추천 엔진용 ────────────────────────────────────────────
  is_safe       boolean not null default false,   -- '안전빵' — 3장 중 최소 1장은 이게 들어간다.
                                                  -- 화면 라벨은 "무난해요" (내부 용어 노출 금지)
  embedding     vector(512),             -- 분위기 임베딩. 🔬 어느 모델인지 미정(스파이크①) → 지금은 비워둔다

  -- ── 운영 ───────────────────────────────────────────────────
  active        boolean not null default true,    -- false면 추천에서 빠진다 (모더레이션·회수)
  created_at    timestamptz not null default now(),

  -- 온도 구간이 뒤집히면 하드필터가 조용히 아무것도 안 거른다. 막아둔다.
  constraint temp_range_sane check (temp_min <= temp_max)
);

-- 하드필터가 매 요청 도는 조건. 사진이 700장이 되면 이게 있고 없고가 갈린다.
create index if not exists library_looks_filter_idx
  on library_looks (active, rain_ok, temp_min, temp_max);

-- ── 누가 읽고 쓸 수 있나 ────────────────────────────────────
alter table library_looks enable row level security;

-- 라이브러리는 '보여주려고' 있는 자산이라 읽기는 누구나. 단 내린 사진(active=false)은 빼고.
drop policy if exists "library readable" on library_looks;
create policy "library readable" on library_looks
  for select using (active = true);

-- 🚫 쓰기 정책은 만들지 않는다. 적재는 서버 키(service_role)로만 —
--    브라우저에서 라이브러리를 고칠 수 있으면 안 된다.

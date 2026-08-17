-- rainism · 빈 Supabase 프로젝트를 처음부터 채운다 (2026-08-17)
--
-- 01~06 을 순서대로 합친 것이다. 새 프로젝트(fzmyqsvxitnvfxwqkxsd)에 한 번만 돌린다.
-- 순서가 중요하다: 표 만들기 → 39장 → 안전장치 → 컨셉 개편 → 85장 → 기온·비 재태깅.
--
-- ⚠️ 두 번 돌리지 말 것. 02(39장)에는 중복 막는 장치가 없어서 39장이 또 들어간다.
--    (중복 막는 색인은 03 에서 생기고, 05 만 그 보호를 받는다)


-- ==================================================================
-- 01_schema.sql
-- ==================================================================
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
  mood          text not null,           -- 고프코어 | 발레코어 | Y2K | 모리룩  (2026-08-16 개편)
  color_primary text not null,           -- 뉴트럴 | 다크 | 쿨톤 | 웜톤
  formality     smallint not null default 2,   -- 격식 0~5. 프로토타입은 1~3만 쓴다

  -- ── 🔴 날씨 태그 (하드필터용 — 틀리면 안 되는 것 · 원칙 2) ────
  temp_min      smallint not null,       -- 적용 체감온도 하한 (°C)
  temp_max      smallint not null,       -- 적용 체감온도 상한 (°C)
                                         -- 구간 근거 = tech/rainism_outfit_rules_v2_allseason_women.csv [1]
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


-- ==================================================================
-- 02_seed_39.sql
-- ==================================================================
-- rainism · 지금 프로토타입에 박혀 있는 코디를 표에 넣는다
-- 01_schema.sql 을 먼저 돌린 뒤, 이 파일을 SQL Editor 에 붙여넣고 Run.
--
-- ⚠️ 손으로 쓴 게 아니라 export_looks.py 가 프로토타입에서 뽑아낸 것이다.
--    프로토타입이 바뀌면 다시 돌린다.
--
-- 🔴 source_license 가 전부 'unverified' 다 — 출처가 확인되지 않았다는 뜻이고,
--    그래서 이 사진들은 인터넷에 올리면 안 된다 (RG-4).

insert into library_looks
  (image_path, name, items, mood, color_primary, formality,
   temp_min, temp_max, rain_ok, boots, is_safe)
values
  ('./proto_img/01.jpg', '비 오는 날 크림 블라우스', '["크림 블라우스", "화이트 미니스커트", "레인부츠"]'::jsonb, '러블리', '웜톤', 2, 23, 27, true, true, false),
  ('./proto_img/02.jpg', '그레이 톤온톤 캐주얼', '["그레이 롱슬리브", "카고 쇼츠", "스니커즈"]'::jsonb, '캐주얼', '뉴트럴', 1, 23, 27, false, false, true),
  ('./proto_img/03.jpg', '화이트 캐미 × 블랙 와이드', '["화이트 캐미솔", "블랙 와이드팬츠", "플랫"]'::jsonb, '미니멀', '다크', 2, 28, 45, false, false, true),
  ('./proto_img/04.jpg', '비 오는 날 데님 셔츠 레이어드', '["데님 셔츠", "그레이 스웨트", "쇼츠", "레인부츠"]'::jsonb, '캐주얼', '쿨톤', 1, 20, 22, true, true, false),
  ('./proto_img/05.jpg', '비 오는 날 미니멀 롱스커트', '["그레이 티", "블랙 롱스커트", "샌들"]'::jsonb, '미니멀', '다크', 2, 23, 27, true, false, true),
  ('./proto_img/06.jpg', '브라운 와이드 캐주얼', '["화이트 티", "브라운 와이드", "옐로 스니커즈"]'::jsonb, '캐주얼', '웜톤', 1, 28, 45, false, false, false),
  ('./proto_img/07.jpg', '블루 스트라이프 오버셔츠', '["스트라이프 오버셔츠", "화이트 팬츠"]'::jsonb, '캐주얼', '쿨톤', 1, 20, 22, false, false, false),
  ('./proto_img/08.jpg', '블랙 톤온톤 미디', '["크롭 롱슬리브", "블랙 미디스커트", "스니커즈"]'::jsonb, '시크', '다크', 2, 23, 27, false, false, true),
  ('./proto_img/09.jpg', '청록 티어드 스커트', '["그레이 탱크", "청록 티어드 스커트", "부츠"]'::jsonb, '캐주얼', '쿨톤', 2, 28, 45, false, false, false),
  ('./proto_img/10.jpg', '블루 브이넥 × 데님', '["블루 브이넥 티", "데님 와이드"]'::jsonb, '캐주얼', '쿨톤', 1, 23, 27, false, false, false),
  ('./proto_img/11.jpg', '서늘한 비, 올리브 가디건', '["올리브 가디건", "니트", "체크 스커트", "로퍼"]'::jsonb, '러블리', '웜톤', 3, 17, 19, true, false, false),
  ('./proto_img/12.jpg', '올리브 × 브라운 버뮤다', '["올리브 가디건", "화이트 탑", "브라운 버뮤다", "부츠"]'::jsonb, '시크', '웜톤', 2, 23, 27, false, false, false),
  ('./proto_img/13.jpg', '하늘색 가디건 러블리', '["하늘 가디건", "레이스 탑", "러플 스커트"]'::jsonb, '러블리', '쿨톤', 2, 20, 22, false, false, false),
  ('./proto_img/14.jpg', '블랙 블레이저 × 데님', '["크롭 블레이저", "그레이 캐미", "데님 스트레이트"]'::jsonb, '시크', '다크', 3, 23, 27, false, false, true),
  ('./proto_img/15.jpg', '블루 가디건 × 카프리', '["크롭 가디건", "탑", "카프리 레깅스", "플랫"]'::jsonb, '시크', '쿨톤', 3, 20, 22, false, false, false),
  ('./proto_img/16.jpg', '화이트 롱슬리브 × 배기진', '["화이트 롱슬리브", "배기진", "벨트"]'::jsonb, '캐주얼', '뉴트럴', 1, 23, 27, false, false, true),
  ('./proto_img/17.jpg', '블랙 니트탑 × 와이드 데님', '["블랙 니트 민소매", "데님 와이드", "플립플롭"]'::jsonb, '미니멀', '다크', 2, 28, 45, false, false, true),
  ('./proto_img/18.jpg', '옐로 카고 캐주얼', '["그레이 베이비티", "옐로 카고"]'::jsonb, '캐주얼', '웜톤', 1, 28, 45, false, false, false),
  ('./proto_img/19.jpg', '크림 톤온톤 미니멀', '["오버 니트", "화이트 탑", "크림 와이드"]'::jsonb, '미니멀', '뉴트럴', 3, 20, 22, false, false, true),
  ('./proto_img/20.jpg', '슬립 드레스 × 후디', '["네이비 후디", "화이트 슬립 드레스", "부츠"]'::jsonb, '시크', '뉴트럴', 2, 20, 22, false, false, false),
  ('./proto_img/21.jpg', '크림 가디건 × 버뮤다', '["크림 가디건", "프린트 캐미", "버뮤다", "메리제인"]'::jsonb, '러블리', '웜톤', 2, 23, 27, false, false, false),
  ('./proto_img/22.jpg', '블랙 니트 원피스 × 레인부츠', '["블랙 니트 원피스", "레드 스카프", "레인부츠"]'::jsonb, '시크', '다크', 2, 17, 19, true, true, false),
  ('./proto_img/23.jpg', '비 오는 날 블랙 셔츠 × 레인부츠', '["블랙 오버셔츠", "네이비 쇼츠", "레인부츠", "캡"]'::jsonb, '시크', '다크', 1, 23, 27, true, true, true),
  ('./proto_img/24.jpg', '스트릿 니트탑 레이어드', '["믹스 니트탑", "쇼츠", "니삭스", "스니커즈"]'::jsonb, '캐주얼', '웜톤', 1, 28, 45, false, false, false),
  ('./proto_img/25.jpg', '플로럴 후드 × 튤스커트', '["플로럴 후드", "튤 스커트"]'::jsonb, '러블리', '웜톤', 2, 20, 22, false, false, false),
  ('./proto_img/26.jpg', '레인재킷 × 레인부츠', '["블루 레인재킷", "블랙 쇼츠", "레인부츠"]'::jsonb, '캐주얼', '쿨톤', 1, 20, 22, true, true, true),
  ('./proto_img/27.jpg', '비 오는 날 퍼프 블라우스', '["화이트 퍼프 블라우스", "데님 쇼츠", "레인부츠"]'::jsonb, '러블리', '뉴트럴', 2, 23, 27, true, true, false),
  ('./proto_img/28.jpg', '그레이 니트 원피스 × 레인부츠', '["그레이 니트 원피스", "레드 반다나", "레인부츠"]'::jsonb, '시크', '다크', 2, 17, 19, true, true, false),
  ('./proto_img/30.jpg', '옐로 베이비티 × 스웻쇼츠', '["옐로 베이비티", "네이비 스웻 쇼츠", "스니커즈"]'::jsonb, '캐주얼', '웜톤', 1, 23, 27, false, false, false),
  ('./proto_img/31.jpg', '여름 비, 자수 블라우스 × 깅엄', '["화이트 자수 블라우스", "깅엄 쇼츠", "레인부츠"]'::jsonb, '러블리', '웜톤', 2, 23, 27, true, true, false),
  ('./proto_img/32.jpg', '하늘색 롱슬리브 × 차콜 쇼츠', '["하늘 롱슬리브", "차콜 쇼츠", "블랙 부츠"]'::jsonb, '캐주얼', '쿨톤', 1, 23, 27, false, false, false),
  ('./proto_img/33.jpg', '비 오는 골목, 크림 블라우스', '["크림 블라우스", "연청 데님", "크림 레인부츠"]'::jsonb, '러블리', '웜톤', 2, 23, 27, true, true, false),
  ('./proto_img/34.jpg', '올블랙 × 레인부츠', '["블랙 후디", "블랙 팬츠", "블랙 레인부츠"]'::jsonb, '시크', '다크', 1, 20, 22, true, true, true),
  ('./proto_img/35.jpg', '화이트 레이어드 × 핑크 레인부츠', '["화이트 블라우스", "화이트 스커트", "핑크 레인부츠"]'::jsonb, '러블리', '뉴트럴', 2, 23, 27, true, true, false),
  ('./proto_img/36.jpg', '버터색 원피스 × 블랙 레인부츠', '["크림 코튼 원피스", "블랙 롱 레인부츠"]'::jsonb, '미니멀', '뉴트럴', 2, 23, 27, true, true, true),
  ('./proto_img/37.jpg', '화이트 티 × 블랙 버뮤다', '["화이트 반팔 티", "블랙 버뮤다", "블랙 부츠"]'::jsonb, '미니멀', '다크', 1, 23, 27, false, false, true),
  ('./proto_img/38.jpg', '레이스 캐미 × 레이스 버뮤다', '["화이트 레이스 캐미", "레이스 버뮤다", "스니커즈"]'::jsonb, '러블리', '뉴트럴', 2, 28, 45, false, false, false),
  ('./proto_img/39.jpg', '화이트 긴팔 × 연두 티어드 스커트', '["화이트 롱슬리브", "연두 티어드 스커트", "화이트 뮬"]'::jsonb, '러블리', '웜톤', 2, 20, 22, false, false, false),
  ('./proto_img/40.jpg', '비 오는 날 크림 셔츠 × 네이비 레인부츠', '["크림 셔츠", "화이트 쇼츠", "네이비 레인부츠"]'::jsonb, '러블리', '웜톤', 2, 23, 27, true, true, false);


-- ==================================================================
-- 03_tagging_gate.sql
-- ==================================================================
-- rainism · "태그 안 붙은 코디는 화면에 못 나온다" 안전장치
-- 01_schema.sql 다음에 한 번 돌린다.
--
-- 왜 필요한가:
--   핀터레스트에서 사진을 받아오면 제목과 사진만 온다. 무드·색은 안 온다.
--   그 상태로 라이브러리에 들어가면 추천에 섞여 나오는데, 그게 조용히 틀리는 방식이다.
--   그래서 받아온 사진은 active=false 로 들어오고, 태그를 채워야만 켤 수 있게 막는다.
--   화면 코드가 아니라 표에 규칙을 건다 — 코드로 막으면 까먹는 경로가 생긴다.

-- 받아온 직후엔 무드·색을 모르므로 비워둘 수 있어야 한다
alter table library_looks alter column mood          drop not null;
alter table library_looks alter column color_primary drop not null;

-- 대신 켜는 순간(active=true) 필요한 게 다 있는지 검사한다.
-- 🔴 온도·비는 하드필터에 쓰인다. 이게 비어 있으면 "비 오는 날 비 부적합 코디"가 나온다.
alter table library_looks drop constraint if exists ready_to_show;
alter table library_looks add  constraint ready_to_show check (
  not active or (
    mood          is not null and
    color_primary is not null and
    temp_min      is not null and
    temp_max      is not null
  )
);

-- 같은 핀을 두 번 받아오는 걸 막는다 (출처가 있는 것만)
create unique index if not exists library_looks_source_uniq
  on library_looks (source_url) where source_url is not null;


-- ==================================================================
-- 04_concepts_v2.sql
-- ==================================================================
-- rainism · 컨셉 4개 개편 (2026-08-16)
-- 온보딩 질문이 미니멀/러블리/캐주얼/시크 → 고프코어/발레코어/Y2K/모리룩 으로 바뀌었다.
-- 표의 mood 값을 안 바꾸면 화면과 데이터가 어긋나 추천이 사실상 랜덤이 된다.
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 Run.

update library_looks set mood = case image_path
  when './proto_img/01.jpg' then '모리룩'
  when './proto_img/02.jpg' then 'Y2K'
  when './proto_img/03.jpg' then 'Y2K'
  when './proto_img/04.jpg' then '고프코어'
  when './proto_img/05.jpg' then '모리룩'
  when './proto_img/06.jpg' then '고프코어'
  when './proto_img/07.jpg' then '모리룩'
  when './proto_img/08.jpg' then '발레코어'
  when './proto_img/09.jpg' then 'Y2K'
  when './proto_img/10.jpg' then '모리룩'
  when './proto_img/11.jpg' then '모리룩'
  when './proto_img/12.jpg' then 'Y2K'
  when './proto_img/13.jpg' then '발레코어'
  when './proto_img/14.jpg' then 'Y2K'
  when './proto_img/15.jpg' then '모리룩'
  when './proto_img/16.jpg' then '모리룩'
  when './proto_img/17.jpg' then 'Y2K'
  when './proto_img/18.jpg' then '고프코어'
  when './proto_img/19.jpg' then '모리룩'
  when './proto_img/20.jpg' then '발레코어'
  when './proto_img/21.jpg' then '발레코어'
  when './proto_img/22.jpg' then '발레코어'
  when './proto_img/23.jpg' then '고프코어'
  when './proto_img/24.jpg' then 'Y2K'
  when './proto_img/25.jpg' then '발레코어'
  when './proto_img/26.jpg' then '고프코어'
  when './proto_img/27.jpg' then '모리룩'
  when './proto_img/28.jpg' then 'Y2K'
  when './proto_img/30.jpg' then 'Y2K'
  when './proto_img/31.jpg' then '모리룩'
  when './proto_img/32.jpg' then 'Y2K'
  when './proto_img/33.jpg' then '고프코어'
  when './proto_img/34.jpg' then '고프코어'
  when './proto_img/35.jpg' then '발레코어'
  when './proto_img/36.jpg' then '모리룩'
  when './proto_img/37.jpg' then 'Y2K'
  when './proto_img/38.jpg' then '발레코어'
  when './proto_img/39.jpg' then '모리룩'
  when './proto_img/40.jpg' then '모리룩'
  else mood end;

-- 확인: 4개 컨셉이 몇 장씩인지
select mood, count(*) from library_looks group by mood order by count(*) desc;


-- ==================================================================
-- 05_import_pinterest_85.sql
-- ==================================================================
-- user12_4 의 핀터레스트 보드 4개에서 받아온 코디 85장 (2026-08-17)
-- 컨셉은 보드 이름 그대로. 색·기온·비는 사진을 보고 정했다 — 에이전트가 정한 값이다.
-- 🔴 rain_ok 는 레인부츠·방수 재킷이 눈에 보이는 것만 true 로 뒀다. 나머지는 전부 false.
--    (비 아닌 옷을 비 오는 날에 올리는 쪽이 그 반대보다 훨씬 나쁘다 — 원칙 2)
-- 🔴 마네킹·제품컷·잡지컷·한겨울 사진 14장은 active=false 로 넣었다. 표엔 있고 화면엔 안 나온다.
-- 🔴 source_license 는 'unverified' 다. 인터넷에 올리면 안 된다 (RG-4).

insert into library_looks
  (image_path, name, source_url, mood, color_primary,
   temp_min, temp_max, rain_ok, boots, active)
values
  ('./proto_img/41.jpg', '코디 41', 'https://www.pinterest.com/pin/891994270143922692/', '고프코어', '쿨톤', 23, 27, true, true, true),
  ('./proto_img/42.jpg', '코디 42', 'https://www.pinterest.com/pin/891994270143922732/', '고프코어', '다크', 23, 27, false, false, true),
  ('./proto_img/43.jpg', '코디 43', 'https://www.pinterest.com/pin/891994270143922721/', '고프코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/44.jpg', '코디 44', 'https://www.pinterest.com/pin/891994270143922695/', '고프코어', '다크', 20, 22, false, false, true),
  ('./proto_img/45.jpg', '코디 45', 'https://www.pinterest.com/pin/891994270143919844/', '고프코어', '웜톤', 23, 27, true, true, true),
  ('./proto_img/46.jpg', '코디 46', 'https://www.pinterest.com/pin/891994270143919889/', '고프코어', '뉴트럴', 23, 27, true, true, true),
  ('./proto_img/47.jpg', '코디 47', 'https://www.pinterest.com/pin/891994270143922709/', '고프코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/48.jpg', 'We discover new brands. For collaboration inquiries, please ', 'https://www.pinterest.com/pin/891994270143919851/', '고프코어', '웜톤', 20, 22, true, false, true),
  ('./proto_img/49.jpg', '코디 49', 'https://www.pinterest.com/pin/891994270143919856/', '고프코어', '뉴트럴', 20, 22, true, true, true),
  ('./proto_img/50.jpg', 'ojos global 2022 high summer collection “hypoxic zone”', 'https://www.pinterest.com/pin/891994270143919743/', '고프코어', '뉴트럴', 20, 22, true, false, true),
  ('./proto_img/51.jpg', 'Ready to face the wild, or just another Monday. 🏔️❄️ Functio', 'https://www.pinterest.com/pin/891994270143922698/', '고프코어', '뉴트럴', 20, 22, false, false, true),
  ('./proto_img/52.jpg', 'Y2K energy meets outdoor freedom 🌈💛 Bright, bold, and a litt', 'https://www.pinterest.com/pin/891994270143919852/', '고프코어', '웜톤', 23, 27, true, true, true),
  ('./proto_img/53.jpg', 'Functional woven fabrics for outdoor apparel, jackets, windb', 'https://www.pinterest.com/pin/891994270143922690/', '고프코어', '웜톤', 17, 19, true, false, true),
  ('./proto_img/54.jpg', '코디 54', 'https://www.pinterest.com/pin/891994270143922699/', '고프코어', '뉴트럴', 20, 22, true, false, true),
  ('./proto_img/55.jpg', '코디 55', 'https://www.pinterest.com/pin/891994270143922724/', '고프코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/56.jpg', '코디 56', 'https://www.pinterest.com/pin/891994270143919839/', '고프코어', '뉴트럴', 20, 22, true, false, true),
  ('./proto_img/57.jpg', 'Cocok saat jalan santai dan kegiatan outdoor', 'https://www.pinterest.com/pin/891994270143919732/', '고프코어', '다크', 20, 22, true, false, true),
  ('./proto_img/58.jpg', '코디 58', 'https://www.pinterest.com/pin/891994270143922660/', '고프코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/59.jpg', '코디 59', 'https://www.pinterest.com/pin/891994270143919742/', '고프코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/60.jpg', '코디 60', 'https://www.pinterest.com/pin/891994270143919735/', '고프코어', '뉴트럴', 20, 22, false, false, true),
  ('./proto_img/61.jpg', '코디 61', 'https://www.pinterest.com/pin/891994270143919701/', '발레코어', '웜톤', 23, 27, false, false, true),
  ('./proto_img/62.jpg', '코디 62', 'https://www.pinterest.com/pin/891994270143919633/', '발레코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/63.jpg', '코디 63', 'https://www.pinterest.com/pin/891994270143919704/', '발레코어', '웜톤', 23, 27, false, false, true),
  ('./proto_img/64.jpg', '코디 64', 'https://www.pinterest.com/pin/891994270143919628/', '발레코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/65.jpg', '코디 65', 'https://www.pinterest.com/pin/891994270143919630/', '발레코어', '쿨톤', 23, 27, false, false, true),
  ('./proto_img/66.jpg', '코디 66', 'https://www.pinterest.com/pin/891994270143919624/', '발레코어', '뉴트럴', 20, 22, false, false, true),
  ('./proto_img/67.jpg', '코디 67', 'https://www.pinterest.com/pin/891994270143919520/', '발레코어', '쿨톤', 23, 27, false, false, true),
  ('./proto_img/68.jpg', '코디 68', 'https://www.pinterest.com/pin/891994270143919615/', '발레코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/69.jpg', '코디 69', 'https://www.pinterest.com/pin/891994270143919612/', '발레코어', '웜톤', 28, 45, false, false, true),
  ('./proto_img/70.jpg', '#coquette #style #fashion #outfits #aesthetic ♡', 'https://www.pinterest.com/pin/891994270143919611/', '발레코어', '웜톤', 23, 27, false, false, true),
  ('./proto_img/71.jpg', 'b-side', 'https://www.pinterest.com/pin/891994270143919604/', '발레코어', '쿨톤', 23, 27, false, false, true),
  ('./proto_img/72.jpg', '코디 72', 'https://www.pinterest.com/pin/891994270143919602/', '발레코어', '뉴트럴', 28, 45, false, false, true),
  ('./proto_img/73.jpg', '코디 73', 'https://www.pinterest.com/pin/891994270143919543/', '발레코어', '웜톤', 23, 27, false, false, true),
  ('./proto_img/74.jpg', '코디 74', 'https://www.pinterest.com/pin/891994270143919524/', '발레코어', '웜톤', 23, 27, false, false, true),
  ('./proto_img/75.jpg', '[레이이드템🩰/핏보장 ] 코코 사선 프릴 캉캉 뷔스띠에 나시  /데일리룩 데이트룩 오피스룩 하객룩 여행룩 바', 'https://www.pinterest.com/pin/891994270143919515/', '발레코어', '뉴트럴', 23, 27, false, false, false),
  ('./proto_img/76.jpg', '#outfits', 'https://www.pinterest.com/pin/891994270143919513/', '발레코어', '웜톤', 23, 27, false, false, false),
  ('./proto_img/77.jpg', '코디 77', 'https://www.pinterest.com/pin/891994270143919512/', '발레코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/78.jpg', '[요정무드/속바지내장] 페어리 엠보 레이스 캉캉 미니스커트 ❤ 발레코어 프릴 티어드 치마 (2color)', 'https://www.pinterest.com/pin/891994270143919485/', '발레코어', '뉴트럴', 28, 45, false, false, true),
  ('./proto_img/79.jpg', '[색감..🤍] 소프 발레코어 레이스 긴팔티', 'https://www.pinterest.com/pin/891994270143919484/', '발레코어', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/80.jpg', '코디 80', 'https://www.pinterest.com/pin/891994270143919482/', '발레코어', '웜톤', 23, 27, false, false, true),
  ('./proto_img/81.jpg', '코디 81', 'https://www.pinterest.com/pin/891994270143918958/', 'Y2K', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/82.jpg', '코디 82', 'https://www.pinterest.com/pin/891994270143918941/', 'Y2K', '웜톤', 20, 22, false, false, true),
  ('./proto_img/83.jpg', '코디 83', 'https://www.pinterest.com/pin/891994270143918967/', 'Y2K', '쿨톤', 28, 45, false, false, true),
  ('./proto_img/84.jpg', '코디 84', 'https://www.pinterest.com/pin/891994270143919439/', 'Y2K', '다크', 23, 27, false, false, false),
  ('./proto_img/85.jpg', '코디 85', 'https://www.pinterest.com/pin/891994270143919452/', 'Y2K', '웜톤', 23, 27, false, false, false),
  ('./proto_img/86.jpg', 'via stalgivc on tumblr', 'https://www.pinterest.com/pin/891994270143918950/', 'Y2K', '다크', 23, 27, false, false, true),
  ('./proto_img/87.jpg', '코디 87', 'https://www.pinterest.com/pin/891994270143918963/', 'Y2K', '다크', 20, 22, false, false, true),
  ('./proto_img/88.jpg', '코디 88', 'https://www.pinterest.com/pin/891994270143918972/', 'Y2K', '다크', 28, 45, false, false, false),
  ('./proto_img/89.jpg', '코디 89', 'https://www.pinterest.com/pin/891994270143918969/', 'Y2K', '뉴트럴', 28, 45, false, false, true),
  ('./proto_img/90.jpg', '코디 90', 'https://www.pinterest.com/pin/891994270143918989/', 'Y2K', '뉴트럴', 28, 45, false, false, false),
  ('./proto_img/91.jpg', '코디 91', 'https://www.pinterest.com/pin/891994270143918976/', 'Y2K', '뉴트럴', 23, 27, false, false, false),
  ('./proto_img/92.jpg', 'outfit idea outfit inspo 2000s fashion inspo 2010s tumblr ae', 'https://www.pinterest.com/pin/891994270143918904/', 'Y2K', '웜톤', 20, 22, false, false, true),
  ('./proto_img/93.jpg', '코디 93', 'https://www.pinterest.com/pin/891994270143918945/', 'Y2K', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/94.jpg', '코디 94', 'https://www.pinterest.com/pin/891994270143918980/', 'Y2K', '뉴트럴', 28, 45, false, false, false),
  ('./proto_img/95.jpg', '코디 95', 'https://www.pinterest.com/pin/891994270143918922/', 'Y2K', '다크', 20, 22, false, false, true),
  ('./proto_img/96.jpg', '2026 New Y2K Spicy Girl Contrast Color Collar Polo Shirt, Pi', 'https://www.pinterest.com/pin/891994270143918906/', 'Y2K', '웜톤', 28, 45, false, false, false),
  ('./proto_img/97.jpg', '코디 97', 'https://www.pinterest.com/pin/891994270143918917/', 'Y2K', '다크', 28, 45, false, false, false),
  ('./proto_img/98.jpg', '오리지널 뉴 스프링 걸 여성 펑크 리벳 체인 나비 튜브탑 메쉬 셔츠 불규칙 플리츠 스커트 타이다이 스커트 슈', 'https://www.pinterest.com/pin/891994270143918937/', 'Y2K', '다크', 23, 27, false, false, true),
  ('./proto_img/99.jpg', 'Material: Polyester 100% 	Model: 171cm(78/58/86)/착용 사이즈 S   ', 'https://www.pinterest.com/pin/891994270143918902/', 'Y2K', '웜톤', 20, 22, false, false, true),
  ('./proto_img/100.jpg', 'Material: Polyester 100% Model: 171cm(78/58/86)/착용 사이즈 XS 흉상', 'https://www.pinterest.com/pin/891994270143918899/', 'Y2K', '다크', 23, 27, false, false, true),
  ('./proto_img/101.jpg', 'Karrram Japanese Y2k Rhinestones T-shirt Vintage Harajuku Di', 'https://www.pinterest.com/pin/891994270143918898/', 'Y2K', '웜톤', 28, 45, false, false, true),
  ('./proto_img/102.jpg', '코디 102', 'https://www.pinterest.com/pin/891994270143918484/', '모리룩', '웜톤', 28, 45, false, false, true),
  ('./proto_img/103.jpg', '코디 103', 'https://www.pinterest.com/pin/891994270143918458/', '모리룩', '뉴트럴', 23, 27, false, false, false),
  ('./proto_img/104.jpg', '코디 104', 'https://www.pinterest.com/pin/891994270143918466/', '모리룩', '뉴트럴', 17, 19, false, false, true),
  ('./proto_img/105.jpg', 'issue 019', 'https://www.pinterest.com/pin/891994270143918509/', '모리룩', '다크', 17, 19, false, false, false),
  ('./proto_img/106.jpg', '[44~77/2컬러] 코티지 스모크 프릴 레이어드 뷔스티에 프릴뷔스티에 레이어드탑 스모크탑 캉캉탑 빈티지룩 ', 'https://www.pinterest.com/pin/891994270143918503/', '모리룩', '뉴트럴', 23, 27, false, false, false),
  ('./proto_img/107.jpg', '코디 107', 'https://www.pinterest.com/pin/891994270143918498/', '모리룩', '웜톤', 20, 22, false, false, true),
  ('./proto_img/108.jpg', '코디 108', 'https://www.pinterest.com/pin/891994270143918495/', '모리룩', '쿨톤', 20, 22, false, false, true),
  ('./proto_img/109.jpg', '코디 109', 'https://www.pinterest.com/pin/891994270143918490/', '모리룩', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/110.jpg', '코디 110', 'https://www.pinterest.com/pin/891994270143918486/', '모리룩', '웜톤', 28, 45, false, false, true),
  ('./proto_img/111.jpg', '코디 111', 'https://www.pinterest.com/pin/891994270143918483/', '모리룩', '쿨톤', 23, 27, false, false, true),
  ('./proto_img/112.jpg', '코디 112', 'https://www.pinterest.com/pin/891994270143918479/', '모리룩', '뉴트럴', 28, 45, false, false, true),
  ('./proto_img/113.jpg', '코디 113', 'https://www.pinterest.com/pin/891994270143918477/', '모리룩', '다크', 23, 27, false, false, true),
  ('./proto_img/114.jpg', '[레이어드템/모리룩🫧] 카나 플라워 빈티지 주름 플리츠 캉캉 끈조절 나시 미디 원피스 - 2color', 'https://www.pinterest.com/pin/891994270143918476/', '모리룩', '쿨톤', 20, 22, false, false, true),
  ('./proto_img/115.jpg', '코디 115', 'https://www.pinterest.com/pin/891994270143918474/', '모리룩', '뉴트럴', 20, 22, false, false, true),
  ('./proto_img/116.jpg', 'rei and leeseo', 'https://www.pinterest.com/pin/891994270143918471/', '모리룩', '다크', 20, 22, false, false, true),
  ('./proto_img/117.jpg', '코디 117', 'https://www.pinterest.com/pin/891994270143918469/', '모리룩', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/118.jpg', '코디 118', 'https://www.pinterest.com/pin/891994270143918465/', '모리룩', '웜톤', 17, 19, false, false, true),
  ('./proto_img/119.jpg', '코디 119', 'https://www.pinterest.com/pin/891994270143918463/', '모리룩', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/120.jpg', '[퀄보장✨/모리룩] 빈티지 플라워자수 프릴 캉캉 롱스커트', 'https://www.pinterest.com/pin/891994270143918461/', '모리룩', '뉴트럴', 17, 19, false, false, true),
  ('./proto_img/121.jpg', '하트단추🖤 도트/둥큰카라 모리룩 반팔 블라우스(1col) 성희주도트블라우스', 'https://www.pinterest.com/pin/891994270143918460/', '모리룩', '뉴트럴', 23, 27, false, false, true),
  ('./proto_img/122.jpg', '🩵허리조절/핏보장 #레이어드 #모리룩 빈티지체크 쉬폰 캉캉 미디 스커트(2col) 미아체크스커트', 'https://www.pinterest.com/pin/891994270143918459/', '모리룩', '뉴트럴', 20, 22, false, false, true),
  ('./proto_img/123.jpg', '코디 123', 'https://www.pinterest.com/pin/891994270143918457/', '모리룩', '웜톤', 23, 27, false, false, true),
  ('./proto_img/124.jpg', '#y2k #tiemcuameo_meows #2hand #thrift #sawako #shoujo #core ', 'https://www.pinterest.com/pin/891994270143918455/', '모리룩', '뉴트럴', 23, 27, false, false, false),
  ('./proto_img/125.jpg', '💙🤍도트프릴/러블리 #모리룩 데님 소매 롤업 반팔 블라우스(2col) 청도트블라우스', 'https://www.pinterest.com/pin/891994270143918454/', '모리룩', '뉴트럴', 23, 27, false, false, true)
-- 중복 막는 색인이 '출처가 있는 줄만' 걸린 부분색인이라(03_tagging_gate.sql)
-- 여기서도 같은 조건을 적어줘야 한다. 안 적으면 42P10 으로 튕긴다.
on conflict (source_url) where source_url is not null do nothing;

select mood, count(*) filter (where active) as 화면에_나옴, count(*) as 전체
  from library_looks group by mood order by 2 desc;


-- ==================================================================
-- 06_retag_124.sql
-- ==================================================================
-- rainism · 사진 124장 기온·비 다시 매기기 (2026-08-17)
--
-- 왜 다시 하나:
--   앞서 넣은 값은 사진마다 기준이 달랐다. 이번엔 **눈으로 볼 수 있는 규칙 하나**로 124장을 전부 다시 봤다.
--
--   기온 — 팔과 다리 두 군데만 본다.
--     맨팔이면 28°↑ · 반팔+다리가림 23~27° · 긴팔+다리짧음 23~27° · 긴팔+다리가림 20~22°
--     두꺼운 옷(니트·맨투맨·후드·퍼)이 한 겹이라도 있으면 한 칸 내린다.
--     7부 소매는 반팔로 친다. 방수 아노락·우비는 세지 않는다(비 때문이지 추위 때문이 아니라서).
--     🔴 애매하면 **더 더운 쪽**으로 올린다 — 얇은 옷이 추운 날 뜨는 게, 안 뜨는 것보다 나쁘다.
--
--   비 — 신발부터 본다.
--     천 신발(캔버스·스웨이드·어그) · 샌들에 양말 · 시스루/레이스/튤/크로셰 ·
--     바닥에 끌리는 밑단 → 하나라도 걸리면 즉시 false.
--     거기 안 걸리고 레인부츠·고무장화거나, 사진에 비가 오고 있거나,
--     방수 아우터 + 안 끌리는 하의면 true.
--     🔴 애매하면 **무조건 false** — 기온과 반대 방향이다. false 를 true 로 잘못 넣으면
--        비 오는 날 캔버스화 코디가 추천돼서 유저 신발이 젖는다(원칙 2).
--
-- 🔴 에이전트가 사진을 보고 정한 값이다. 기온·비는 하드필터라 틀리면 유저가 젖거나 춥다.
--    prototype/check_temp.html · check_rain.html 에서 사진과 나란히 확인할 수 있다.
--
-- 이름·컨셉(mood)·색(color_primary)·출처는 **안 건드린다.**
-- 색은 온보딩에서 질문을 빼기로 했지만(2026-08-17), 표의 값은 그냥 안 읽히면 되므로 그대로 둔다.
--
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여넣고 Run.
-- 먼저 01~05 파일이 다 돌아가 있어야 한다. 안 그러면 고칠 줄이 없어서 조용히 0줄만 바뀐다.

update library_looks set
  temp_min = case image_path
  when './proto_img/01.jpg' then 23
  when './proto_img/02.jpg' then 23
  when './proto_img/03.jpg' then 28
  when './proto_img/04.jpg' then 20
  when './proto_img/05.jpg' then 23
  when './proto_img/06.jpg' then 23
  when './proto_img/07.jpg' then 20
  when './proto_img/08.jpg' then 20
  when './proto_img/09.jpg' then 28
  when './proto_img/10.jpg' then 23
  when './proto_img/11.jpg' then 17
  when './proto_img/12.jpg' then 23
  when './proto_img/13.jpg' then 23
  when './proto_img/14.jpg' then 20
  when './proto_img/15.jpg' then 20
  when './proto_img/16.jpg' then 20
  when './proto_img/17.jpg' then 28
  when './proto_img/18.jpg' then 23
  when './proto_img/19.jpg' then 17
  when './proto_img/20.jpg' then 20
  when './proto_img/21.jpg' then 23
  when './proto_img/22.jpg' then 20
  when './proto_img/23.jpg' then 23
  when './proto_img/24.jpg' then 23
  when './proto_img/25.jpg' then 20
  when './proto_img/26.jpg' then 28
  when './proto_img/27.jpg' then 28
  when './proto_img/28.jpg' then 23
  when './proto_img/30.jpg' then 23
  when './proto_img/31.jpg' then 28
  when './proto_img/32.jpg' then 23
  when './proto_img/33.jpg' then 20
  when './proto_img/34.jpg' then 20
  when './proto_img/35.jpg' then 20
  when './proto_img/36.jpg' then 28
  when './proto_img/37.jpg' then 28
  when './proto_img/38.jpg' then 28
  when './proto_img/39.jpg' then 20
  when './proto_img/40.jpg' then 23
  when './proto_img/41.jpg' then 28
  when './proto_img/42.jpg' then 20
  when './proto_img/43.jpg' then 28
  when './proto_img/44.jpg' then 20
  when './proto_img/45.jpg' then 28
  when './proto_img/46.jpg' then 28
  when './proto_img/47.jpg' then 23
  when './proto_img/48.jpg' then 28
  when './proto_img/49.jpg' then 23
  when './proto_img/50.jpg' then 23
  when './proto_img/51.jpg' then 20
  when './proto_img/52.jpg' then 23
  when './proto_img/53.jpg' then 23
  when './proto_img/54.jpg' then 20
  when './proto_img/55.jpg' then 28
  when './proto_img/56.jpg' then 17
  when './proto_img/57.jpg' then 20
  when './proto_img/58.jpg' then 23
  when './proto_img/59.jpg' then 28
  when './proto_img/60.jpg' then 23
  when './proto_img/61.jpg' then 23
  when './proto_img/62.jpg' then 23
  when './proto_img/63.jpg' then 28
  when './proto_img/64.jpg' then 23
  when './proto_img/65.jpg' then 23
  when './proto_img/66.jpg' then 23
  when './proto_img/67.jpg' then 23
  when './proto_img/68.jpg' then 23
  when './proto_img/69.jpg' then 28
  when './proto_img/70.jpg' then 23
  when './proto_img/71.jpg' then 23
  when './proto_img/72.jpg' then 28
  when './proto_img/73.jpg' then 23
  when './proto_img/74.jpg' then 23
  when './proto_img/75.jpg' then 28
  when './proto_img/76.jpg' then 23
  when './proto_img/77.jpg' then 23
  when './proto_img/78.jpg' then 28
  when './proto_img/79.jpg' then 23
  when './proto_img/80.jpg' then 23
  when './proto_img/81.jpg' then 28
  when './proto_img/82.jpg' then 20
  when './proto_img/83.jpg' then 28
  when './proto_img/84.jpg' then 28
  when './proto_img/85.jpg' then 28
  when './proto_img/86.jpg' then 23
  when './proto_img/87.jpg' then 20
  when './proto_img/88.jpg' then 28
  when './proto_img/89.jpg' then 28
  when './proto_img/90.jpg' then 28
  when './proto_img/91.jpg' then 28
  when './proto_img/92.jpg' then 23
  when './proto_img/93.jpg' then 23
  when './proto_img/94.jpg' then 28
  when './proto_img/95.jpg' then 20
  when './proto_img/96.jpg' then 28
  when './proto_img/97.jpg' then 28
  when './proto_img/98.jpg' then 28
  when './proto_img/99.jpg' then 23
  when './proto_img/100.jpg' then 28
  when './proto_img/101.jpg' then 28
  when './proto_img/102.jpg' then 28
  when './proto_img/103.jpg' then 23
  when './proto_img/104.jpg' then 20
  when './proto_img/105.jpg' then 17
  when './proto_img/106.jpg' then 28
  when './proto_img/107.jpg' then 20
  when './proto_img/108.jpg' then 20
  when './proto_img/109.jpg' then 20
  when './proto_img/110.jpg' then 28
  when './proto_img/111.jpg' then 20
  when './proto_img/112.jpg' then 28
  when './proto_img/113.jpg' then 28
  when './proto_img/114.jpg' then 20
  when './proto_img/115.jpg' then 20
  when './proto_img/116.jpg' then 20
  when './proto_img/117.jpg' then 23
  when './proto_img/118.jpg' then 17
  when './proto_img/119.jpg' then 23
  when './proto_img/120.jpg' then 17
  when './proto_img/121.jpg' then 28
  when './proto_img/122.jpg' then 23
  when './proto_img/123.jpg' then 28
  when './proto_img/124.jpg' then 28
  when './proto_img/125.jpg' then 23
    else temp_min end,

  temp_max = case image_path
  when './proto_img/01.jpg' then 27
  when './proto_img/02.jpg' then 27
  when './proto_img/03.jpg' then 45
  when './proto_img/04.jpg' then 22
  when './proto_img/05.jpg' then 27
  when './proto_img/06.jpg' then 27
  when './proto_img/07.jpg' then 22
  when './proto_img/08.jpg' then 22
  when './proto_img/09.jpg' then 45
  when './proto_img/10.jpg' then 27
  when './proto_img/11.jpg' then 19
  when './proto_img/12.jpg' then 27
  when './proto_img/13.jpg' then 27
  when './proto_img/14.jpg' then 22
  when './proto_img/15.jpg' then 22
  when './proto_img/16.jpg' then 22
  when './proto_img/17.jpg' then 45
  when './proto_img/18.jpg' then 27
  when './proto_img/19.jpg' then 19
  when './proto_img/20.jpg' then 22
  when './proto_img/21.jpg' then 27
  when './proto_img/22.jpg' then 22
  when './proto_img/23.jpg' then 27
  when './proto_img/24.jpg' then 27
  when './proto_img/25.jpg' then 22
  when './proto_img/26.jpg' then 45
  when './proto_img/27.jpg' then 45
  when './proto_img/28.jpg' then 27
  when './proto_img/30.jpg' then 27
  when './proto_img/31.jpg' then 45
  when './proto_img/32.jpg' then 27
  when './proto_img/33.jpg' then 22
  when './proto_img/34.jpg' then 22
  when './proto_img/35.jpg' then 22
  when './proto_img/36.jpg' then 45
  when './proto_img/37.jpg' then 45
  when './proto_img/38.jpg' then 45
  when './proto_img/39.jpg' then 22
  when './proto_img/40.jpg' then 27
  when './proto_img/41.jpg' then 45
  when './proto_img/42.jpg' then 22
  when './proto_img/43.jpg' then 45
  when './proto_img/44.jpg' then 22
  when './proto_img/45.jpg' then 45
  when './proto_img/46.jpg' then 45
  when './proto_img/47.jpg' then 27
  when './proto_img/48.jpg' then 45
  when './proto_img/49.jpg' then 27
  when './proto_img/50.jpg' then 27
  when './proto_img/51.jpg' then 22
  when './proto_img/52.jpg' then 27
  when './proto_img/53.jpg' then 27
  when './proto_img/54.jpg' then 22
  when './proto_img/55.jpg' then 45
  when './proto_img/56.jpg' then 19
  when './proto_img/57.jpg' then 22
  when './proto_img/58.jpg' then 27
  when './proto_img/59.jpg' then 45
  when './proto_img/60.jpg' then 27
  when './proto_img/61.jpg' then 27
  when './proto_img/62.jpg' then 27
  when './proto_img/63.jpg' then 45
  when './proto_img/64.jpg' then 27
  when './proto_img/65.jpg' then 27
  when './proto_img/66.jpg' then 27
  when './proto_img/67.jpg' then 27
  when './proto_img/68.jpg' then 27
  when './proto_img/69.jpg' then 45
  when './proto_img/70.jpg' then 27
  when './proto_img/71.jpg' then 27
  when './proto_img/72.jpg' then 45
  when './proto_img/73.jpg' then 27
  when './proto_img/74.jpg' then 27
  when './proto_img/75.jpg' then 45
  when './proto_img/76.jpg' then 27
  when './proto_img/77.jpg' then 27
  when './proto_img/78.jpg' then 45
  when './proto_img/79.jpg' then 27
  when './proto_img/80.jpg' then 27
  when './proto_img/81.jpg' then 45
  when './proto_img/82.jpg' then 22
  when './proto_img/83.jpg' then 45
  when './proto_img/84.jpg' then 45
  when './proto_img/85.jpg' then 45
  when './proto_img/86.jpg' then 27
  when './proto_img/87.jpg' then 22
  when './proto_img/88.jpg' then 45
  when './proto_img/89.jpg' then 45
  when './proto_img/90.jpg' then 45
  when './proto_img/91.jpg' then 45
  when './proto_img/92.jpg' then 27
  when './proto_img/93.jpg' then 27
  when './proto_img/94.jpg' then 45
  when './proto_img/95.jpg' then 22
  when './proto_img/96.jpg' then 45
  when './proto_img/97.jpg' then 45
  when './proto_img/98.jpg' then 45
  when './proto_img/99.jpg' then 27
  when './proto_img/100.jpg' then 45
  when './proto_img/101.jpg' then 45
  when './proto_img/102.jpg' then 45
  when './proto_img/103.jpg' then 27
  when './proto_img/104.jpg' then 22
  when './proto_img/105.jpg' then 19
  when './proto_img/106.jpg' then 45
  when './proto_img/107.jpg' then 22
  when './proto_img/108.jpg' then 22
  when './proto_img/109.jpg' then 22
  when './proto_img/110.jpg' then 45
  when './proto_img/111.jpg' then 22
  when './proto_img/112.jpg' then 45
  when './proto_img/113.jpg' then 45
  when './proto_img/114.jpg' then 22
  when './proto_img/115.jpg' then 22
  when './proto_img/116.jpg' then 22
  when './proto_img/117.jpg' then 27
  when './proto_img/118.jpg' then 19
  when './proto_img/119.jpg' then 27
  when './proto_img/120.jpg' then 19
  when './proto_img/121.jpg' then 45
  when './proto_img/122.jpg' then 27
  when './proto_img/123.jpg' then 45
  when './proto_img/124.jpg' then 45
  when './proto_img/125.jpg' then 27
    else temp_max end,

  rain_ok = case image_path
  when './proto_img/01.jpg' then true
  when './proto_img/02.jpg' then false
  when './proto_img/03.jpg' then false
  when './proto_img/04.jpg' then true
  when './proto_img/05.jpg' then true
  when './proto_img/06.jpg' then false
  when './proto_img/07.jpg' then false
  when './proto_img/08.jpg' then false
  when './proto_img/09.jpg' then false
  when './proto_img/10.jpg' then false
  when './proto_img/11.jpg' then false
  when './proto_img/12.jpg' then false
  when './proto_img/13.jpg' then false
  when './proto_img/14.jpg' then false
  when './proto_img/15.jpg' then false
  when './proto_img/16.jpg' then false
  when './proto_img/17.jpg' then false
  when './proto_img/18.jpg' then false
  when './proto_img/19.jpg' then false
  when './proto_img/20.jpg' then false
  when './proto_img/21.jpg' then false
  when './proto_img/22.jpg' then true
  when './proto_img/23.jpg' then true
  when './proto_img/24.jpg' then false
  when './proto_img/25.jpg' then false
  when './proto_img/26.jpg' then true
  when './proto_img/27.jpg' then true
  when './proto_img/28.jpg' then false
  when './proto_img/30.jpg' then false
  when './proto_img/31.jpg' then true
  when './proto_img/32.jpg' then false
  when './proto_img/33.jpg' then true
  when './proto_img/34.jpg' then true
  when './proto_img/35.jpg' then true
  when './proto_img/36.jpg' then true
  when './proto_img/37.jpg' then false
  when './proto_img/38.jpg' then false
  when './proto_img/39.jpg' then false
  when './proto_img/40.jpg' then true
  when './proto_img/41.jpg' then true
  when './proto_img/42.jpg' then false
  when './proto_img/43.jpg' then false
  when './proto_img/44.jpg' then false
  when './proto_img/45.jpg' then true
  when './proto_img/46.jpg' then true
  when './proto_img/47.jpg' then false
  when './proto_img/48.jpg' then true
  when './proto_img/49.jpg' then true
  when './proto_img/50.jpg' then false
  when './proto_img/51.jpg' then false
  when './proto_img/52.jpg' then true
  when './proto_img/53.jpg' then false
  when './proto_img/54.jpg' then false
  when './proto_img/55.jpg' then false
  when './proto_img/56.jpg' then false
  when './proto_img/57.jpg' then false
  when './proto_img/58.jpg' then false
  when './proto_img/59.jpg' then false
  when './proto_img/60.jpg' then false
  when './proto_img/61.jpg' then false
  when './proto_img/62.jpg' then false
  when './proto_img/63.jpg' then false
  when './proto_img/64.jpg' then false
  when './proto_img/65.jpg' then false
  when './proto_img/66.jpg' then false
  when './proto_img/67.jpg' then false
  when './proto_img/68.jpg' then false
  when './proto_img/69.jpg' then false
  when './proto_img/70.jpg' then false
  when './proto_img/71.jpg' then false
  when './proto_img/72.jpg' then false
  when './proto_img/73.jpg' then false
  when './proto_img/74.jpg' then false
  when './proto_img/75.jpg' then false
  when './proto_img/76.jpg' then false
  when './proto_img/77.jpg' then false
  when './proto_img/78.jpg' then false
  when './proto_img/79.jpg' then false
  when './proto_img/80.jpg' then false
  when './proto_img/81.jpg' then false
  when './proto_img/82.jpg' then false
  when './proto_img/83.jpg' then false
  when './proto_img/84.jpg' then false
  when './proto_img/85.jpg' then false
  when './proto_img/86.jpg' then false
  when './proto_img/87.jpg' then false
  when './proto_img/88.jpg' then false
  when './proto_img/89.jpg' then false
  when './proto_img/90.jpg' then false
  when './proto_img/91.jpg' then false
  when './proto_img/92.jpg' then false
  when './proto_img/93.jpg' then false
  when './proto_img/94.jpg' then false
  when './proto_img/95.jpg' then false
  when './proto_img/96.jpg' then false
  when './proto_img/97.jpg' then false
  when './proto_img/98.jpg' then false
  when './proto_img/99.jpg' then false
  when './proto_img/100.jpg' then false
  when './proto_img/101.jpg' then false
  when './proto_img/102.jpg' then false
  when './proto_img/103.jpg' then false
  when './proto_img/104.jpg' then false
  when './proto_img/105.jpg' then false
  when './proto_img/106.jpg' then false
  when './proto_img/107.jpg' then false
  when './proto_img/108.jpg' then false
  when './proto_img/109.jpg' then false
  when './proto_img/110.jpg' then false
  when './proto_img/111.jpg' then false
  when './proto_img/112.jpg' then false
  when './proto_img/113.jpg' then false
  when './proto_img/114.jpg' then false
  when './proto_img/115.jpg' then false
  when './proto_img/116.jpg' then false
  when './proto_img/117.jpg' then false
  when './proto_img/118.jpg' then false
  when './proto_img/119.jpg' then false
  when './proto_img/120.jpg' then false
  when './proto_img/121.jpg' then false
  when './proto_img/122.jpg' then false
  when './proto_img/123.jpg' then false
  when './proto_img/124.jpg' then false
  when './proto_img/125.jpg' then false
    else rain_ok end,

  -- 레인부츠가 사진에 실제로 보이는 것만. 이유 문장("레인부츠라 발도 안 젖어요")에 쓰인다.
  boots = case image_path
  when './proto_img/01.jpg' then true
  when './proto_img/02.jpg' then false
  when './proto_img/03.jpg' then false
  when './proto_img/04.jpg' then true
  when './proto_img/05.jpg' then false
  when './proto_img/06.jpg' then false
  when './proto_img/07.jpg' then false
  when './proto_img/08.jpg' then false
  when './proto_img/09.jpg' then false
  when './proto_img/10.jpg' then false
  when './proto_img/11.jpg' then false
  when './proto_img/12.jpg' then false
  when './proto_img/13.jpg' then false
  when './proto_img/14.jpg' then false
  when './proto_img/15.jpg' then false
  when './proto_img/16.jpg' then false
  when './proto_img/17.jpg' then false
  when './proto_img/18.jpg' then false
  when './proto_img/19.jpg' then false
  when './proto_img/20.jpg' then false
  when './proto_img/21.jpg' then false
  when './proto_img/22.jpg' then true
  when './proto_img/23.jpg' then true
  when './proto_img/24.jpg' then false
  when './proto_img/25.jpg' then false
  when './proto_img/26.jpg' then true
  when './proto_img/27.jpg' then true
  when './proto_img/28.jpg' then false
  when './proto_img/30.jpg' then false
  when './proto_img/31.jpg' then true
  when './proto_img/32.jpg' then false
  when './proto_img/33.jpg' then true
  when './proto_img/34.jpg' then true
  when './proto_img/35.jpg' then true
  when './proto_img/36.jpg' then true
  when './proto_img/37.jpg' then false
  when './proto_img/38.jpg' then false
  when './proto_img/39.jpg' then false
  when './proto_img/40.jpg' then true
  when './proto_img/41.jpg' then true
  when './proto_img/42.jpg' then false
  when './proto_img/43.jpg' then false
  when './proto_img/44.jpg' then false
  when './proto_img/45.jpg' then true
  when './proto_img/46.jpg' then true
  when './proto_img/47.jpg' then false
  when './proto_img/48.jpg' then false
  when './proto_img/49.jpg' then true
  when './proto_img/50.jpg' then false
  when './proto_img/51.jpg' then false
  when './proto_img/52.jpg' then true
  when './proto_img/53.jpg' then false
  when './proto_img/54.jpg' then false
  when './proto_img/55.jpg' then false
  when './proto_img/56.jpg' then false
  when './proto_img/57.jpg' then false
  when './proto_img/58.jpg' then false
  when './proto_img/59.jpg' then false
  when './proto_img/60.jpg' then false
  when './proto_img/61.jpg' then false
  when './proto_img/62.jpg' then false
  when './proto_img/63.jpg' then false
  when './proto_img/64.jpg' then false
  when './proto_img/65.jpg' then false
  when './proto_img/66.jpg' then false
  when './proto_img/67.jpg' then false
  when './proto_img/68.jpg' then false
  when './proto_img/69.jpg' then false
  when './proto_img/70.jpg' then false
  when './proto_img/71.jpg' then false
  when './proto_img/72.jpg' then false
  when './proto_img/73.jpg' then false
  when './proto_img/74.jpg' then false
  when './proto_img/75.jpg' then false
  when './proto_img/76.jpg' then false
  when './proto_img/77.jpg' then false
  when './proto_img/78.jpg' then false
  when './proto_img/79.jpg' then false
  when './proto_img/80.jpg' then false
  when './proto_img/81.jpg' then false
  when './proto_img/82.jpg' then false
  when './proto_img/83.jpg' then false
  when './proto_img/84.jpg' then false
  when './proto_img/85.jpg' then false
  when './proto_img/86.jpg' then false
  when './proto_img/87.jpg' then false
  when './proto_img/88.jpg' then false
  when './proto_img/89.jpg' then false
  when './proto_img/90.jpg' then false
  when './proto_img/91.jpg' then false
  when './proto_img/92.jpg' then false
  when './proto_img/93.jpg' then false
  when './proto_img/94.jpg' then false
  when './proto_img/95.jpg' then false
  when './proto_img/96.jpg' then false
  when './proto_img/97.jpg' then false
  when './proto_img/98.jpg' then false
  when './proto_img/99.jpg' then false
  when './proto_img/100.jpg' then false
  when './proto_img/101.jpg' then false
  when './proto_img/102.jpg' then false
  when './proto_img/103.jpg' then false
  when './proto_img/104.jpg' then false
  when './proto_img/105.jpg' then false
  when './proto_img/106.jpg' then false
  when './proto_img/107.jpg' then false
  when './proto_img/108.jpg' then false
  when './proto_img/109.jpg' then false
  when './proto_img/110.jpg' then false
  when './proto_img/111.jpg' then false
  when './proto_img/112.jpg' then false
  when './proto_img/113.jpg' then false
  when './proto_img/114.jpg' then false
  when './proto_img/115.jpg' then false
  when './proto_img/116.jpg' then false
  when './proto_img/117.jpg' then false
  when './proto_img/118.jpg' then false
  when './proto_img/119.jpg' then false
  when './proto_img/120.jpg' then false
  when './proto_img/121.jpg' then false
  when './proto_img/122.jpg' then false
  when './proto_img/123.jpg' then false
  when './proto_img/124.jpg' then false
  when './proto_img/125.jpg' then false
    else boots end

where image_path like './proto_img/%';


-- ── 확인 ────────────────────────────────────────────────────────
-- 1) 124줄이 다 있나. 124 가 아니면 위 파일 중 안 돌린 게 있다.
select count(*) as 고친_사진수 from library_looks where image_path like './proto_img/%';

-- 2) 기온 밴드별 장수 — 43 / 46 / 29 / 6 이 나와야 한다
select temp_min || '~' || temp_max || '°' as 기온, count(*) as 장수
  from library_looks where image_path like './proto_img/%'
  group by temp_min, temp_max order by temp_min desc;

-- 3) 🔴 비 오는 날 후보 — 밴드마다 3장은 있어야 한 화면이 찬다
--    17~19° 가 0장이다. 서늘한 비 오는 날엔 보여줄 코디가 없다는 뜻이다.
select temp_min || '~' || temp_max || '°' as 기온,
       count(*) filter (where rain_ok) as 비_와도_됨,
       count(*) filter (where not rain_ok) as 비엔_안_됨
  from library_looks where image_path like './proto_img/%'
  group by temp_min, temp_max order by temp_min desc;

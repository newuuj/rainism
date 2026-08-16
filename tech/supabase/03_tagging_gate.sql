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

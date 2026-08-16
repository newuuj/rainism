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

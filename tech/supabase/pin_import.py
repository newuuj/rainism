#!/usr/bin/env python3
"""핀터레스트 보드 → 사진 내려받기 + Supabase 에 넣을 SQL 만들기

  # 뭐가 들어올지 먼저 본다 (아무것도 안 받고 안 만든다)
  python3 tech/supabase/pin_import.py 내계정/rainism-비 --dry

  # 실제로 받기 — 그 보드가 어떤 날씨용인지 반드시 알려줘야 한다
  python3 tech/supabase/pin_import.py 내계정/rainism-비 --temp warm --rain

  --temp  hot(28°↑) | warm(23~27°) | cool(20~22°) | chilly(17~19°)
  --rain  비 오는 날 입어도 되는 코디들이면 붙인다
  --limit 최대 몇 개까지 (기본 전부)

어디서 가져오나:
  핀터레스트가 보드마다 공개로 열어두는 주소를 쓴다 —
  https://www.pinterest.com/{계정}/{보드}.rss
  개발자 앱 등록도, 로그인도 필요 없다. 대신 **보드가 공개여야 하고**,
  최근 것 몇 개(보통 25개 안팎)만 준다.

🔴 무드·색·구성아이템은 핀터레스트가 주지 않는다.
   그래서 받아온 코디는 전부 active=false(화면에 안 나옴)로 들어간다.
   태그를 채워야 켤 수 있다 — 03_tagging_gate.sql 이 표 수준에서 막고 있다.

🔴 받아온 사진의 저작권은 남의 것이다. source_license 는 'unverified' 로 들어간다.
   내 컴퓨터에서 데모 돌리는 건 괜찮지만 인터넷에 올리면 안 된다 (RG-4).
"""
import argparse, html, json, pathlib, re, subprocess, sys

ROOT   = pathlib.Path(__file__).resolve().parents[2]
IMGDIR = ROOT / "prototype/proto_img"
LEDGER = ROOT / "tech/supabase/imported_pins.txt"   # 두 번 받는 걸 막는 기록
UA     = "Mozilla/5.0"

# 체감온도 눈금 — rainism_outfit_rules_v1_summer_women.csv [1] 그대로
BAND = {"hot": (28, 45), "warm": (23, 27), "cool": (20, 22), "chilly": (17, 19)}
LONG_EDGE = 520          # CLAUDE.md 기준: sips -Z 520 으로 줄인다


def fetch(url, binary=False):
    """curl 로 받는다. (맥의 파이썬은 SSL 인증서를 못 읽는 경우가 많아 urllib 를 안 쓴다)"""
    r = subprocess.run(["curl", "-sL", "-m", "40", "-A", UA, url],
                       capture_output=True)
    if r.returncode != 0 or not r.stdout:
        raise RuntimeError(f"못 받았다: {url}")
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def parse_board(user, board):
    """보드 RSS → [{title, pin_url, img_url}]"""
    xml = fetch(f"https://www.pinterest.com/{user}/{board}.rss")
    if "<item>" not in xml:
        raise RuntimeError(
            "핀을 하나도 못 찾았다. 확인할 것:\n"
            "  · 보드가 '공개'인가 (비공개 보드는 이 주소가 안 열린다)\n"
            "  · 계정이름/보드이름 철자가 맞나 (주소창에 보이는 그대로)\n"
            f"  · 직접 열어보기: https://www.pinterest.com/{user}/{board}.rss")
    pins = []
    for it in re.findall(r"<item>(.*?)</item>", xml, re.S):
        get = lambda t: (re.search(rf"<{t}>(.*?)</{t}>", it, re.S) or [None, ""])[1]
        desc = html.unescape(get("description"))
        img = re.search(r'<img src="([^"]+)"', desc)
        if not img:
            continue
        pins.append(dict(
            title=html.unescape(get("title")).strip(),
            pin_url=get("link").strip(),
            # 236x(썸네일)로 오므로 736x(원본에 가까운 크기)로 바꿔 받는다
            img_url=re.sub(r"/\d+x\d*/", "/736x/", img.group(1))))
    return pins


def next_id():
    """proto_img 에서 안 쓰는 다음 번호. 번호가 곧 코디 id 라서 겹치면 안 된다."""
    used = [int(m.group(1)) for p in IMGDIR.glob("*.jpg")
            if (m := re.fullmatch(r"(\d+)", p.stem))]
    return max(used, default=0) + 1


def save_photo(url, num):
    path = IMGDIR / f"{num:02d}.jpg"
    path.write_bytes(fetch(url, binary=True))
    # 기존 39장과 같은 방식으로 줄인다 (안 줄이면 배포 파일만 무거워진다)
    subprocess.run(["sips", "-Z", str(LONG_EDGE), str(path)],
                   capture_output=True)
    return path


def sql_row(num, pin, temp, rain):
    esc = lambda s: str(s).replace("'", "''")
    tmin, tmax = BAND[temp]
    name = pin["title"][:60] or f"코디 {num}"
    return (f"  ('./proto_img/{num:02d}.jpg', '{esc(name)}', '{esc(pin['pin_url'])}', "
            f"{tmin}, {tmax}, {str(rain).lower()}, false)")


def main():
    ap = argparse.ArgumentParser(description="핀터레스트 보드에서 코디 사진 가져오기")
    ap.add_argument("board", help="계정이름/보드이름 (예: yujeong/rainism-rain)")
    ap.add_argument("--temp", choices=list(BAND), help="이 보드가 어떤 온도대인가")
    ap.add_argument("--rain", action="store_true", help="비 오는 날 입어도 되는 보드인가")
    ap.add_argument("--limit", type=int, help="최대 몇 개까지")
    ap.add_argument("--dry", action="store_true", help="받지 않고 뭐가 있는지만 보여준다")
    a = ap.parse_args()

    if "/" not in a.board:
        sys.exit("❌ 보드는 '계정이름/보드이름' 형태로 준다 (예: yujeong/rainism-rain)")
    user, board = a.board.split("/", 1)

    if not a.dry and not a.temp:
        sys.exit("❌ --temp 가 없다. 이 보드가 몇 도짜리인지 모르면 넣을 수 없다.\n"
                 "   날씨는 틀리면 안 되는 값이라 넘겨짚지 않는다 (원칙 2).\n"
                 f"   고를 수 있는 값: {' | '.join(BAND)}")

    pins = parse_board(user, board)
    print(f"  보드에서 핀 {len(pins)}개를 찾았다")

    seen = set(LEDGER.read_text(encoding="utf-8").split()) if LEDGER.exists() else set()
    fresh = [p for p in pins if p["pin_url"] not in seen]
    if len(fresh) < len(pins):
        print(f"  이미 받은 것 {len(pins)-len(fresh)}개는 건너뛴다")
    if a.limit:
        fresh = fresh[:a.limit]
    if not fresh:
        print("  새로 받을 게 없다."); return 0

    if a.dry:
        print(f"\n  --dry 라서 아무것도 받지 않았다. 받으면 이렇게 들어간다:\n")
        n = next_id()
        for i, p in enumerate(fresh[:5]):
            print(f"   {n+i:02d}.jpg  ← {p['title'][:44] or '(제목 없음)'}")
            print(f"            {p['pin_url']}")
        if len(fresh) > 5:
            print(f"   … 외 {len(fresh)-5}개")
        print(f"\n  실제로 받으려면 --temp 를 정해서 다시:")
        print(f"    python3 tech/supabase/pin_import.py {a.board} --temp warm"
              f"{' --rain' if a.rain else ''}")
        return 0

    rows, got = [], []
    start = next_id()
    for i, p in enumerate(fresh):
        num = start + i
        try:
            save_photo(p["img_url"], num)
        except Exception as e:
            print(f"  ⚠️ {num:02d} 건너뜀 — {e}"); continue
        rows.append(sql_row(num, p, a.temp, a.rain)); got.append(p["pin_url"])
        print(f"  ✓ {num:02d}.jpg  {p['title'][:40]}")

    if not rows:
        print("  받은 게 없다."); return 1

    out = ROOT / f"tech/supabase/import_{board}.sql"
    out.write_text(
        f"-- {a.board} 에서 받아온 코디 {len(rows)}개\n"
        f"-- pin_import.py 가 만든 파일이다. Supabase SQL Editor 에 붙여넣고 Run.\n"
        "--\n"
        "-- 🔴 active=false 로 들어간다 — 무드·색을 채우기 전에는 화면에 안 나온다.\n"
        "--    켜려면 그 두 개를 채우고 active=true 로 바꾼다.\n"
        "--    (03_tagging_gate.sql 의 ready_to_show 규칙이 빈 채로 켜는 걸 막는다)\n"
        "-- 🔴 source_license 는 'unverified' 다. 인터넷에 올리면 안 된다 (RG-4).\n\n"
        "insert into library_looks\n"
        "  (image_path, name, source_url, temp_min, temp_max, rain_ok, active)\n"
        "values\n" + ",\n".join(rows) + "\non conflict (source_url) do nothing;\n",
        encoding="utf-8")

    LEDGER.write_text("\n".join(sorted(seen | set(got))) + "\n", encoding="utf-8")

    print(f"\n  ✓ 사진 {len(rows)}장 → prototype/proto_img/")
    print(f"  ✓ SQL → {out.relative_to(ROOT)}")
    print(f"\n  다음: 위 SQL 을 Supabase 에 넣고, 무드·색을 채운 뒤 active=true 로 켠다.")
    print(f"        {'☔ 비 적합' if a.rain else '☀️ 비 부적합'} · "
          f"{a.temp}({BAND[a.temp][0]}~{BAND[a.temp][1]}°) 로 표시된다.")
    return 0


if __name__ == "__main__":
    # 파이썬 오류를 그대로 뱉지 않는다 — 이 스크립트를 돌리는 사람은 개발자가 아니다
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit("\n  멈췄다.")
    except Exception as e:
        sys.exit(f"❌ {e}")

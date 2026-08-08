#!/usr/bin/env python3
"""프로토타입에 박혀 있는 코디 목록 → Supabase 넣을 SQL 로 뽑아낸다.

  python3 tech/supabase/export_looks.py

손으로 옮기지 않는 이유: 39줄을 손으로 베끼면 rain/temp 하나쯤 틀리는데,
그게 하필 "비 오는 날 비 부적합 코디"가 나오는 방식이다 (원칙 2 — 날씨는 틀리면 안 된다).
그래서 뽑아낸 뒤 원본과 한 줄씩 대조까지 한다.
"""
import re, json, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC  = ROOT / "prototype/rainism_prototype_v1.html"
OUT  = ROOT / "tech/supabase/02_seed_39.sql"

# 체감온도 눈금 — tech/rainism_outfit_rules_v1_summer_women.csv [1] 그대로.
# 임의로 정한 값이 아니다. CSV가 바뀌면 여기도 바꾼다.
BAND = {"hot": (28, 45), "warm": (23, 27), "cool": (20, 22), "chilly": (17, 19)}


def parse(body):
    """LOOKS 배열 → {id: 필드들}. 같은 id가 두 번 나오면 앞의 것만 쓴다(과거 24/29 중복 전례)."""
    out = {}
    for m in re.finditer(r"\{id:(\d+),(.*?)\}(?:,|\s*$)", body, re.S):
        lid, rest = int(m.group(1)), m.group(2)
        if lid in out:
            print(f"  ⚠️ id={lid} 가 두 번 나온다 — 앞의 것만 쓴다", file=sys.stderr)
            continue
        txt = lambda k: (re.search(rf"{k}:'([^']*)'", rest) or [None, None])[1]
        out[lid] = dict(
            name=txt("name"), mood=txt("mood"), color=txt("color"), temp=txt("temp"),
            items=[i.strip() for i in (txt("items") or "").split("·") if i.strip()],
            form=int(re.search(r"form:(\d+)", rest).group(1)),
            rain=bool(re.search(r"rain:true", rest)),
            boots=bool(re.search(r"boots:true", rest)),
            safe=bool(re.search(r"safe:true", rest)),
        )
    return out


def row(lid, d):
    esc = lambda s: s.replace("'", "''")
    tmin, tmax = BAND[d["temp"]]
    items = json.dumps(d["items"], ensure_ascii=False).replace("'", "''")
    return (f"('./proto_img/{lid:02d}.jpg', '{esc(d['name'])}', '{items}'::jsonb, "
            f"'{d['mood']}', '{d['color']}', {d['form']}, {tmin}, {tmax}, "
            f"{str(d['rain']).lower()}, {str(d['boots']).lower()}, {str(d['safe']).lower()})")


def main():
    body = re.search(r"const LOOKS=\[(.*?)\n\];", SRC.read_text(encoding="utf-8"), re.S).group(1)
    looks = parse(body)

    OUT.write_text(
        "-- rainism · 지금 프로토타입에 박혀 있는 코디를 표에 넣는다\n"
        "-- 01_schema.sql 을 먼저 돌린 뒤, 이 파일을 SQL Editor 에 붙여넣고 Run.\n"
        "--\n"
        "-- ⚠️ 손으로 쓴 게 아니라 export_looks.py 가 프로토타입에서 뽑아낸 것이다.\n"
        "--    프로토타입이 바뀌면 다시 돌린다.\n"
        "--\n"
        "-- 🔴 source_license 가 전부 'unverified' 다 — 출처가 확인되지 않았다는 뜻이고,\n"
        "--    그래서 이 사진들은 인터넷에 올리면 안 된다 (RG-4).\n\n"
        "insert into library_looks\n"
        "  (image_path, name, items, mood, color_primary, formality,\n"
        "   temp_min, temp_max, rain_ok, boots, is_safe)\n"
        "values\n"
        + ",\n".join("  " + row(i, looks[i]) for i in sorted(looks)) + ";\n",
        encoding="utf-8")

    # 뽑은 게 원본과 같은지 한 줄씩 대조 — 이게 없으면 이 스크립트를 믿을 수 없다
    bad = 0
    for line in OUT.read_text(encoding="utf-8").splitlines():
        if not line.strip().startswith("('./proto_img/"):
            continue
        lid = int(re.search(r"proto_img/(\d+)\.jpg", line).group(1))
        t = line.strip().rstrip(",;").rstrip(")").split(", ")[-5:]
        d = looks[lid]
        for label, got, want in (("rain", t[2] == "true", d["rain"]),
                                 ("boots", t[3] == "true", d["boots"]),
                                 ("safe", t[4] == "true", d["safe"]),
                                 ("temp", (int(t[0]), int(t[1])), BAND[d["temp"]])):
            if got != want:
                print(f"  ✗ id={lid} {label}: 뽑은값={got} 원본={want}"); bad += 1

    print(f"  ✓ {OUT.relative_to(ROOT)} — 코디 {len(looks)}개"
          f" (비 적합 {sum(d['rain'] for d in looks.values())} · 안전빵 {sum(d['safe'] for d in looks.values())})")
    print("  ✓ 원본과 대조: 틀린 값 없음" if bad == 0 else f"  🔴 원본과 다른 값 {bad}건 — 넣지 말 것")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())

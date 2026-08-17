#!/usr/bin/env python3
"""핀터레스트 보드 → 사진 내려받기 + Supabase 에 넣을 SQL 만들기

  # 뭐가 들어올지 먼저 본다 (아무것도 안 받고 안 만든다)
  python3 tech/supabase/pin_import.py 내계정/Y2K-더울때 --dry

  # 실제로 받기 — 어떤 컨셉인지, 어떤 날씨용인지 반드시 알려줘야 한다
  python3 tech/supabase/pin_import.py 내계정/Y2K-비 --mood Y2K --temp warm --rain

  --mood  고프코어 | 발레코어 | Y2K | 모리룩   ← 보드 하나 = 컨셉 하나
  --temp  hot(28°↑) | warm(23~27°) | cool(20~22°) | chilly(17~19°)
  --rain  비 오는 날 입어도 되는 코디들이면 붙인다
  --color 보드 전체를 한 색으로 고정한다 (안 주면 사진 보고 고르는 화면이 나온다)
  --limit 최대 몇 개까지 (기본 전부)

어디서 가져오나:
  핀터레스트가 보드마다 공개로 열어두는 주소를 쓴다 —
  https://www.pinterest.com/{계정}/{보드}.rss
  개발자 앱 등록도, 로그인도 필요 없다. 대신 **보드가 공개여야 하고**,
  최근 것 몇 개(보통 25개 안팎)만 준다.

🔴 핀터레스트는 사진과 제목만 준다. 컨셉·색은 안 온다.
   컨셉·온도·비는 보드 단위로 받는다 — 보드를 그렇게 나눠 만들었다는 전제다.
   색만 사진마다 달라서, 받고 나면 색 고르는 화면(prototype/tag_*.html)이 나온다.
   ※ 색도 사진에서 자동으로 뽑아봤지만 39장 기준 41%밖에 안 맞아서 버렸다.
     검은 옷을 밝은 배경에서 찍으면 사진 전체 밝기는 밝게 나온다.

🔴 받아온 사진의 저작권은 남의 것이다. source_license 는 'unverified' 로 들어간다.
   내 컴퓨터에서 데모 돌리는 건 괜찮지만 인터넷에 올리면 안 된다 (RG-4).
"""
import argparse, html, json, pathlib, re, subprocess, sys

ROOT   = pathlib.Path(__file__).resolve().parents[2]
IMGDIR = ROOT / "prototype/proto_img"
LEDGER = ROOT / "tech/supabase/imported_pins.txt"   # 두 번 받는 걸 막는 기록
UA     = "Mozilla/5.0"

# 체감온도 눈금 — rainism_outfit_rules_v2_allseason_women.csv [1] 그대로
BAND = {"hot": (28, 45), "warm": (23, 27), "cool": (20, 22), "chilly": (17, 19)}
LONG_EDGE = 520          # CLAUDE.md 기준: sips -Z 520 으로 줄인다

# 온보딩 질문의 컨셉 4개 (2026-08-16 개편). 표의 mood 값과 같은 글자여야 한다 —
# 한 글자라도 다르면 그 코디는 어떤 취향에도 안 걸려 사실상 안 나온다.
MOODS  = ["고프코어", "발레코어", "Y2K", "모리룩"]
COLORS = ["뉴트럴", "다크", "쿨톤", "웜톤"]


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


def sql_row(num, pin, mood, color, temp, rain):
    esc = lambda s: str(s).replace("'", "''")
    tmin, tmax = BAND[temp]
    name = pin["title"][:60] or f"코디 {num}"
    return (f"  ('./proto_img/{num:02d}.jpg', '{esc(name)}', '{esc(pin['pin_url'])}', "
            f"'{mood}', '{color}', {tmin}, {tmax}, {str(rain).lower()}, true)")


def write_sheet(path, board, rows, mood, temp, rain):
    """받은 사진을 한 장에 늘어놓고 사진마다 색·기온·비를 눌러서 정하는 화면을 만든다.

    왜 자동으로 안 하나: 사진에서 색을 뽑아봤는데 39장 기준 41%밖에 안 맞았다.
    사람이 검은 옷을 입고 밝은 배경에 서 있으면 사진 전체는 밝게 나오기 때문이다.
    그 값으로 켜면 '밝은 톤이라 덜 더워 보여요' 같은 문구가 검은 옷에 붙는다(§9-1).
    그래서 색은 사람이 고른다. 대신 사진을 한 화면에 다 띄워서 클릭만 하면 되게 한다.
    격자 모양은 prototype/_sheet.html 에 이미 쓰던 것을 그대로 가져왔다.

    기온·비도 여기서 고칠 수 있다 (2026-08-16). 전에는 보드 하나 = 기온 하나 = 비 하나였는데,
    한 보드에 이것저것 섞어 담으면 그 전제가 깨져서 비 못 맞는 코디가 비 오는 날에 섞인다.
    🔴 기온·비는 하드필터라 틀리면 안 된다(원칙 2). 명령어에 준 --temp/--rain 으로 미리
       채워두되(그건 사람이 직접 친 값이다) 사진마다 눌러 바꿀 수 있게 한다.

    🔴 색을 다 고르기 전에는 SQL 이 안 나온다 — 표의 ready_to_show 와 같은 취지다.
    """
    j = lambda o: json.dumps(o, ensure_ascii=False)
    # 눈금 이름(hot/warm/…)은 우리끼리 쓰는 말이라 화면엔 실제 온도로 적는다 (AGENTS.md §0)
    temps = [[k, f"{v[0]}°↑" if v[1] >= 45 else f"{v[0]}~{v[1]}°"] for k, v in BAND.items()]
    temp_now = dict(temps)[temp]
    path.write_text(f"""<meta charset=utf-8><title>{board} 태그 달기</title><style>
body{{margin:0;padding:16px;background:#fff;font:14px/1.5 system-ui;color:#1a1f2b}}
h1{{font-size:18px;margin:0 0 4px}} p.s{{margin:0 0 14px;color:#6b7280}}
.bar{{position:sticky;top:0;background:#fff;padding:10px 0;border-bottom:1px solid #e5e7eb;z-index:9}}
.bar b{{font-size:16px}} .bar button{{padding:8px 16px;font:600 14px system-ui;border-radius:8px;
  border:0;background:#2563eb;color:#fff;cursor:pointer}} .bar button:disabled{{background:#cbd5e1;cursor:default}}
textarea{{width:100%;height:150px;margin-top:10px;font:12px/1.5 ui-monospace,monospace;
  border:1px solid #e5e7eb;border-radius:8px;padding:10px}}
.g{{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:14px;margin-top:16px}}
figure{{margin:0}} img{{width:100%;aspect-ratio:5/7;object-fit:cover;border-radius:8px;display:block}}
.n{{font-weight:700;margin:6px 0 2px}} .cs{{display:flex;gap:4px;flex-wrap:wrap}}
.lb{{font-size:11px;color:#9ca3af;margin:7px 0 3px}}
.cs button{{flex:1;min-width:40px;padding:6px 2px;font:600 12px system-ui;border-radius:6px;
  border:1.5px solid #e5e7eb;background:#fff;color:#6b7280;cursor:pointer}}
.cs button.on{{border-color:#2563eb;background:#eef3fa;color:#2563eb}}
/* 기온·비는 하드필터라 고르기 전엔 눈에 띄게 남겨둔다 */
.cs.hard button.on{{border-color:#0f766e;background:#e6f4f1;color:#0f766e}}
figure.todo img{{outline:2px solid #f59e0b;outline-offset:-2px}}
</style>
<h1>{board} — 사진마다 색 · 기온 · 비를 정하세요</h1>
<p class=s>컨셉 <b>{mood}</b> 는 보드 이름으로 이미 정해져 있습니다. <b>색</b>을 사진마다 고르세요.<br>
🔴 <b>기온과 비는 틀리면 안 됩니다.</b> 비에 못 입을 옷을 '비 와도 됨'으로 두면
그 코디가 비 오는 날 추천에 그대로 올라갑니다.
명령어에 준 값(<b>{temp_now}</b> · <b>{'비 와도 됨' if rain else '비엔 안 됨'}</b>)으로 미리 채워뒀으니
<b>사진마다 확인하고 다른 것만 눌러 고치세요.</b><br>
색은 추천 순위에만 쓰여서 틀려도 큰일 나지 않습니다. 옷이 무슨 색인지만 보세요(배경 말고).</p>
<div class=bar><b id=cnt></b> &nbsp; <button id=btn onclick=copy()>SQL 복사</button></div>
<textarea id=out readonly></textarea>
<div class=g id=g></div>
<script>
const P={j(rows)}, C={j(COLORS)}, MOOD={j(mood)}, BAND={j(BAND)}, TEMPS={j(temps)},
      DEF_T={j(temp)}, DEF_R={str(rain).lower()},
      RAINS=[['true','비 와도 됨'],['false','비엔 안 됨']], got={{}};
P.forEach(p=>got[p.n]={{c:null, t:DEF_T, r:DEF_R}});

document.getElementById('g').innerHTML = P.map(p=>`<figure class=todo id=f${{p.n}}>
  <img src="./proto_img/${{String(p.n).padStart(2,'0')}}.jpg">
  <div class=n>${{String(p.n).padStart(2,'0')}}</div>
  <div class=lb>색</div>
  <div class=cs>${{C.map(c=>
    `<button onclick="pick(${{p.n}},'c','${{c}}',this)">${{c}}</button>`).join('')}}</div>
  <div class=lb>기온</div>
  <div class="cs hard">${{TEMPS.map(([k,lab])=>
    `<button class="${{k===DEF_T?'on':''}}" onclick="pick(${{p.n}},'t','${{k}}',this)">${{lab}}</button>`).join('')}}</div>
  <div class=lb>비</div>
  <div class="cs hard">${{RAINS.map(([v,lab])=>
    `<button class="${{String(DEF_R)===v?'on':''}}" onclick="pick(${{p.n}},'r','${{v}}',this)">${{lab}}</button>`).join('')}}</div>
</figure>`).join('');

function pick(n,k,v,el){{
  got[n][k] = (k==='r') ? (v==='true') : v;
  [...el.parentNode.children].forEach(b=>b.classList.toggle('on', b===el));
  if (got[n].c) document.getElementById('f'+n).classList.remove('todo');
  draw();
}}
function sql(){{
  const q=s=>String(s).replace(/'/g,"''");
  return "insert into library_looks\\n"
    +"  (image_path, name, source_url, mood, color_primary,\\n"
    +"   temp_min, temp_max, rain_ok, active)\\nvalues\\n"
    + P.map(p=>{{ const g=got[p.n], b=BAND[g.t];
        return `  ('./proto_img/${{String(p.n).padStart(2,'0')}}.jpg', '${{q(p.name)}}', `
          +`'${{q(p.url)}}', '${{MOOD}}', '${{g.c}}', ${{b[0]}}, ${{b[1]}}, ${{g.r}}, true)`;
      }}).join(',\\n')
    + "\\non conflict (source_url) where source_url is not null do nothing;";
}}
function draw(){{
  const d=P.filter(p=>got[p.n].c).length, ok=d===P.length;
  document.getElementById('cnt').textContent=`${{d}} / ${{P.length}} 골랐어요`;
  document.getElementById('btn').disabled=!ok;
  document.getElementById('out').value = ok ? sql()
    : '사진마다 색을 하나씩 고르면 여기에 붙여넣을 SQL 이 나옵니다.';
}}
function copy(){{
  const t=document.getElementById('out'); t.select(); document.execCommand('copy');
  document.getElementById('btn').textContent='복사됐어요 — Supabase SQL Editor 에 붙여넣으세요';
}}
draw();
</script>
""", encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description="핀터레스트 보드에서 코디 사진 가져오기")
    ap.add_argument("board", help="계정이름/보드이름 (예: yujeong/Y2K-비)")
    ap.add_argument("--from-json", help="보드 대신 이 파일에서 핀 목록을 읽는다 "
                                        "([{title,pin_url,img_url}, ...])")
    ap.add_argument("--mood", choices=MOODS, help="이 보드가 어떤 컨셉인가")
    ap.add_argument("--temp", choices=list(BAND), help="이 보드가 어떤 온도대인가")
    ap.add_argument("--rain", action="store_true", help="비 오는 날 입어도 되는 보드인가")
    ap.add_argument("--color", choices=COLORS, help="색을 고정한다 (안 주면 사진에서 자동)")
    ap.add_argument("--limit", type=int, help="최대 몇 개까지")
    ap.add_argument("--dry", action="store_true", help="받지 않고 뭐가 있는지만 보여준다")
    a = ap.parse_args()

    if a.from_json:
        # 보드 대신 검색 화면에서 긁어온 목록을 쓸 때. board 는 파일 이름표로만 쓴다.
        board = a.board
    elif "/" not in a.board:
        sys.exit("❌ 보드는 '계정이름/보드이름' 형태로 준다 (예: yujeong/Y2K-비)")
    else:
        user, board = a.board.split("/", 1)

    if not a.dry and not a.temp:
        sys.exit("❌ --temp 가 없다. 이 보드가 몇 도짜리인지 모르면 넣을 수 없다.\n"
                 "   날씨는 틀리면 안 되는 값이라 넘겨짚지 않는다 (원칙 2).\n"
                 f"   고를 수 있는 값: {' | '.join(BAND)}")

    if not a.dry and not a.mood:
        sys.exit("❌ --mood 가 없다. 어떤 컨셉인지 모르면 넣어도 화면에 못 나온다.\n"
                 "   (컨셉이 비면 표가 켜는 걸 막는다 — 03_tagging_gate.sql)\n"
                 f"   고를 수 있는 값: {' | '.join(MOODS)}")

    if a.from_json:
        pins = json.loads(pathlib.Path(a.from_json).read_text(encoding="utf-8"))
        print(f"  목록에서 핀 {len(pins)}개를 읽었다")
    else:
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
        print(f"\n  실제로 받으려면 --mood 와 --temp 를 정해서 다시:")
        print(f"    python3 tech/supabase/pin_import.py {a.board} --mood Y2K --temp warm"
              f"{' --rain' if a.rain else ''}")
        return 0

    picked, got = [], []
    start = next_id()
    for i, p in enumerate(fresh):
        num = start + i
        try:
            save_photo(p["img_url"], num)
        except Exception as e:
            print(f"  ⚠️ {num:02d} 건너뜀 — {e}"); continue
        picked.append(dict(n=num, name=p["title"][:60] or f"코디 {num}", url=p["pin_url"]))
        got.append(p["pin_url"])
        print(f"  ✓ {num:02d}.jpg  {p['title'][:40]}")

    if not picked:
        print("  받은 게 없다."); return 1

    LEDGER.write_text("\n".join(sorted(seen | set(got))) + "\n", encoding="utf-8")
    print(f"\n  ✓ 사진 {len(picked)}장 → prototype/proto_img/")

    # 색을 보드 단위로 고정했으면 SQL 을 바로 만든다.
    # 안 그랬으면 사진을 보고 색을 골라야 하므로 고르는 화면을 만든다 (자동 추출은 41%라 폐기).
    if a.color:
        out = ROOT / f"tech/supabase/import_{board}.sql"
        rows = [sql_row(d["n"], {"title": d["name"], "pin_url": d["url"]},
                        a.mood, a.color, a.temp, a.rain) for d in picked]
        out.write_text(
            f"-- {a.board} 에서 받아온 코디 {len(rows)}개 · 컨셉 {a.mood} · 색 {a.color}\n"
            f"-- pin_import.py 가 만든 파일이다. Supabase SQL Editor 에 붙여넣고 Run.\n"
            "--\n"
            f"-- 온도 {BAND[a.temp][0]}~{BAND[a.temp][1]}° · "
            f"{'비 적합' if a.rain else '비 부적합'} 으로 들어간다 — 넘겨짚은 값이 아니라\n"
            "--    보드를 그렇게 나눠서 받았다는 뜻이다. 보드가 섞여 있었다면 지금 고쳐야 한다.\n"
            "-- 🔴 source_license 는 'unverified' 다. 인터넷에 올리면 안 된다 (RG-4).\n"
            "-- 🔴 구성 아이템(items)은 비어 있다 — 핀터레스트가 주지 않는다.\n\n"
            "insert into library_looks\n"
            "  (image_path, name, source_url, mood, color_primary,\n"
            "   temp_min, temp_max, rain_ok, active)\n"
            "values\n" + ",\n".join(rows) + "\non conflict (source_url) where source_url is not null do nothing;\n",
            encoding="utf-8")
        print(f"  ✓ SQL → {out.relative_to(ROOT)}")
        print(f"\n  다음: 그 파일을 Supabase SQL Editor 에 붙여넣고 Run.")
        return 0

    sheet = ROOT / f"prototype/tag_{board}.html"
    write_sheet(sheet, a.board, picked, a.mood, a.temp, a.rain)
    print(f"  ✓ 색 고르는 화면 → {sheet.relative_to(ROOT)}")
    print(f"\n  {a.mood} · {'☔ 비 적합' if a.rain else '☀️ 비 부적합'} · "
          f"{a.temp}({BAND[a.temp][0]}~{BAND[a.temp][1]}°) 로 들어간다.")
    print(f"\n  다음 (2단계):")
    print(f"   1. 이 화면을 열어서 사진마다 색을 누른다:")
    print(f"        open {sheet.relative_to(ROOT)}")
    print(f"   2. 다 누르면 SQL 이 나온다 → 복사해서 Supabase SQL Editor 에 붙여넣고 Run")
    return 0


if __name__ == "__main__":
    # 파이썬 오류를 그대로 뱉지 않는다 — 이 스크립트를 돌리는 사람은 개발자가 아니다
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit("\n  멈췄다.")
    except Exception as e:
        sys.exit(f"❌ {e}")

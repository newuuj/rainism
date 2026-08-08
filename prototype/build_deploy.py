#!/usr/bin/env python3
"""배포용 자립 파일 빌드 — 원본에서 사진을 base64로 박아 링크 하나로 여는 파일을 만든다.

왜 필요한가: 원본(rainism_prototype_v1.html)은 사진을 ./proto_img/ 상대경로로 부른다.
그대로 배포하면 사진이 안 뜬다(CLAUDE.md "아티팩트로 공유할 때"). 그래서 사진을
파일 안에 통째로 박은 자립본을 따로 만든다. 폰트는 원본이 이미 인라인하고 있어 그대로 딸려온다.

쓰는 법:  python3 prototype/build_deploy.py
원본을 고칠 때마다 다시 돌리면 된다. 원본은 건드리지 않는다.
"""
import base64, re, subprocess, tempfile, pathlib, sys

HERE   = pathlib.Path(__file__).resolve().parent
SRC    = HERE / "rainism_prototype_v1.html"
OUT    = HERE / "rainism_deploy_single.html"
IMGDIR = HERE / "proto_img"
LONG_EDGE = 520   # CLAUDE.md 기준: sips -Z 520 으로 줄인다

# 1) proto_img 전부 520px로 줄여 base64로. 파일명 NN.jpg 의 NN 이 코디 id.
img_b64 = {}
for f in sorted(IMGDIR.glob("*.jpg")):
    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=True) as tmp:
        subprocess.run(["sips", "-Z", str(LONG_EDGE), str(f), "--out", tmp.name],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
        raw = pathlib.Path(tmp.name).read_bytes()
    img_b64[int(f.stem)] = "data:image/jpeg;base64," + base64.b64encode(raw).decode()

html = SRC.read_text(encoding="utf-8")

# 2) 런타임 경로 조합(동적)을 id→base64 사전으로 교체.
#    원본:  LOOKS.forEach(l=> l.img='./proto_img/'+String(l.id).padStart(2,'0')+'.jpg');
DYN = "LOOKS.forEach(l=> l.img='./proto_img/'+String(l.id).padStart(2,'0')+'.jpg');"
if DYN not in html:
    sys.exit("❌ 원본에서 이미지 조합 라인을 못 찾음 — 원본이 바뀌었다. build_deploy.py의 DYN 을 맞춰라.")
img_obj = "const IMG={" + ",".join(f'{n}:"{v}"' for n, v in sorted(img_b64.items())) + "};"
html = html.replace(DYN, img_obj + "\nLOOKS.forEach(l=> l.img=IMG[l.id]);")

# 3) 정적으로 박힌 퀴즈 사진(./proto_img/NN.jpg)도 base64로.
missing = []
def _repl(m):
    n = int(m.group(1))
    if n not in img_b64: missing.append(n); return m.group(0)
    return 'src="' + img_b64[n] + '"'
html = re.sub(r'src="\./proto_img/(\d+)\.jpg"', _repl, html)

# 4) 검증 — 사진 없는 id 를 코디가 참조하면 그 코디는 화면에서 깨진다(원칙 9-1).
look_ids = {int(x) for x in re.findall(r"\{id:(\d+),", html)}
broken   = sorted(look_ids - set(img_b64))
leftover = html.count("./proto_img/")
if missing:  print(f"⚠️  퀴즈 사진 없음: {missing}")
if broken:   print(f"⚠️  코디가 참조하는데 사진이 없는 id: {broken} — 이 코디는 이미지가 깨진다")
if leftover: print(f"⚠️  아직 남은 상대경로 참조 {leftover}개 (배포하면 그 자리 사진이 안 뜬다)")

OUT.write_text(html, encoding="utf-8")
print(f"✓ {OUT.name} — 사진 {len(img_b64)}장 인라인 · {OUT.stat().st_size//1024}KB")
if not (missing or broken or leftover):
    print("✓ 깨질 사진 없음")

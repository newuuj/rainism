#!/usr/bin/env python3
"""프로토타입 화면 캡쳐 — 손으로 가기 어려운 예외 화면까지 한 번에.

  python3 prototype/shot.py 오늘
  python3 prototype/shot.py 오늘 기록
  python3 prototype/shot.py 오늘 --sim lib=thin        # 라이브러리 부족한 날
  python3 prototype/shot.py 오늘 --sim auth=expired    # 세션 만료
  python3 prototype/shot.py all                        # 전부

사진은 prototype/shots/ 에 저장됩니다. 그 다음 Claude에게 "shots 폴더 봐줘" 하면 됩니다.
"""
import os, sys, pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
OUT = HERE / "shots"; OUT.mkdir(exist_ok=True)
VIEW = {"width": 402, "height": 874}   # iPhone 17 논리 화면 크기(pt). ×2로 찍어 804×1748px
# 기본은 더블클릭과 같은 file://. 웹서버(http)로 확인할 땐 주소를 넣어준다 — 둘은 동작이 다르다(AGENTS §9-2):
#   RAINISM_URL=http://localhost:8899/prototype/rainism_prototype_v1.html python3 prototype/shot.py 오늘
URL = os.environ.get("RAINISM_URL") or ("file://" + str((HERE / "rainism_prototype_v1.html").resolve()))

# 화면 이름 → 거기까지 가는 클릭 순서 (온보딩을 매번 통과해야 도달함)
# ※ '날씨'는 오늘 탭 안 카드로 합쳤다(2026-08-17). '날씨선택'도 뺐다 — 결과 화면의 데모 버튼 4개를 지워서
#    이제 그 화면엔 우하단 🧪 상황 패널로만 간다
QUIZ = ["#s-q1 .moodgrid button:nth-child(4)", "#moodNext"]   # 질문은 사진 고르기 하나뿐 → 내 옷 화면으로
# 스플래시엔 버튼이 없다(2.4초 뒤 자동으로 넘어감). 클릭은 화면이 보일 때까지 알아서 기다린다
CLOSET = ["#closetGrid .citem:nth-child(1)",   # 퀴즈 다음은 옷장이다 — 몇 개 고르고 넘어간다
          "#closetGrid .citem:nth-child(4)",   # (2026-08-17 흩뿌리기로 바뀌며 그룹이 없어졌다)
          "#closetGrid .citem:nth-child(9)",
          "#closetNext"]
# 위치를 허용하면 동네 화면을 건너뛴다. 캡쳐용 브라우저는 위치가 막혀 있어 자동으로 동네 화면에 떨어진다
DONG = ["#s-location .btn"]   # 이 동네로 할게요 → 날씨 자동 → 결과
TO_RESULT = QUIZ + CLOSET + DONG

# 스스로 지나가 버려서 그냥은 못 찍는 화면 → 다 지나간 뒤 그 화면만 다시 띄워 찍는다
REPAINT = {"시작": "s-splash", "위치": "s-locating"}

SCREENS = {
    "시작":   [],                        # 스플래시 — 자동으로 넘어가기 전에 찍힌다
    "컨셉":   ["#s-q1 h2"],               # 제목 클릭 = 아무 일도 안 하지만 스플래시가 넘어갈 때까지 기다려준다
    "옷장":   QUIZ + CLOSET[:3],           # 컨셉 다음 = 내 옷 고르기 (고른 상태)
    "위치":   QUIZ + CLOSET,               # 위치 물어보는 화면 (스스로 지나가므로 REPAINT 로 다시 띄운다)
    "동네":   QUIZ + CLOSET,               # 위치가 막히면 자동으로 여기로 떨어진다
    "오늘":   TO_RESULT,
    "결정":   TO_RESULT + [".look:nth-child(1) .heart"],
    "기록":   TO_RESULT + ["#tab-calendar"],
}

def main():
    argv = sys.argv[1:]
    cut = argv.index("--sim") if "--sim" in argv else len(argv)
    args = argv[:cut]                                    # --sim 앞 = 화면 이름
    sims = dict(kv.split("=") for kv in argv[cut + 1:])  # --sim 뒤 = 상황
    names = list(SCREENS) if (not args or args[0] == "all") else args

    with sync_playwright() as pw:
        browser = pw.chromium.launch()
        page = browser.new_page(viewport=VIEW, device_scale_factor=2)
        # 매 화면을 '처음 열어본 사람'으로 찍는다. 페이지 스크립트보다 먼저 지워야 한다 —
        # 열고 나서 지우면 앱이 아직 받아오는 중(라이브러리·날씨)이라 그 뒤에 다시 저장돼 버린다.
        page.add_init_script("try{localStorage.clear()}catch(e){}")
        for name in names:
            steps = SCREENS.get(name)
            if steps is None:
                print(f"  ? 모르는 화면: {name} — 가능한 이름: {', '.join(SCREENS)}"); continue
            page.goto(URL); page.wait_for_timeout(400)
            # 데모 전용 떠다니는 버튼 두 개는 앱 화면이 아니다 — 포트폴리오 사진엔 안 나오게
            page.evaluate("['simfab','metfab'].forEach(id=>{const e=document.getElementById(id); if(e) e.style.display='none';})")
            for k, v in sims.items():
                page.evaluate(f"setSim('{k}','{v}')")
            for sel in steps:
                page.click(sel); page.wait_for_timeout(350)
            page.wait_for_timeout(700)                       # 스켈레톤이 걷힐 때까지
            if name in REPAINT:                              # 스스로 지나가 버리는 화면
                page.wait_for_timeout(500)                   # 다 지나갈 때까지 기다렸다가
                page.evaluate(f"paint('{REPAINT[name]}')")   # 다시 띄워 찍는다
            suffix = ("_" + "_".join(f"{k}-{v}" for k, v in sims.items())) if sims else ""
            order = list(SCREENS).index(name) + 1          # 파일명 앞 번호 = 유저 플로우 순서(포트폴리오용 정렬)
            # 긴 화면은 한 장으로 안 찍는다 — 폰 한 대 높이씩 잘라서 여러 컷.
            # 통짜로 찍으면 세로가 폰 비율을 한참 넘어서 PDF로 인쇄할 때 아래가 잘린다.
            total = page.evaluate("Math.max(document.body.scrollHeight, document.documentElement.scrollHeight)")
            cuts = max(1, -(-total // VIEW["height"]))     # 올림 나눗셈
            for i in range(cuts):
                page.evaluate(f"window.scrollTo(0,{i * VIEW['height']})")
                page.wait_for_timeout(250)
                path = OUT / f"{order:02d}_{name}{suffix}_{i+1}.png"
                page.screenshot(path=str(path))            # full_page 아님 = 딱 폰 한 화면
                print(f"  ✓ {path.relative_to(HERE.parent)}")
        browser.close()

if __name__ == "__main__":
    main()

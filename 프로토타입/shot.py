#!/usr/bin/env python3
"""프로토타입 화면 캡쳐 — 손으로 가기 어려운 예외 화면까지 한 번에.

  python3 프로토타입/shot.py 오늘
  python3 프로토타입/shot.py 오늘 기록 날씨
  python3 프로토타입/shot.py 오늘 --sim lib=thin        # 라이브러리 부족한 날
  python3 프로토타입/shot.py 오늘 --sim auth=expired    # 세션 만료
  python3 프로토타입/shot.py all                        # 전부

사진은 프로토타입/shots/ 에 저장됩니다. 그 다음 Claude에게 "shots 폴더 봐줘" 하면 됩니다.
"""
import sys, pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
OUT = HERE / "shots"; OUT.mkdir(exist_ok=True)
URL = "file://" + str((HERE / "rainism_prototype_v1.html").resolve())

# 화면 이름 → 거기까지 가는 클릭 순서 (온보딩을 매번 통과해야 도달함)
QUIZ = ["#s-q1 .moodgrid button:nth-child(4)", "#s-q2 .choices .choice:nth-child(2)",
        "#s-q3 .choices .choice:nth-child(1)", "#s-photo .btn:not(.ghost)"]
START = ["#s-splash .btn", "#s-gender .choices .choice:nth-child(1)",
         "#s-age .choices .choice:nth-child(2)"]
CONSENT = ["#s-consent .btn"]
TO_RESULT = START + CONSENT + QUIZ + [".weatherpick button:nth-child(1)"]

SCREENS = {
    "시작":   [],
    "동의":   START,
    "무드":   START + CONSENT,
    "사진":   START + CONSENT + QUIZ[:3],
    "날씨선택": START + CONSENT + QUIZ,
    "오늘":   TO_RESULT,
    "결정":   TO_RESULT + [".look:nth-child(1) .heart"],
    "날씨":   TO_RESULT + ["#tab-weather"],
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
        page = browser.new_page(viewport={"width": 430, "height": 900}, device_scale_factor=2)
        for name in names:
            steps = SCREENS.get(name)
            if steps is None:
                print(f"  ? 모르는 화면: {name} — 가능한 이름: {', '.join(SCREENS)}"); continue
            page.goto(URL); page.evaluate("localStorage.clear()")
            page.reload(); page.wait_for_timeout(400)
            page.evaluate("document.getElementById('simfab').style.display='none'")
            for k, v in sims.items():
                page.evaluate(f"setSim('{k}','{v}')")
            for sel in steps:
                page.click(sel); page.wait_for_timeout(350)
            page.wait_for_timeout(700)                       # 스켈레톤이 걷힐 때까지
            suffix = ("_" + "_".join(f"{k}-{v}" for k, v in sims.items())) if sims else ""
            path = OUT / f"{name}{suffix}.png"
            page.screenshot(path=str(path), full_page=True)
            print(f"  ✓ {path.relative_to(HERE.parent)}")
        browser.close()

if __name__ == "__main__":
    main()

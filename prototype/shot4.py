#!/usr/bin/env python3
"""4개 날씨 시나리오 결과화면을 한 번에 캡쳐 (일회용 검증 스크립트).
   shot.py는 날씨 1번(장마)만 눌러서 나머지 3개를 못 본다."""
import pathlib
from playwright.sync_api import sync_playwright

HERE = pathlib.Path(__file__).parent
OUT = HERE / "shots"; OUT.mkdir(exist_ok=True)
URL = "file://" + str((HERE / "rainism_prototype_v1.html").resolve())

START = ["#s-splash .btn", "#genderRow .pick:nth-child(1)",
         "#ageList .pick:nth-child(2)", "#onbNext"]
CONSENT = ["#s-consent .btn"]
QUIZ = ["#s-q1 .moodgrid button:nth-child(4)", "#moodNext",
        "#s-q2 .choices .choice:nth-child(2)", "#colorNext",
        "#s-q3 .choices .choice:nth-child(1)", "#tpoNext",
        "#s-photo .btn.ghost"]
DONG = ["#s-location .btn"]

NAMES = ["장마", "무더위", "선선한비", "맑음"]

with sync_playwright() as pw:
    b = pw.chromium.launch()
    page = b.new_page(viewport={"width": 430, "height": 900}, device_scale_factor=2)
    for i, nm in enumerate(NAMES, start=1):
        page.goto(URL); page.evaluate("localStorage.clear()")
        page.reload(); page.wait_for_timeout(400)
        page.evaluate("document.getElementById('simfab').style.display='none'")
        for sel in START + CONSENT + QUIZ + DONG:
            page.click(sel); page.wait_for_timeout(300)
        page.click(f".weatherpick button:nth-child({i})"); page.wait_for_timeout(1200)
        p = OUT / f"chk_{nm}.png"
        page.screenshot(path=str(p), full_page=True)
        print("  OK", p.name)
        # 하드필터 검증: 비 오는 날 비 부적합 룩이 섞였나 + 카드 문장
        info = page.evaluate("""() => ({
            rain: state.weather.rain,
            key: state.weather.key,
            picks: currentPicks.map(l => ({name:l.name, rain:l.rain, items:l.items})),
            taste: document.getElementById('r-taste').textContent,
            reasons: [...document.querySelectorAll('.look .reason')].map(e=>e.textContent.trim()),
            shownItems: [...document.querySelectorAll('.look .items')].map(e=>e.textContent.trim())
        })""")
        bad = [p2["name"] for p2 in info["picks"] if info["rain"] and not p2["rain"]]
        print("     날씨:", info["key"], "| 비:", info["rain"])
        print("     취향줄:", info["taste"])
        for r, it in zip(info["reasons"], info["shownItems"]):
            print("       -", r, "||", it)
        print("     하드필터 위반:", bad if bad else "없음")
    b.close()

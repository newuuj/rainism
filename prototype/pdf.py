#!/usr/bin/env python3
"""설계 노트 → 제출용 PDF.  python3 prototype/pdf.py

브라우저 Cmd+P 로 뽑아도 되지만, 그 경우 '배경 그래픽' 체크를 매번 켜야 하고
축소 배율이 컴퓨터마다 달라진다. 여기서 뽑으면 늘 같은 결과가 나온다."""
import pathlib
from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).parent.parent
SRC  = ROOT / "flow_walkthrough.html"
OUT  = ROOT / "flow_walkthrough.pdf"

with sync_playwright() as pw:
    b = pw.chromium.launch()
    p = b.new_page()
    p.goto("file://" + str(SRC.resolve()))
    p.wait_for_load_state("networkidle")          # 웹폰트·사진 다 받고 나서
    p.pdf(path=str(OUT), format="A4", print_background=True,
          margin={"top": "12mm", "bottom": "12mm", "left": "10mm", "right": "10mm"})
    b.close()
print("✓", OUT, f"({OUT.stat().st_size/1e6:.1f} MB)")

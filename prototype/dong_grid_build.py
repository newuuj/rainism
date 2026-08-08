#!/usr/bin/env python3
"""전국 동네표 만들기 — 기상청 격자 엑셀 → dong_grid.js

왜 필요한가: GPS가 잡아준 위경도를 "마포구 서교동" 같은 이름으로 바꾸고, 그 동네의
날씨를 부를 기상청 격자번호(nx, ny)를 알아야 한다. 기상청이 배포하는 격자표에 그 셋이
한꺼번에 들어있다 — 이름·위경도·격자. 그래서 지도 API(카카오 등) 없이 끝난다.

원본: 공공데이터포털 "기상청_단기예보 조회서비스" 활용가이드에 첨부된
      격자_위경도 엑셀. 로그인이 필요해 아래 미러에서 받는다(내용 동일).
      확인용 지표: 서울 종로구 = 격자 60, 127 (기상청 문서의 대표 예시값)

쓰는 법:  python3 prototype/dong_grid_build.py
          기상청이 표를 갱신했을 때만 다시 돌리면 된다. 결과(dong_grid.js)는 커밋한다.

의존성 없음 — xlsx 는 zip+xml 이라 파이썬 기본 기능으로 읽는다.
"""
import io, json, pathlib, re, subprocess, xml.etree.ElementTree as ET, zipfile

SRC = "https://raw.githubusercontent.com/boolint-kim/kma-grid-location/main/raw/location.xlsx"
OUT = pathlib.Path(__file__).resolve().parent / "dong_grid.js"
NS  = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"

# 화면에 쓰는 이름 규칙 — 기존 동네 목록과 같은 모양으로 맞춘다.
#   서울은 시도를 뗀다("마포구 서교동"), 나머지는 짧게 붙인다("부산 해운대구 우동").
SIDO = {
    '서울특별시':'', '부산광역시':'부산', '대구광역시':'대구', '인천광역시':'인천',
    '광주광역시':'광주', '대전광역시':'대전', '울산광역시':'울산', '세종특별자치시':'세종',
    '경기도':'경기', '강원특별자치도':'강원', '충청북도':'충북', '충청남도':'충남',
    '전북특별자치도':'전북', '전라남도':'전남', '경상북도':'경북', '경상남도':'경남',
    '제주특별자치도':'제주',
}

def display_name(sido, sigungu, dong):
    """'경기도' + '수원시장안구' + '파장동' → '경기 수원시 장안구 파장동'"""
    head = SIDO.get(sido, sido)
    sigungu = re.sub(r'(시)(\S+구)$', r'\1 \2', sigungu)      # 수원시장안구 → 수원시 장안구
    dong = dong.split('/')[0]                                 # '대정읍/마라도포함' → '대정읍'
    if sigungu == sido: sigungu = ''                          # 세종특별자치시가 두 번 나오는 것 방지
    return ' '.join(p for p in (head, sigungu, dong) if p)

def col_index(ref):
    """셀 좌표 'AB12' → 열 번호 27. (A=0)"""
    n = 0
    for ch in ref:
        if not ch.isalpha(): break
        n = n * 26 + (ord(ch.upper()) - 64)
    return n - 1

def read_rows(xlsx_bytes):
    """엑셀 한 줄을 열 순서대로 돌려준다.

    ⚠️ 엑셀은 빈 칸을 XML에 아예 안 적는다. 그래서 셀을 나오는 순서대로 담으면
       빈 칸이 있는 줄부터 값이 통째로 밀린다(실제로 강원도 9줄이 그랬다 —
       동네 이름 자리에 숫자가, 경도 자리에 날짜가 들어왔다).
       그래서 각 셀의 좌표(A1·F1…)를 보고 제자리에 넣는다.
    """
    z = zipfile.ZipFile(io.BytesIO(xlsx_bytes))
    shared = ["".join(t.text or "" for t in si.iter(f"{NS}t"))
              for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall(f"{NS}si")]
    sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    for row in sheet.find(f"{NS}sheetData").findall(f"{NS}row"):
        out = []
        for c in row.findall(f"{NS}c"):
            v = c.find(f"{NS}v")
            val = "" if v is None else (shared[int(v.text)] if c.get("t") == "s" else v.text)
            i = col_index(c.get("r", ""))
            if i < 0: i = len(out)                       # 좌표가 없으면 그냥 뒤에 붙인다
            while len(out) <= i: out.append("")          # 빈 칸은 빈 칸으로 채워 자리를 맞춘다
            out[i] = val
        yield out

print("내려받는 중…")
# 파이썬 기본 다운로드는 이 맥에서 인증서 검증에 실패한다(python.org 설치본에 CA 목록이 없음).
# 검증을 끄는 대신 시스템 인증서를 쓰는 curl 에 맡긴다.
xlsx = subprocess.run(["curl", "-sSLf", "--max-time", "120", SRC],
                      capture_output=True, check=True).stdout
rows = list(read_rows(xlsx))[1:]

table = []
for r in rows:
    if len(r) < 15: continue
    sido, sigungu, dong, nx, ny, lon, lat = r[2], r[3], r[4], r[5], r[6], r[13], r[14]
    if not dong or not lat or not lon: continue          # 읍·면·동 행만 (시도·시군구 요약행 제외)
    table.append([display_name(sido, sigungu, dong),
                  round(float(lat), 4), round(float(lon), 4),   # 소수 4자리 = 약 11m. 5km 격자엔 차고 넘친다
                  int(nx), int(ny)])

# 검증 — 못 믿을 표를 조용히 넣지 않는다(§9-3)
seoul = [t for t in table if t[0].startswith('종로구')]
assert table, "표가 비었다 — 원본 형식이 바뀌었는지 확인할 것"
assert seoul and (seoul[0][3], seoul[0][4]) == (60, 127), \
    f"종로구 격자가 60,127 이 아니다 → {seoul[:1]} (원본이 바뀌었다)"
assert all(33 < t[1] < 39 and 124 < t[2] < 132 for t in table), "한반도 밖 좌표가 섞여 있다"

body = "[\n" + ",\n".join(json.dumps(t, ensure_ascii=False) for t in table) + "\n]"
OUT.write_text(
    "/* 전국 동네표 — 기상청 격자 엑셀에서 만든 것. 손으로 고치지 말 것.\n"
    "   다시 만들기: python3 prototype/dong_grid_build.py\n"
    f"   [이름, 위도, 경도, 격자X, 격자Y] · {len(table)}개 */\n"
    f"const DONG_GRID = {body};\n", encoding="utf-8")

print(f"✓ {OUT.name} — 동네 {len(table)}개 · {OUT.stat().st_size//1024}KB")
print(f"  확인: {seoul[0]}")

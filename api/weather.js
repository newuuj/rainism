/* 기상청 단기예보 중계 (Vercel 서버리스 · api/weather.js)
   ───────────────────────────────────────────────────────────────
   왜 있나: 인증키를 브라우저에 못 내보낸다. 이 저장소는 공개라 HTML에 넣으면
            소스 보기로 그대로 새어나간다. 그래서 키를 아는 자리는 여기 하나뿐이다.
            (키 넣는 자리 = tech/weather_api_key_setup.md)
   입력  : /api/weather?nx=60&ny=127   ← 격자번호는 prototype/dong_grid.js 에 동네별로 있다
   출력  : { base, days:{ "20260816":{ temp, band, rain, pop, ... } } }
            숫자만 낸다. 제목·안내문 같은 '말'은 프로토타입이 만든다.
   확인  : node api/weather.js   ← 파싱이 맞는지 자체 점검이 돌아간다 */

const KMA = 'https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst';

/* 코디는 낮에 입는다 → 하루를 06~21시로 본다. 기상청 3시간 슬롯이 딱 6개라
   날씨 탭의 막대 6개와도 맞는다. ※ 06~21은 에이전트가 정한 값(AGENTS §7). */
const SLOTS = ['0600', '0900', '1200', '1500', '1800', '2100'];

const pad = n => String(n).padStart(2, '0');
const ymd = d => `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`;

/* 기상청은 KST로 돌고 Vercel 서버는 UTC로 돈다 → 9시간 더해두고 getUTC*로 읽는다.
   서버가 어느 시간대에 있든 같은 답이 나오게 하는 게 목적이다. */
const kstNow = () => new Date(Date.now() + 9 * 3600e3);

/* 발표시각 8번(02·05·08·11·14·17·20·23시). 정각 10분은 지나야 값이 나온다. */
function latestBase(now) {
  const h = now.getUTCHours(), m = now.getUTCMinutes();
  const hit = [23, 20, 17, 14, 11, 8, 5, 2].find(b => h > b || (h === b && m >= 10));
  if (hit != null) return { date: ymd(now), time: pad(hit) + '00' };
  const y = new Date(now.getTime() - 86400e3);        // 00:00~02:09 = 어제 23시 발표가 최신
  return { date: ymd(y), time: '2300' };
}
/* 한 단계 전 발표시각 — 방금 발표분이 아직 안 올라왔을 때 한 번 물러선다 */
function prevBase(b) {
  const d = new Date(Date.UTC(+b.date.slice(0, 4), +b.date.slice(4, 6) - 1, +b.date.slice(6), +b.time.slice(0, 2)));
  return latestBase(new Date(d.getTime() - 3600e3 + 10 * 60e3));
}

/* PCP는 숫자가 아니라 말로 온다: "강수없음" · "1mm 미만" · "2.0mm" · "30.0~50.0mm" · "50.0mm 이상" */
function mmOf(v) {
  if (!v || v === '강수없음' || v === '-' || v === '0') return 0;
  if (v.includes('미만')) return 0.5;
  const n = v.match(/[\d.]+/g);
  if (!n) return 0;
  return n.length > 1 ? (+n[0] + +n[1]) / 2 : +n[0];
}

/* 체감온도 밴드 = PRD §8.2 / CSV[1]. 습도 70%↑면 한 칸 위로(CSV[5] 매핑 규칙).
   🚫 체감온도 산출식은 문서에 없고 "임의 식 확정 금지"라 적혀 있다(PRD §8.3 미결) →
      식을 지어내지 않고 문서에 있는 규칙(기온 밴드 + 습도 보정)만 쓴다.
      그래서 화면도 '체감'이 아니라 '기온'이라고 말한다(AGENTS §9-1). */
const BANDS = ['chilly', 'cool', 'warm', 'hot'];
function bandOf(t, reh) {
  let i = t >= 28 ? 3 : t >= 23 ? 2 : t >= 20 ? 1 : 0;
  if (reh >= 70) i = Math.min(3, i + 1);
  return BANDS[i];
}

/* 하루치 예보 → 화면이 쓰는 숫자 한 묶음. 06~21시 안에 값이 없으면 null(=그날은 못 낸다) */
function summarize(items) {
  const day = items.filter(i => SLOTS.includes(i.fcstTime));
  const at = (t, c) => { const r = day.find(i => i.fcstTime === t && i.category === c); return r ? r.fcstValue : null; };
  const of = c => day.filter(i => i.category === c);
  const temps = of('TMP').map(i => ({ t: i.fcstTime, v: +i.fcstValue }));
  if (!temps.length) return null;

  /* 대표값 = 그날 가장 더운 시각. 사람이 실제로 마주치는 상한이라 옷 두께를 여기에 맞춘다.
     ※ '가장 더운 시각'은 에이전트가 정한 값(AGENTS §7). */
  const peak = temps.reduce((a, b) => (b.v > a.v ? b : a));
  const humid = +at(peak.t, 'REH') || 0;
  const slots = SLOTS.filter(t => day.some(i => i.fcstTime === t && i.category === 'POP'));
  const maxPop = Math.max(0, ...of('POP').map(i => +i.fcstValue));
  const mm = Math.round(of('PCP').reduce((s, i) => s + mmOf(i.fcstValue), 0) * 10) / 10;

  /* 비로 볼 것인가 = 강수량(PCP)·강수형태(PTY)로 정한다. 확률(POP)로 정하지 않는다 — CSV[5] 매핑:
       "PCP 범주 파싱 → 강수 단계 · POP·PTY로 우산/소재 규칙 발동"
     확률 30%만 갖고 비로 치면 예보상 비가 한 방울도 없는 맑은 날까지 레인 코디만 남는다
     (2026-08-17·18이 실제로 그랬다: PCP 강수없음 · PTY 0 · POP 30). 확률은 우산 안내에 쓴다. */
  const rain = mm > 0 || of('PTY').some(i => +i.fcstValue !== 0);

  const one = c => { const r = items.find(i => i.category === c); return r ? Math.round(+r.fcstValue) : null; };
  const tmn = one('TMN'), tmx = one('TMX');

  return {
    temp: peak.v, at: peak.t, band: bandOf(peak.v, humid), humid,
    rain, maxPop, pop: slots.map(t => +at(t, 'POP')), hrs: slots.map(t => +t.slice(0, 2) + '시'),
    mm, sky: +at(peak.t, 'SKY') || 1,
    tmn, tmx, gap: (tmn != null && tmx != null) ? tmx - tmn : null,
  };
}

async function callKma(key, base, nx, ny) {
  const q = new URLSearchParams({
    serviceKey: key, pageNo: '1', numOfRows: '1000', dataType: 'JSON',
    base_date: base.date, base_time: base.time, nx: String(nx), ny: String(ny),
  });
  const r = await fetch(KMA + '?' + q, { signal: AbortSignal.timeout(7000) });
  const body = await r.text();
  if (!body.trim().startsWith('{')) throw new Error('기상청이 JSON이 아닌 답을 보냈습니다: ' + body.slice(0, 120));
  const j = JSON.parse(body);
  const code = j.response?.header?.resultCode;
  if (code !== '00') throw new Error(j.response?.header?.resultMsg || 'resultCode ' + code);
  return j.response.body.items.item;
}

module.exports = async (req, res) => {
  /* Encoding 키·Decoding 키 어느 쪽을 넣어도 되게 한 번 풀어준다.
     (두 키가 겉보기로 구분이 안 돼서 잘못 넣고 헤매는 일이 흔하다) */
  const key = decodeURIComponent((process.env.KMA_SERVICE_KEY || '').trim());
  if (!key) return res.status(500).json({ error: 'NO_KEY', msg: 'KMA_SERVICE_KEY 환경변수가 비어 있습니다' });

  const nx = parseInt(req.query.nx, 10), ny = parseInt(req.query.ny, 10);
  if (!(nx > 0 && ny > 0)) return res.status(400).json({ error: 'BAD_GRID', msg: 'nx·ny 가 필요합니다' });

  let base = latestBase(kstNow()), items;
  try {
    items = await callKma(key, base, nx, ny);
  } catch (e) {
    try { base = prevBase(base); items = await callKma(key, base, nx, ny); }   // 방금 발표분이 아직이면 한 단계 전으로
    catch (e2) { return res.status(502).json({ error: 'KMA_FAIL', msg: e2.message }); }
  }

  const days = {};
  for (const d of [...new Set(items.map(i => i.fcstDate))]) {
    const s = summarize(items.filter(i => i.fcstDate === d));
    if (s) days[d] = s;
  }
  /* 기상청은 3시간마다 새로 낸다 → 30분 캐시. 하루 10,000회 한도를 지키는 값이기도 하다 */
  res.setHeader('Cache-Control', 's-maxage=1800, stale-while-revalidate=3600');
  res.status(200).json({ base: base.date + ' ' + base.time, nx, ny, days });
};

/* ── 자체 점검: node api/weather.js ──────────────────────────────
   파싱이 깨지면 화면엔 "그냥 예시 날씨"로 조용히 폴백돼서 안 보인다. 그래서 여기서 잡는다. */
if (require.main === module) {
  const mk = (fcstTime, category, fcstValue) => ({ fcstDate: '20260816', fcstTime, category, fcstValue });
  const fx = [
    ...SLOTS.map((t, i) => mk(t, 'TMP', [24, 25, 28, 29, 28, 26][i])),
    ...SLOTS.map((t, i) => mk(t, 'POP', [60, 60, 60, 60, 0, 0][i])),
    ...SLOTS.map((t, i) => mk(t, 'PTY', [1, 1, 1, 1, 0, 0][i])),
    ...SLOTS.map((t, i) => mk(t, 'REH', [90, 85, 75, 70, 70, 80][i])),
    ...SLOTS.map((t, i) => mk(t, 'PCP', ['7.0mm', '2.0mm', '1mm 미만', '2.0mm', '강수없음', '강수없음'][i])),
    ...SLOTS.map(t => mk(t, 'SKY', '4')),
    mk('0600', 'TMN', '24.0'), mk('1500', 'TMX', '30.0'),
  ];
  const s = summarize(fx);
  const eq = (got, want, what) => { if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error(`${what}: ${JSON.stringify(got)} ≠ ${JSON.stringify(want)}`); };
  eq(s.temp, 29, '대표기온(그날 최고)');
  eq(s.humid, 70, '대표시각의 습도');
  eq(s.band, 'hot', '29도+습도70% → warm에서 한 칸 위');           // CSV[5] 습도 보정
  eq(s.rain, true, '비 여부');
  eq(s.pop, [60, 60, 60, 60, 0, 0], '시간별 강수확률');
  eq(s.hrs, [6, 9, 12, 15, 18, 21].map(h => h + '시'), '막대 이름표');
  eq(s.mm, 11.5, '하루 강수량 합(7+2+0.5+2)');
  eq(s.gap, 6, '일교차(30-24)');
  /* 확률만 30%이고 예보상 비는 없는 날 = 비 오는 날이 아니다 (2026-08-17 실제 사례) */
  const dry = summarize([...SLOTS.map(t => mk(t, 'TMP', '31')), ...SLOTS.map(t => mk(t, 'REH', '60')),
    ...SLOTS.map(t => mk(t, 'PCP', '강수없음')), ...SLOTS.map(t => mk(t, 'PTY', '0')),
    mk('0600', 'POP', '30'), ...SLOTS.slice(1).map(t => mk(t, 'POP', '0'))]);
  eq(dry.rain, false, '강수확률 30%만으로는 비 오는 날이 아니다');
  eq(dry.maxPop, 30, '확률은 그대로 남겨 우산 안내에 쓴다');
  eq(bandOf(25, 60), 'warm', '25도 습도60 → 따뜻함');
  eq(bandOf(21, 55), 'cool', '21도 → 선선함');
  eq(bandOf(18, 50), 'chilly', '18도 → 서늘');
  eq(mmOf('30.0~50.0mm'), 40, '범위 강수량은 가운데값');
  eq(mmOf('50.0mm 이상'), 50, '이상 표기');
  eq(summarize([mk('0300', 'TMP', '20')]), null, '06~21시 밖만 있으면 그날은 못 낸다');
  console.log('✓ api/weather.js 파싱 점검 통과');
}

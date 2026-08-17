/* 옷 사진 → 종류 자동 판별 (Vercel 서버리스 · api/tag.js)
   ───────────────────────────────────────────────────────────────
   왜 있나: 유저가 올린 옷 사진에 **무슨 옷이 있는지** 사람이 고르게 하지 않는다(2026-08-18 유저 결정).
            브라우저에서 돌리는 CLIP은 정확도가 33~57%라 못 썼다(AGENTS §10 실측). LLM은 사진을 보고
            "블라우스냐 셔츠냐" 같은 구분까지 한다. 키를 브라우저에 못 내보내니 여기를 거친다.
   입력  : POST /api/tag   { image: "data:image/png;base64,..." }
   출력  : { cats: ["반팔티","반바지"], conf: "high"|"low" }  · 못 고르면 { cats: [] }
            사진 한 장에 상의·하의·신발이 다 보이면 **전부** 낸다(2026-08-18 유저 요청)
   키    : ANTHROPIC_API_KEY  (.env.local + Vercel 환경변수. 🚫 HTML·JS에 넣지 말 것)
   확인  : node api/tag.js   ← 응답 파싱이 맞는지 자체 점검이 돌아간다

   ⚠️ AGENTS §5 의 "🚫 요청마다 LLM" 은 **추천 이유를 LLM으로 짓지 말라**는 뜻이다.
      추천은 지금도 결정론이다. 여기는 사진 한 장을 담을 때 딱 한 번 부르는 자리다. */

/* 프로토타입의 ITEM_ART 21종과 **글자까지 똑같아야 한다.** 다르면 화면이 못 알아본다. */
const CATS = ['반팔티', '긴팔티', '민소매·나시', '블라우스', '셔츠', '니트', '반바지', '스커트',
  '청바지', '와이드팬츠', '레깅스', '원피스', '가디건', '후드·맨투맨', '재킷', '레인재킷',
  '레인부츠', '스니커즈', '부츠', '샌들·슬리퍼', '플랫·로퍼'];

const PROMPT = `이 사진에 **보이는 옷을 전부** 아래 21가지에서 골라주세요.

${CATS.join(' / ')}

규칙:
- 사람이 상의와 하의를 같이 입고 있으면 **둘 다** 고르세요. 신발이 보이면 신발도 고르세요.
- 겉옷을 걸쳤고 안에 입은 상의도 보이면 둘 다 고르세요.
- **잘려서 잘 안 보이거나 가려진 옷은 빼세요.** 확실히 보이는 것만.
- 앞이 트여 겉에 걸치는 것은 겉옷입니다: 니트 소재면 가디건, 빳빳한 정장류면 재킷.
- 단추가 달린 빳빳한 칼라 상의는 셔츠, 얇고 하늘하늘한 여성용 상의는 블라우스입니다.
- 방수 소재의 겉옷은 레인재킷, 고무장화는 레인부츠입니다.
- 원피스는 상하의가 하나로 붙은 것입니다 — 원피스면 상의·하의를 따로 고르지 마세요.
- 위 21가지에 없는 것(가방·모자·액세서리)은 빼세요. 하나도 없으면 빈 배열로 두세요.

JSON만 출력하세요. 설명 금지.
{"cats": ["<21가지 중 하나>", ...], "conf": "high" 또는 "low"}`;

/* 모델 응답에서 우리가 아는 카테고리만 걸러낸다 — LLM이 "반팔 티셔츠"처럼 살짝 다르게 써도 살린다 */
function matchCat(raw) {
  raw = String(raw || '').trim();
  if (!raw || raw === 'null') return null;
  /* 공백을 지우고 견준다. 안 지우면 "반팔 티셔츠" 가 **「셔츠」로 읽힌다** — 앞의 "반팔 티"가
     공백에 끊겨 「반팔티」와 안 맞고, 뒤의 "셔츠"만 걸리기 때문이다(자체 점검이 잡은 실제 버그). */
  const flat = s => s.replace(/\s/g, '');
  const r = flat(raw);
  return CATS.includes(raw) ? raw
       : CATS.find(c => flat(c) === r)                            // 공백만 다른 경우
      || CATS.find(c => r.includes(flat(c)) || flat(c).includes(r))   // 그래도 안 맞으면 품고 있는지
      || null;
}
function parseTag(text) {
  let obj;
  try { obj = JSON.parse((text.match(/\{[\s\S]*\}/) || [text])[0]); }
  catch (e) { return { cats: [], conf: 'low' }; }
  const list = Array.isArray(obj.cats) ? obj.cats : (obj.cat != null ? [obj.cat] : []);
  /* 같은 종류를 두 번 말해도 한 번만 담는다 (예: 상의를 셔츠·셔츠로 두 번) */
  const cats = [...new Set(list.map(matchCat).filter(Boolean))];
  return { cats, conf: cats.length && obj.conf === 'high' ? 'high' : 'low' };
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') return res.status(405).json({ error: 'POST_ONLY' });
  const key = (process.env.ANTHROPIC_API_KEY || '').trim();
  if (!key) return res.status(500).json({ error: 'NO_KEY', msg: 'ANTHROPIC_API_KEY 환경변수가 비어 있습니다' });

  const dataUrl = (req.body && req.body.image) || '';
  const m = /^data:(image\/(?:png|jpeg|webp));base64,(.+)$/.exec(dataUrl);
  if (!m) return res.status(400).json({ error: 'BAD_IMAGE', msg: 'image 는 data:image/... base64 여야 합니다' });
  /* 사진 한 장 상한 4MB — 그보다 크면 화면에서 줄여 보낸다(프로토타입이 캔버스로 줄인다) */
  if (m[2].length > 4 * 1024 * 1024) return res.status(413).json({ error: 'TOO_BIG' });

  let r;
  try {
    r = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify({
        model: 'claude-haiku-4-5-20251001',           // 사진 한 장 분류라 제일 싼 모델로 충분하다
        max_tokens: 128,          // 여러 벌을 낼 수 있어야 해서 64로는 모자란다
        messages: [{ role: 'user', content: [
          { type: 'image', source: { type: 'base64', media_type: m[1], data: m[2] } },
          { type: 'text', text: PROMPT },
        ] }],
      }),
    });
  } catch (e) { return res.status(502).json({ error: 'LLM_FAIL', msg: e.message }); }

  if (!r.ok) return res.status(502).json({ error: 'LLM_FAIL', msg: 'HTTP ' + r.status });
  const j = await r.json();
  const text = (j.content || []).map(c => c.text || '').join('');
  res.status(200).json(parseTag(text));
};

/* ── 자체 점검: node api/tag.js ───────────────────────────────── */
if (require.main === module) {
  const eq = (got, want, what) => {
    if (JSON.stringify(got) !== JSON.stringify(want)) throw new Error(`${what}: ${JSON.stringify(got)} ≠ ${JSON.stringify(want)}`);
  };
  eq(parseTag('{"cats":["반팔티","반바지"],"conf":"high"}'), { cats: ['반팔티', '반바지'], conf: 'high' }, '한 사진에서 여러 벌');
  eq(parseTag('{"cats":["반팔티"],"conf":"high"}'), { cats: ['반팔티'], conf: 'high' }, '한 벌만');
  eq(parseTag('```json\n{"cats":["청바지"],"conf":"low"}\n```'), { cats: ['청바지'], conf: 'low' }, '코드블록에 싸여 와도 읽는다');
  eq(parseTag('{"cats":["반팔 티셔츠","와이드 팬츠"],"conf":"high"}'), { cats: ['반팔티', '와이드팬츠'], conf: 'high' }, '살짝 다르게 써도 살린다');
  eq(parseTag('{"cats":["셔츠","셔츠"],"conf":"high"}'), { cats: ['셔츠'], conf: 'high' }, '같은 종류를 두 번 말해도 한 번');
  eq(parseTag('{"cats":[],"conf":"low"}'), { cats: [], conf: 'low' }, '옷이 아니면 빈 배열');
  eq(parseTag('{"cats":["모자","반바지"],"conf":"high"}'), { cats: ['반바지'], conf: 'high' }, '없는 종류는 빼고 나머지는 살린다');
  eq(parseTag('그냥 말로 답함'), { cats: [], conf: 'low' }, 'JSON이 아니면 빈 배열');
  eq(parseTag('{"cat":"부츠","conf":"high"}'), { cats: ['부츠'], conf: 'high' }, '옛 모양(cat 하나)도 읽는다');
  eq(CATS.length, 21, '카테고리 21종');
  console.log('✓ api/tag.js 점검 통과');
}

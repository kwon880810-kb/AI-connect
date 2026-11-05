// 주요 화면 스크린샷 (e2e.js 실행 후 남은 시험 데이터 사용)
// 사용법: node supabase/tests/screenshots.js <수요자 이메일> <공급자 이메일> [주소] [저장 폴더]
const { chromium } = require("playwright");
const [DEM, SUP] = [process.argv[2], process.argv[3]];
const B = process.argv[4] || "http://localhost:8787";
const OUT = (process.argv[5] || require("path").join(__dirname, "..", "..", "screenshots")) + "/";

(async () => {
  const br = await chromium.launch();
  async function as(email, width, height) {
    const ctx = await br.newContext({ viewport: { width, height }, deviceScaleFactor: 2 });
    const p = await ctx.newPage();
    if (email) {
      await p.goto(B + "/login.html");
      await p.fill("#loginForm [name=email]", email); await p.fill("#loginForm [name=password]", "password1");
      await Promise.all([p.waitForNavigation(), p.click("#loginForm button[type=submit]")]);
      await p.waitForTimeout(800);
    }
    return p;
  }
  const snap = async (p, f, full = true) => { await p.waitForTimeout(700); await p.screenshot({ path: OUT + f, fullPage: full }); };

  let p = await as(null, 1280, 860);
  await p.goto(B + "/index.html"); await p.waitForSelector(".count-card"); await snap(p, "01_홈_PC.png");
  await p.goto(B + "/login.html?signup=1"); await snap(p, "02_회원가입.png", false);
  await p.goto(B + "/directory.html"); await p.waitForSelector(".dir-card"); await snap(p, "03_제작파트너_둘러보기.png");
  const m = await as(null, 390, 844);
  await m.goto(B + "/index.html"); await m.waitForSelector(".count-card"); await snap(m, "04_홈_모바일.png");

  const d = await as(DEM, 1280, 860);
  await d.goto(B + "/request.html");
  await d.waitForSelector('[data-k="title"]');
  await d.fill('[data-k="title"]', "우리 강아지 얼굴 모양 져키"); await d.waitForSelector("#suggest [data-sug]"); await d.click("#suggest [data-sug] >> nth=0");
  await d.click('.opt:has(input[name="opt2"][value="oem"])'); await d.waitForSelector('[data-k="steps.2.src.qty_min"]');
  await d.fill('[data-k="steps.2.src.qty_min"]', "500"); await d.fill('[data-k="steps.2.src.qty_max"]', "1000");
  await d.fill('[data-k="steps.2.src.due_min"]', "28"); await d.fill('[data-k="steps.2.src.due_max"]', "42");
  await snap(d, "05_아이디어_의뢰하기.png");
  await d.goto(B + "/projects.html");
  await d.waitForSelector(".phase-card"); await d.click('.row-card:has-text("강아지 얼굴 져키")'); await d.waitForTimeout(800); await d.click("[data-req] >> nth=0"); await d.waitForSelector(".rp-card"); await snap(d, "06_내_프로젝트_파트너리스트.png");

  const s = await as(SUP, 1280, 860);
  await s.waitForSelector("#feedList [data-rid]"); await s.click("#feedList [data-rid] >> nth=0"); await s.waitForSelector("#respForm");
  await snap(s, "07_제작파트너센터_응답.png");

  const a = await as("admin@test.kr", 1280, 860);
  await a.waitForSelector("#rf"); await a.click('#rf [data-f="all"]'); await a.waitForSelector("#rl .row-card");
  await a.click('#rl .row-card:has-text("강아지 얼굴 져키") >> nth=0'); await a.waitForSelector("text=응답 순위"); await snap(a, "08_관리자_의뢰.png");
  await br.close();
})();

// 화면 전체 흐름 시험: 출시 프로젝트 (로컬 가짜 Supabase + Playwright)
// 사용법: node supabase/tests/e2e.js [http://localhost:8787] [스크린샷 폴더]
const { chromium } = require("playwright");
const fs = require("fs");
const path = require("path");
const BASE = process.argv[2] || "http://localhost:8787";
const SHOTS = process.argv[3] || "/tmp/e2e-shots";
fs.mkdirSync(SHOTS, { recursive: true });

let n = 0, failed = 0;
const ok = (cond, msg) => { n++; if (cond) console.log("PASS  " + msg); else { failed++; console.log("FAIL  " + msg); } };
const stamp = Date.now().toString().slice(-6);
function bizNo(prefix9) {
  const d = prefix9.split("").map(Number), w = [1, 3, 7, 1, 3, 7, 1, 3, 5];
  const s = d.reduce((a, x, i) => a + x * w[i], 0) + Math.floor((d[8] * 5) / 10);
  return prefix9 + ((10 - (s % 10)) % 10);
}

(async () => {
  const browser = await chromium.launch();
  const errors = [];
  async function user(name, width = 1280) {
    const ctx = await browser.newContext({ viewport: { width, height: 900 } });
    const page = await ctx.newPage();
    page.on("pageerror", (e) => errors.push(`[${name}] ${e.message}`));
    page.on("dialog", (d) => d.accept());
    return page;
  }
  const shot = (p, f) => p.screenshot({ path: path.join(SHOTS, f), fullPage: true });
  const text = async (p, sel) => (await p.textContent(sel)) || "";
  const pick = (p, name, v) => p.click(`.opt:has(input[name="${name}"][value="${v}"])`);

  async function signup(p, role, email, name, company, phone) {
    await p.goto(`${BASE}/login.html?signup=1${role === "supplier" ? "&role=supplier" : ""}`);
    await p.fill("#signupForm [name=name]", name);
    await p.fill("#signupForm [name=company]", company);
    await p.fill("#signupForm [name=phone]", phone);
    await p.fill("#signupForm [name=email]", email);
    await p.fill("#signupForm [name=password]", "password1");
    await p.check("#signupForm [name=agree]");
    await Promise.all([p.waitForNavigation(), p.click("#signupForm button[type=submit]")]);
  }
  async function login(p, email) {
    await p.goto(`${BASE}/login.html`);
    await p.fill("#loginForm [name=email]", email);
    await p.fill("#loginForm [name=password]", "password1");
    await Promise.all([p.waitForNavigation(), p.click("#loginForm button[type=submit]")]);
  }
  async function adminOpen(adm, title) {
    await adm.goto(`${BASE}/admin.html`);
    await adm.waitForSelector("#rf");
    await adm.click('#rf [data-f="all"]');
    await adm.waitForSelector(`#rl .row-card:has-text("${title}")`);
    await adm.click(`#rl .row-card:has-text("${title}") >> nth=0`);
    await adm.waitForTimeout(600);
  }

  // ---------- 홈 ----------
  const anon = await user("anon", 390);
  await anon.goto(`${BASE}/index.html`);
  await anon.waitForSelector(".count-card");
  ok((await anon.$$(".count-card")).length >= 8, "홈: 분야별 진행 건수 표시");
  ok((await text(anon, ".fees")).includes("9,900") && (await text(anon, ".fees")).includes("50,000"), "홈: 접수비·착수금·이어하기 요금 표시");
  ok(await anon.isVisible("#couponNote"), "홈: 신규 가입 쿠폰 안내");
  ok(await anon.evaluate(() => document.documentElement.scrollWidth <= 390), "홈: 모바일 가로 넘침 없음");

  // ---------- 공급자 2곳 ----------
  const supA = await user("supA"), supB = await user("supB");
  async function supplierSetup(p, email, name, company, biz, sido, minor) {
    await signup(p, "supplier", email, name, company, "010-3333-" + sido.length + "333");
    await p.waitForSelector("#supForm");
    await p.fill("#supForm [name=biz_no]", biz);
    await p.selectOption("#supForm [name=region_sido]", sido);
    await p.fill("#supForm [name=contact_phone]", "010-3333-" + sido.length + "333");
    await p.fill("#supForm [name=intro]", sido + " 펫 간식 전문");
    await p.check('#supForm input[name=cat][value="2"]');
    if (minor) await p.check(`#supForm input[name=cat][value="${minor}"]`);
    await p.click("#supForm button[type=submit]");
    await p.waitForSelector("text=사업자 확인 중입니다");
  }
  await supplierSetup(supA, `a${stamp}@sup.kr`, "김실장", "가나펫푸드", bizNo(`22${stamp.slice(0, 6)}1`), "경기", 201);
  await supplierSetup(supB, `b${stamp}@sup.kr`, "이팀장", "다라푸드", bizNo(`33${stamp.slice(0, 6)}2`), "충북");
  ok(true, "공급자 2곳 가입·사업자번호 등록");

  const adm = await user("admin");
  await login(adm, "admin@test.kr");
  await adm.waitForSelector("#rf");
  await adm.click('#tabs [data-t="sup"]');
  await adm.waitForSelector("[data-verify]");
  for (let i = 0; i < 2; i++) { await adm.click("[data-verify] >> nth=0"); await adm.waitForTimeout(400); }
  await adm.waitForFunction(() => document.querySelectorAll("[data-verify]").length === 0);
  ok(true, "관리자: 사업자 확인 완료");

  // ---------- 수요자: 1차 ----------
  const dem = await user("demander");
  await signup(dem, "demander", `d${stamp}@dem.kr`, "홍길동", "멍멍상회", "010-9" + stamp.slice(0, 3) + "-" + stamp.slice(3) + "1");
  await dem.goto(`${BASE}/request.html`);
  await dem.waitForSelector('[data-k="title"]');
  ok((await dem.$$(".phase-tab")).length === 5, "의뢰서: 1차·2차·2-1차·3차·4차 탭");
  await dem.fill('[data-k="title"]', "강아지 얼굴 져키");
  await dem.waitForSelector("#suggest [data-sug]");
  await dem.click("#suggest [data-sug] >> nth=0");
  await dem.waitForSelector(".note:has-text('사료제조업')");
  ok(true, "1단계: '져키'로 반려동물 › 간식 추천, 헷갈리기 쉬운 점 안내");
  await pick(dem, "ideaMode", "ai");
  await dem.waitForSelector(".ai-tool");
  ok((await dem.$$(".ai-tool")).length === 8 && (await text(dem, "#steps")).includes("업데이트 예정") && (await text(dem, "#steps")).includes("저작권"), "1단계: AI 도구 링크 8개, 업데이트 예정, 저작권 안내");
  await dem.click('.opt:has(input[name="ideaMode"][value="ai"]) .qmark');
  ok(await dem.isVisible(".help-pop"), "선택지 (?) 설명 말풍선");
  await dem.fill('[data-k="idea_desc"]', "우리 강아지 얼굴 모양 닭가슴살 져키, 50g 파우치");
  const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
  await dem.setInputFiles('[data-fadd="1"]', [{ name: "concept.png", mimeType: "image/png", buffer: png }]);
  await dem.waitForSelector('[data-fstep="1"]');
  await dem.selectOption('[data-fstep="1"]', "all");
  await pick(dem, "opt2", "oem");
  await dem.waitForSelector('[data-k="steps.2.src.qty_min"]');
  ok(await dem.isDisabled('input[name="opt2"][value="same"]'), "2단계: 기존 공장 재요청은 연결된 파트너가 생긴 뒤에만");
  await dem.fill('[data-k="steps.2.src.qty_min"]', "500"); await dem.fill('[data-k="steps.2.src.qty_max"]', "1000");
  await dem.fill('[data-k="steps.2.src.price_min"]', "600"); await dem.fill('[data-k="steps.2.src.price_max"]', "800");
  await dem.fill('[data-k="steps.2.src.due_min"]', "28"); await dem.fill('[data-k="steps.2.src.due_max"]', "42");
  await dem.selectOption('[data-k="steps.2.src.sido"]', "경기");
  await dem.check('[data-item="2"]:near(:text("사료제조업 등록 서류 확인"))');
  await dem.setInputFiles('[data-fadd="2"]', [{ name: "spec.pdf", mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4 test") }]);
  await dem.waitForSelector("#sumBox .sum-total");
  const sum1 = await text(dem, "#sumBox");
  ok(sum1.includes("쿠폰") && sum1.includes("0원") && sum1.includes("55,000"), "요약: 쿠폰으로 접수비 0원, 리스트 받을 때 착수금 55,000원");
  await dem.waitForSelector('#saveState:has-text("자동 저장됨")', { timeout: 8000 });
  ok(dem.url().includes("project="), "자동 저장: 프로젝트 생성, 주소에 프로젝트 번호");
  await shot(dem, "01_phase1.png");
  await dem.reload();
  await dem.waitForSelector('[data-k="steps.2.src.qty_min"]');
  ok((await dem.inputValue('[data-k="title"]')) === "강아지 얼굴 져키" && (await dem.inputValue('[data-k="steps.2.src.qty_min"]')) === "500", "새로고침해도 작성 내용 유지 (임시저장)");
  // 파일은 메모리에만 있어서 새로고침 후 다시 첨부
  await dem.setInputFiles('[data-fadd="1"]', [{ name: "concept.png", mimeType: "image/png", buffer: png }]);
  await dem.waitForSelector('[data-fstep="1"]');
  await dem.selectOption('[data-fstep="1"]', "all");
  await dem.check("#agree");
  await dem.click("#submitBtn");
  await dem.waitForSelector("text=의뢰가 접수되었습니다");
  const done1 = await text(dem, "main");
  ok(/R\d{6}-\d{4}/.test(done1) && done1.includes("착수금 55,000원"), "1차 접수: 의뢰번호, 첫 의뢰 착수금 안내");

  // ---------- 관리자: 공개 승인 (0원) ----------
  await adminOpen(adm, "강아지 얼굴 져키");
  await adm.waitForSelector("#confirmPay");
  ok((await text(adm, "#rd")).includes("공개 승인 (0원)") && (await text(adm, "#rd")).includes("쿠폰"), "관리자: 쿠폰 의뢰는 0원 공개 승인, 전화 확인 안내");
  await adm.click("#confirmPay");
  await adm.waitForSelector("text=응답 순위");

  // ---------- 공급자 응답 ----------
  await supA.goto(`${BASE}/supplier.html`);
  await supA.waitForSelector("#feedList [data-rid]");
  ok((await text(supA, "#feedList")).includes("1차 · 제품 생산"), "공급자: 의뢰에 차수·단계 표시");
  ok(!!(await supA.waitForSelector("#feedList img.thumb", { timeout: 5000 }).catch(() => null)), "공급자: 모두 공개 컨셉 이미지 썸네일");
  await supA.click("#feedList [data-rid]");
  await supA.waitForSelector("#respForm");
  const det = await text(supA, "#feedDetail");
  ok(det.includes("출시 프로젝트 요약") && !det.includes("멍멍상회") && !det.includes("홍길동"), "공급자: 프로젝트 요약은 보이고 의뢰자 정보는 가림");
  await supA.fill("#respForm [name=qty_min]", "500"); await supA.fill("#respForm [name=qty_max]", "3000");
  await supA.fill("#respForm [name=price_min]", "650"); await supA.fill("#respForm [name=price_max]", "750");
  await supA.fill("#respForm [name=due_min]", "30"); await supA.fill("#respForm [name=due_max]", "40");
  for (const seg of await supA.$$("#respForm .seg")) await (await seg.$("[data-a=O]")).click();
  await supA.fill("#respForm [name=memo]", "원료 직접 수급");
  await supA.check("#respForm [name=pledge]");
  await supA.click("#respForm button[type=submit]");
  await supA.waitForSelector("#respForm .sbadge.s-blue");
  await supB.goto(`${BASE}/supplier.html`);
  await supB.waitForSelector("#feedList [data-rid]");
  await supB.click("#feedList [data-rid]");
  await supB.waitForSelector("#respForm");
  await supB.fill("#respForm [name=qty_min]", "3000"); await supB.fill("#respForm [name=price_min]", "500"); await supB.fill("#respForm [name=due_min]", "30");
  for (const seg of await supB.$$("#respForm .seg")) await (await seg.$("[data-a=O]")).click();
  await supB.check("#respForm [name=pledge]");
  await supB.click("#respForm button[type=submit]");
  await supB.waitForSelector("#respForm .sbadge.s-blue");
  ok(true, "공급자 2곳 응답");

  // ---------- 선정 → 착수금 대기 → 착수금 확인 ----------
  await adminOpen(adm, "강아지 얼굴 져키");
  await adm.waitForSelector("[data-sel]");
  await adm.check("[data-sel] >> nth=0");
  await adm.click("#deliverBtn");
  await adm.waitForSelector("#confirmDeposit");
  ok(true, "관리자: 선정 → 첫 의뢰라 착수금 입금 대기");
  await dem.goto(`${BASE}/projects.html`);
  await dem.waitForSelector("[data-req]");
  await dem.click("[data-req] >> nth=0");
  await dem.waitForSelector(".rp-locked");
  const pv = await text(dem, "#detail");
  ok(pv.includes("파트너 A") && pv.includes("55,000") && !pv.includes("가나펫푸드"), "수요자: 착수금 전에는 '파트너 A'로 체크 결과만, 업체명 가림");
  await shot(dem, "02_awaiting_deposit.png");
  await adm.click("#confirmDeposit");
  await adm.waitForSelector("#confirmReq");
  await dem.reload();
  await dem.waitForSelector("[data-req]");
  await dem.click("[data-req] >> nth=0");
  await dem.waitForSelector(".rp-contact");
  const list = await text(dem, "#detail");
  ok(list.includes("가나펫푸드") && list.includes("010-3333"), "착수금 확인 후 업체명·연락처 공개");

  // ---------- 이의신청 → 의견서 → 판정 ----------
  await dem.click("[data-dispute]");
  await dem.fill("textarea[name=claim]", "최소 수량 3,000개부터라고 함");
  await dem.click("form >> text=이의신청");
  await dem.waitForSelector("#toast.show");
  await adm.goto(`${BASE}/admin.html`);
  await adm.waitForSelector("#rf");
  await adm.click('#tabs [data-t="dis"]');
  await adm.waitForSelector("[data-ask]");
  await adm.click("[data-ask]");
  await adm.waitForSelector("[data-decide]");
  await supA.goto(`${BASE}/supplier.html`);
  await supA.waitForSelector("#feedList");
  await supA.click('#tabs [data-t="opinion"]');
  await supA.waitForSelector("[data-op]");
  await supA.fill("[data-op] textarea", "500개부터 가능, 안내 착오");
  await supA.click("[data-op] button");
  await supA.waitForSelector("#toast.show");
  await adm.click('#tabs [data-t="dis"]');
  await adm.waitForSelector("text=공급자 의견");
  await adm.selectOption("[data-decide] [name=status]", "accepted");
  await adm.selectOption("[data-decide] [name=remedy]", "replace");
  await adm.selectOption("[data-decide] [name=fault]", "1");
  await adm.fill("[data-decide] [name=note]", "공급자 안내 착오 인정");
  await adm.click("[data-decide] button");
  await adm.waitForSelector("text=판정: 공급자 안내 착오");
  await supA.click('#tabs [data-t="score"]');
  await supA.waitForSelector(".stats");
  ok((await text(supA, ".stats")).includes("90"), "이의 인정·공급자 책임 → 신뢰도 90점");

  // ---------- 2차: 기존 파트너에게 포장재 문의 (무료) ----------
  const projectUrl = dem.url();
  await dem.goto(`${BASE}/projects.html`);
  await dem.waitForSelector(".phase-card");
  await dem.click('a:has-text("2차 작성하기")');
  await dem.waitForSelector('[data-panel="3"]');
  await pick(dem, "opt3", "pouch");
  await pick(dem, "opt4", "ai");
  await dem.click('.opt:has(input[name="opt4"][value="ai"]) .qmark');
  ok((await text(dem, ".help-pop")).includes("ChatGPT"), "4단계: AI 도구 활용 (?)에 예시 도구");
  await pick(dem, "opt5", "factory");
  await dem.waitForSelector("[data-partner]");
  await dem.check("[data-partner] >> nth=0");
  await dem.fill('[data-k="steps.5.desc"]', "파우치 포장재도 함께 가능한지 문의");
  const sum2 = await text(dem, "#sumBox");
  ok(sum2.includes("기존 파트너 문의") && sum2.includes("무료") && !sum2.includes("착수금"), "2차: 기존 파트너 문의는 무료, 착수금 없음");
  await shot(dem, "03_phase2.png");
  await dem.check("#agree");
  await dem.click("#submitBtn");
  await dem.waitForSelector("text=의뢰가 접수되었습니다");
  ok((await text(dem, "main")).includes("기존 파트너 문의"), "2차 접수 완료");
  await adminOpen(adm, "포장재 제작 문의");
  await adm.waitForSelector("#confirmPay");
  await adm.click("#confirmPay");
  await adm.waitForTimeout(600);
  await supA.goto(`${BASE}/supplier.html`);
  await supA.waitForSelector("#feedList");
  ok((await text(supA, "#feedList")).includes("기존 거래 파트너 문의"), "공급자 A: 기존 거래 파트너 문의로 받음");
  await supB.goto(`${BASE}/supplier.html`);
  await supB.waitForSelector("#feedList");
  ok(!(await text(supB, "#feedList")).includes("포장재 제작 문의"), "공급자 B는 그 문의를 못 봄");

  // ---------- 2-1차 인증 안내, 3차 판매 채널 ----------
  await dem.goto(`${BASE}/projects.html`);
  await dem.waitForSelector(".phase-card");
  await dem.click('a:has-text("2-1차 작성하기")');
  await dem.waitForSelector('[data-panel="6"]');
  ok((await text(dem, "#steps")).includes("사료 성분 등록"), "6단계: 반려동물 간식에 맞는 인증 안내");
  await dem.click('.phase-tab[data-phase="3"]');
  await dem.waitForSelector("[data-channel]");
  await pick(dem, "opt7", "self");
  await dem.check('[data-channel][value="네이버 스마트스토어"]');
  await dem.check('[data-channel][value="와디즈"]');
  await dem.fill('[data-k="etc.0"]', "동네 펫샵");
  ok((await dem.$$("[data-channel]")).length >= 25 && (await dem.$$(".etc-in")).length === 10, "9단계: 판매 채널 체크박스와 기타1~10");
  await dem.check("#agree");
  await dem.click("#submitBtn");
  await dem.waitForSelector("text=계획을 저장했습니다");
  await dem.goto(`${BASE}/projects.html`);
  await dem.waitForSelector(".phase-card");
  const pj = await text(dem, "#detail");
  ok(pj.includes("와디즈") && pj.includes("동네 펫샵") && pj.includes("3차"), "내 프로젝트: 판매 채널과 차수별 진행 표시");
  await shot(dem, "04_project.png");
  await dem.click('[data-act="close"]');
  await dem.waitForSelector('[data-act="reopen"]');
  await dem.click('[data-act="reopen"]');
  await dem.waitForSelector('[data-act="close"]');
  ok(true, "여기서 마치기 → 다시 이어가기");

  // ---------- 둘러보기 → 지정 의뢰 (새 프로젝트) ----------
  await dem.goto(`${BASE}/directory.html`);
  await dem.waitForSelector(".dir-card");
  ok(!(await text(dem, "#grid")).includes("가나펫푸드"), "둘러보기: 업체명 가림");
  for (const c of await dem.$$(".dir-card")) if ((await c.textContent()).includes("충북")) await (await c.$("[data-pick]")).click();
  await dem.click("#directBtn");
  await dem.waitForSelector('[data-k="title"]');
  await dem.fill('[data-k="title"]', "고양이 스크래쳐");
  await dem.selectOption('[data-k="product_major"]', "2");
  await pick(dem, "opt2", "oem");
  await dem.waitForSelector("#clearDirect");
  await dem.fill('[data-k="steps.2.src.qty_min"]', "300"); await dem.fill('[data-k="steps.2.src.due_min"]', "20");
  const sum3 = await text(dem, "#sumBox");
  ok(sum3.includes("9,900") && sum3.includes("50,000"), "지정 의뢰 새 프로젝트: 접수비 9,900원(쿠폰 사용함) + 착수금 50,000원, 할인 없음");
  await dem.check("#agree");
  await dem.click("#submitBtn");
  await dem.waitForSelector("text=의뢰가 접수되었습니다");
  await adminOpen(adm, "고양이 스크래쳐");
  await adm.waitForSelector("#confirmPay");
  await adm.click("#confirmPay");
  await adm.waitForSelector("text=응답 대기 1곳");
  await supB.goto(`${BASE}/supplier.html`);
  await supB.waitForSelector("#feedList");
  ok((await text(supB, "#feedList")).includes("지정 의뢰"), "지정된 공급자 B가 지정 의뢰를 봄");

  await supA.goto(`${BASE}/admin.html`);
  await supA.waitForSelector("text=이 화면을 볼 수 없습니다");
  ok(true, "공급자는 관리자 화면에 못 들어감");

  console.log(errors.length ? "PAGE ERRORS:\n" + errors.join("\n") : "페이지 오류 없음");
  console.log(`\n${n - failed}/${n} 통과`);
  await browser.close();
  process.exit(failed || errors.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });

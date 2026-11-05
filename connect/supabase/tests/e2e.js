// 화면 전체 흐름 시험 (로컬 가짜 Supabase + Playwright)
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

// 국세청 체크섬이 맞는 사업자번호 만들기
function bizNo(prefix9) {
  const d = prefix9.split("").map(Number), w = [1, 3, 7, 1, 3, 7, 1, 3, 5];
  let s = d.reduce((a, x, i) => a + x * w[i], 0) + Math.floor((d[8] * 5) / 10);
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
  const waitToast = (p) => p.waitForSelector("#toast.show", { timeout: 5000 }).catch(() => null);

  async function signup(p, role, email, name, company) {
    await p.goto(`${BASE}/login.html?signup=1${role === "supplier" ? "&role=supplier" : ""}`);
    await p.fill("#signupForm [name=name]", name);
    await p.fill("#signupForm [name=company]", company);
    await p.fill("#signupForm [name=phone]", "010-1234-5678");
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

  // ---------- 비회원 홈 ----------
  const anon = await user("anon", 390);
  await anon.goto(`${BASE}/index.html`);
  await anon.waitForSelector(".count-card");
  ok((await anon.$$(".count-card")).length === 8, "홈: 분야별 진행 건수 8개 표시");
  ok((await anon.textContent(".fees")).includes("50,000"), "홈: 요금표가 DB 값으로 표시");
  ok(await anon.evaluate(() => document.documentElement.scrollWidth <= 390), "홈: 모바일 가로 넘침 없음");
  await shot(anon, "01_home_mobile.png");

  // ---------- 공급자 2곳 가입 ----------
  const supA = await user("supA"), supB = await user("supB");
  await signup(supA, "supplier", `a${stamp}@sup.kr`, "김실장", "가나펫푸드");
  ok(supA.url().includes("supplier.html"), "공급자 가입 후 공급자 센터로 이동");
  await supA.waitForSelector("#supForm");
  async function fillSupplier(p, biz, sido, extraMinor) {
    await p.fill("#supForm [name=biz_no]", biz);
    await p.selectOption("#supForm [name=region_sido]", sido);
    await p.fill("#supForm [name=contact_phone]", "010-3333-" + sido.length + "333");
    await p.fill("#supForm [name=intro]", sido + " 펫 간식 전문, 소량 가능");
    await p.check('#supForm input[name=cat][value="2"]');
    if (extraMinor) await p.check(`#supForm input[name=cat][value="${extraMinor}"]`);
    await p.check("#supForm input[name=proc] >> nth=0");
    await p.click("#supForm button[type=submit]");
  }
  await supA.fill("#supForm [name=biz_no]", "1234567890");
  await supA.selectOption("#supForm [name=region_sido]", "경기");
  await supA.fill("#supForm [name=contact_phone]", "010-3333-3333");
  await supA.check('#supForm input[name=cat][value="2"]');
  await supA.click("#supForm button[type=submit]");
  ok((await supA.textContent("#supForm .form-msg")).includes("올바르지"), "잘못된 사업자번호는 거절");
  await fillSupplier(supA, bizNo(`22${stamp.slice(0, 6)}1`), "경기", 201);
  await supA.waitForSelector("text=사업자 확인 중입니다");
  ok(true, "공급자 A 등록 → 사업자 확인 대기");
  await shot(supA, "02_supplier_pending.png");
  await signup(supB, "supplier", `b${stamp}@sup.kr`, "이팀장", "다라푸드");
  await supB.waitForSelector("#supForm");
  await fillSupplier(supB, bizNo(`33${stamp.slice(0, 6)}2`), "충북");
  await supB.waitForSelector("text=사업자 확인 중입니다");

  // ---------- 관리자: 사업자 확인 ----------
  const adm = await user("admin");
  await login(adm, "admin@test.kr");
  ok(adm.url().includes("admin.html"), "관리자 로그인 → 관리자 화면");
  await adm.waitForSelector("#rf");
  await adm.click('#tabs [data-t="sup"]');
  await adm.waitForSelector("[data-verify]");
  for (let i = 0; i < 2; i++) { await adm.click("[data-verify] >> nth=0"); await adm.waitForTimeout(400); }
  await adm.waitForFunction(() => document.querySelectorAll("[data-verify]").length === 0);
  ok(true, "관리자: 공급자 2곳 사업자 확인 완료");
  await shot(adm, "03_admin_suppliers.png");

  // ---------- 수요자: 의뢰 ----------
  const dem = await user("demander");
  await signup(dem, "demander", `d${stamp}@dem.kr`, "홍길동", "멍멍상회");
  await dem.goto(`${BASE}/request.html`);
  await dem.waitForSelector("#reqForm");
  await dem.fill("#reqForm [name=title]", "강아지 져키 파우치");
  await dem.waitForSelector("#suggest [data-id]");
  ok((await dem.textContent("#suggest")).includes("간식"), "요청서: '져키'로 반려동물 › 간식 추천");
  await dem.click("#suggest [data-id] >> nth=0");
  ok(!(await dem.isHidden("#confusion")), "요청서: 헷갈리기 쉬운 점 안내 표시");
  await dem.fill("#reqForm [name=qty_min]", "500"); await dem.fill("#reqForm [name=qty_max]", "1000");
  await dem.fill("#reqForm [name=price_min]", "600"); await dem.fill("#reqForm [name=price_max]", "800");
  await dem.fill("#reqForm [name=due_min]", "28"); await dem.fill("#reqForm [name=due_max]", "42");
  await dem.selectOption("#reqForm [name=deliver_sido]", "경기");
  await dem.check("#condList .check-row:has(.tag-rec) input");
  await dem.fill("#reqForm [name=supplier_count]", "2");
  await dem.fill("#reqForm [name=description]", "닭가슴살 져키 50g, 지퍼 파우치");
  const png = Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==", "base64");
  await dem.setInputFiles("#fileInput", [{ name: "ref.png", mimeType: "image/png", buffer: png }, { name: "design.pdf", mimeType: "application/pdf", buffer: Buffer.from("%PDF-1.4 test") }]);
  ok((await dem.$$("#fileList .file-row")).length === 2, "요청서: 파일 2개 첨부");
  ok((await dem.inputValue("#fileList select >> nth=0")) === "all" && (await dem.inputValue("#fileList select >> nth=1")) === "selected", "요청서: 첫 이미지는 모두 공개, 나머지는 선정사 공개 기본값");
  ok((await dem.textContent("#sum")).includes("55,000"), "요청서: 금액 55,000원 (착수금 + 서류 확인 1개)");
  await dem.check("#reqForm [name=agree]");
  await shot(dem, "04_request_form.png");
  await dem.click("#submitBtn");
  await dem.waitForSelector("text=의뢰가 접수되었습니다");
  const doneText = await dem.textContent("main");
  ok(/R\d{6}-\d{4}/.test(doneText) && doneText.includes("55,000"), "접수 완료: 의뢰번호와 서버 계산 금액 표시");
  await shot(dem, "05_request_done.png");

  // ---------- 관리자: 입금 확인 ----------
  await adm.click('#tabs [data-t="req"]');
  await adm.waitForSelector("#rl .row-card");
  await adm.click("#rl .row-card >> nth=0");
  await adm.waitForSelector("#confirmPay");
  await adm.click("#confirmPay");
  await adm.waitForSelector("text=응답 순위");
  ok(true, "관리자: 입금 확인 → 공급자에게 공개");

  // ---------- 공급자 A 응답 ----------
  await supA.goto(`${BASE}/supplier.html`);
  await supA.waitForSelector("#feedList [data-rid]");
  ok((await supA.$$("#feedList [data-rid]")).length === 1, "공급자 A: 의뢰 목록에 1건");
  ok(!!(await supA.waitForSelector("#feedList img.thumb", { timeout: 5000 }).catch(() => null)), "공급자 A: 썸네일 이미지 표시");
  await supA.click("#feedList [data-rid]");
  await supA.waitForSelector("#respForm");
  ok(!(await supA.textContent("#feedDetail")).includes("멍멍상회") && !(await supA.textContent("#feedDetail")).includes("홍길동"), "공급자 A: 수요자 회사명·이름이 보이지 않음");
  ok((await supA.$$("#feedDetail [data-file]")).length === 1, "공급자 A: 선정 전에는 모두 공개 파일 1개만");
  await supA.fill("#respForm [name=qty_min]", "500"); await supA.fill("#respForm [name=qty_max]", "3000");
  await supA.fill("#respForm [name=price_min]", "650"); await supA.fill("#respForm [name=price_max]", "750");
  await supA.fill("#respForm [name=due_min]", "30"); await supA.fill("#respForm [name=due_max]", "40");
  ok((await supA.textContent("#rangePreview")).split("● 가능").length - 1 === 3, "공급자 A: 범위 비교 미리보기 3개 모두 ●");
  for (const seg of await supA.$$("#respForm .seg")) await (await seg.$("[data-a=O]")).click();
  await supA.fill("#respForm [name=sample_cost]", "5만 원, 1주");
  await supA.fill("#respForm [name=memo]", "원료 직접 수급");
  await supA.check("#respForm [name=pledge]");
  await shot(supA, "06_supplier_respond.png");
  await supA.click("#respForm button[type=submit]");
  await supA.waitForSelector("#respForm .sbadge.s-blue");
  ok(true, "공급자 A: 응답 제출");

  // ---------- 공급자 B: 수량이 맞지 않는 응답 ----------
  await supB.goto(`${BASE}/supplier.html`);
  await supB.waitForSelector("#feedList [data-rid]");
  await supB.click("#feedList [data-rid]");
  await supB.waitForSelector("#respForm");
  await supB.fill("#respForm [name=qty_min]", "3000"); await supB.fill("#respForm [name=qty_max]", "5000");
  await supB.fill("#respForm [name=price_min]", "500"); await supB.fill("#respForm [name=due_min]", "30");
  ok((await supB.textContent("#rangePreview")).includes("✕ 불가"), "공급자 B: 수량 ±20% 밖이면 ✕ 미리보기");
  for (const seg of await supB.$$("#respForm .seg")) await (await seg.$("[data-a=P]")).click();
  await supB.check("#respForm [name=pledge]");
  await supB.click("#respForm button[type=submit]");
  ok((await supB.textContent("#respForm .form-msg")).includes("조건"), "공급자 B: ▲ 조건부인데 메모 없으면 거절");
  for (const nb of await supB.$$("#respForm [data-note]")) await nb.fill("수량 협의 필요");
  await supB.click("#respForm button[type=submit]");
  await supB.waitForSelector("#respForm .sbadge.s-blue");

  // ---------- 수요자: 응답 현황 ----------
  await dem.goto(`${BASE}/projects.html`);
  await dem.waitForSelector(".stats");
  const st = await dem.textContent(".stats");
  ok(st.includes("2") && st.includes("100%"), "수요자: 열람 2 / 응답 2 · 응답률 100% 표시");
  ok(!(await dem.textContent("#detail")).includes("가나펫푸드"), "수요자: 선정 전에는 공급자 이름이 보이지 않음");

  // ---------- 관리자: 순위·선정·전달 ----------
  await adm.goto(`${BASE}/admin.html`);
  await adm.waitForSelector("#rf");
  await adm.waitForSelector("#rl .row-card");
  await adm.click("#rl .row-card >> nth=0");
  await adm.waitForSelector("[data-sel]");
  const rows = await adm.$$eval("table.data tr", (trs) => trs.slice(1).map((t) => t.textContent));
  ok(rows.length === 2 && rows[0].includes("가나펫푸드"), "관리자: 순위 1위는 조건이 맞는 공급자 A");
  await shot(adm, "07_admin_rank.png");
  await adm.check("[data-sel] >> nth=0");
  await adm.click("#deliverBtn");
  await adm.waitForSelector("#confirmReq");
  ok(true, "관리자: 1곳 선정 후 리스트 전달 (요청 2곳 → 부족분 확인 창)");

  // ---------- 수요자: 리스트·이의신청 ----------
  await dem.goto(`${BASE}/projects.html`);
  await dem.waitForSelector(".rp-card");
  const list = await dem.textContent("#detail");
  ok(list.includes("가나펫푸드") && list.includes("010-3333"), "수요자: 선정된 공급자 이름·연락처 공개");
  ok(!list.includes("다라푸드"), "수요자: 미선정 공급자는 보이지 않음");
  await shot(dem, "08_demander_list.png");
  await dem.click("[data-dispute]");
  await dem.fill("textarea[name=claim]", "11/6 통화, 최소 수량 3,000개부터라고 함");
  await dem.click("text=이의신청 >> nth=-1");
  await waitToast(dem);
  await dem.waitForSelector("text=이의 처리 중");
  ok(true, "수요자: 이의신청 → 이의 처리 중");

  // ---------- 공급자 A: 선정 후 파일 ----------
  await supA.goto(`${BASE}/supplier.html`);
  await supA.waitForSelector("#feedList");
  await supA.click('#tabs [data-t="mine"]');
  ok((await supA.textContent("#tabBody")).includes("선정됨"), "공급자 A: 내 응답에 선정됨");

  // ---------- 관리자: 의견서 요청 → 공급자 의견 → 판정 ----------
  await adm.click('#tabs [data-t="dis"]');
  await adm.waitForSelector("[data-ask]");
  await adm.click("[data-ask]");
  await adm.waitForSelector("[data-decide]");
  await supA.click('#tabs [data-t="opinion"]');
  await supA.waitForSelector("[data-op]");
  await supA.fill("[data-op] textarea", "500개부터 가능, 3,000개는 다른 제품 기준으로 잘못 안내함");
  await supA.click("[data-op] button");
  await waitToast(supA);
  await adm.click('#tabs [data-t="dis"]');
  await adm.waitForSelector("text=공급자 의견");
  await adm.selectOption("[data-decide] [name=status]", "accepted");
  await adm.selectOption("[data-decide] [name=remedy]", "replace");
  await adm.selectOption("[data-decide] [name=fault]", "1");
  await adm.fill("[data-decide] [name=note]", "공급자 안내 착오 인정, 대체 업체 제공");
  await adm.click("[data-decide] button");
  await adm.waitForSelector("text=판정: 공급자 안내 착오");
  ok(true, "관리자: 의견서 확인 후 인정·대체 업체·공급자 책임 판정");
  await supA.click('#tabs [data-t="score"]');
  await supA.waitForSelector(".stats");
  ok((await supA.textContent(".stats")).includes("90"), "공급자 A: 신뢰도 90점 (필수 불일치 -10)");
  await shot(supA, "09_supplier_score.png");
  await supB.goto(`${BASE}/supplier.html`);
  await supB.waitForSelector("#feedList");
  await supB.click('#tabs [data-t="score"]');
  await supB.waitForSelector(".stats");
  ok((await supB.textContent(".stats")).includes("100"), "공급자 B: 신뢰도 100점 (다른 공급자 차감과 무관)");

  // ---------- 둘러보기 → 지정 의뢰 ----------
  await anon.goto(`${BASE}/directory.html`);
  await anon.waitForSelector(".dir-card");
  const dir = await anon.textContent("#grid");
  ok((await anon.$$(".dir-card")).length === 2 && !dir.includes("가나펫푸드") && !dir.includes("010-3333"), "둘러보기: 2곳, 업체명·연락처 가림");
  await shot(anon, "10_directory_mobile.png");
  await dem.goto(`${BASE}/directory.html`);
  await dem.waitForSelector(".dir-card");
  const cards = await dem.$$(".dir-card");
  for (const c of cards) if ((await c.textContent()).includes("충북")) await (await c.$("[data-pick]")).click();
  await dem.click("#directBtn");
  await dem.waitForSelector("#directBox:not([hidden])");
  await dem.fill("#reqForm [name=title]", "고양이 스크래쳐");
  await dem.selectOption("#reqForm [name=major]", "2");
  await dem.fill("#reqForm [name=qty_min]", "300"); await dem.fill("#reqForm [name=due_min]", "20");
  ok((await dem.textContent("#sum")).includes("25,000"), "지정 의뢰: 착수금 절반 25,000원");
  await dem.check("#reqForm [name=agree]");
  await dem.click("#submitBtn");
  await dem.waitForSelector("text=의뢰가 접수되었습니다");
  await adm.click('#tabs [data-t="req"]');
  await adm.waitForSelector("#rl .row-card");
  await adm.click("#rl .row-card >> nth=0");
  await adm.waitForSelector("#confirmPay");
  await adm.click("#confirmPay");
  await adm.waitForSelector("text=응답 대기 1곳");
  ok(true, "지정 의뢰: 입금 확인 시 지정 공급사 응답 대기 생성");
  await supB.goto(`${BASE}/supplier.html`);
  await supB.waitForSelector("#feedList");
  ok((await supB.textContent("#feedList")).includes("지정 의뢰"), "지정된 공급자 B는 지정 의뢰를 봄");
  await supA.goto(`${BASE}/supplier.html`);
  await supA.waitForSelector("#feedList");
  ok(!(await supA.textContent("#feedList")).includes("고양이 스크래쳐"), "지정되지 않은 공급자 A는 못 봄");

  // ---------- 권한 없는 화면 ----------
  await supA.goto(`${BASE}/admin.html`);
  await supA.waitForSelector("text=이 화면을 볼 수 없습니다");
  ok(true, "공급자는 관리자 화면에 들어갈 수 없음");

  console.log(errors.length ? "PAGE ERRORS:\n" + errors.join("\n") : "페이지 오류 없음");
  console.log(`\n${n - failed}/${n} 통과`);
  await browser.close();
  process.exit(failed || errors.length ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });

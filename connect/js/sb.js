// 공통: Supabase 연결, 로그인 상태, 상단 메뉴, 자주 쓰는 도우미
(function () {
  const S = window.SITE;
  const sb = window.supabase.createClient(S.supabaseUrl, S.supabaseKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  });

  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const won = (n) => (n == null ? "-" : Number(n).toLocaleString("ko-KR") + "원");
  const num = (n) => (n == null || n === "" ? "" : Number(n).toLocaleString("ko-KR"));
  const range = (a, b, unit = "") => (a == null && b == null ? "-" : a == null || b == null || a == b ? num(a ?? b) + unit : `${num(a)}~${num(b)}${unit}`);
  const date = (d, withTime) => (d ? new Date(d).toLocaleString("ko-KR", withTime ? { dateStyle: "short", timeStyle: "short" } : { dateStyle: "medium" }) : "-");
  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  const STATUS = {
    draft: ["작성 중", "s-gray"], submitted: ["입금 대기", "s-amber"], open: ["공급자 응답 받는 중", "s-blue"], selecting: ["업체 선정 중", "s-blue"],
    delivered: ["리스트 전달 · 검증 중", "s-green"], disputed: ["이의 처리 중", "s-red"], confirmed: ["확정", "s-green"], cancelled: ["취소", "s-gray"],
  };
  const reqStatus = (r) => (r.status === "draft" && r.submitted_at ? STATUS.submitted : STATUS[r.status] || [r.status, "s-gray"]);
  const badge = ([label, cls]) => `<span class="sbadge ${cls}">${esc(label)}</span>`;
  const ANS = { O: ["● 가능", "a-o"], P: ["▲ 조건부", "a-p"], X: ["✕ 불가", "a-x"], N: ["미확인", "a-n"] };
  const ans = (v) => { const a = ANS[v || "N"]; return `<span class="ans ${a[1]}">${a[0]}</span>`; };

  // 범위 비교 (DB의 range_mark와 같은 규칙, 화면 미리보기용)
  function rangeMark(dmin, dmax, smin, smax, tolPct = 20) {
    const dl = dmin ?? dmax, dh = dmax ?? dmin, sl = smin ?? smax, sh = smax ?? smin;
    if (dl == null || sl == null) return "N";
    if (sl <= dh && sh >= dl) return "O";
    const t = tolPct / 100;
    if (sl <= dh * (1 + t) && sh >= dl * (1 - t)) return "P";
    return "X";
  }

  function toast(msg, kind) {
    let t = $("#toast");
    if (!t) { t = document.createElement("div"); t.id = "toast"; document.body.appendChild(t); }
    t.textContent = msg; t.className = "show " + (kind || "");
    clearTimeout(t._h); t._h = setTimeout(() => (t.className = ""), 3200);
  }
  const errMsg = (e) => (e && (e.message || e.error_description || e.msg)) || "처리하지 못했습니다";

  // ---------- 로그인 상태 ----------
  let me = null; // { user, profile, supplier }
  async function loadMe(force) {
    if (me && !force) return me;
    const { data: { session } } = await sb.auth.getSession();
    if (!session) { me = { user: null }; return me; }
    const user = session.user;
    const { data: profile } = await sb.from("profiles").select("*").eq("id", user.id).maybeSingle();
    let supplier = null;
    if (profile && profile.role === "supplier") {
      const r = await sb.from("suppliers").select("*").eq("id", user.id).maybeSingle();
      supplier = r.data;
    }
    me = { user, profile, supplier };
    return me;
  }

  // 로그인이 필요한 화면: 역할이 맞지 않으면 안내 후 이동
  async function requireLogin(roles) {
    const m = await loadMe();
    if (!m.user) { location.href = "login.html?next=" + encodeURIComponent(location.pathname.split("/").pop() + location.search); return null; }
    if (roles && (!m.profile || !roles.includes(m.profile.role))) {
      document.querySelector("main").innerHTML = `<div class="wrap empty-page"><h1>이 화면을 볼 수 없습니다</h1><p>${roles.includes("admin") ? "관리자" : roles.includes("supplier") ? "공급자 회원" : "수요자 회원"} 전용 화면입니다.</p><a class="btn" href="index.html">홈으로</a></div>`;
      return null;
    }
    return m;
  }

  // ---------- 상단 메뉴 ----------
  async function renderNav() {
    const nav = $("#nav");
    if (!nav) return;
    const m = await loadMe();
    const role = m.profile && m.profile.role;
    const links = [
      ["directory.html", "공급사 둘러보기"],
      ["index.html#fee", "이용 요금"],
    ];
    if (role === "supplier") links.push(["supplier.html", "공급자 센터"]);
    else links.push(["request.html", "의뢰하기"]);
    if (role === "demander" || role === "admin") links.push(["projects.html", "내 프로젝트"]);
    if (role === "admin") links.push(["admin.html", "관리자"]);
    nav.innerHTML = `
      <div class="wrap nav-in">
        <a href="index.html" class="logo"><span class="logo-mark">W</span><span>${esc(S.brand)}</span></a>
        <nav class="menu" id="menu">${links.map(([h, l]) => `<a href="${h}">${l}</a>`).join("")}</nav>
        ${m.user
          ? `<span class="nav-user">${esc(m.profile ? m.profile.name : m.user.email)}</span><button class="btn btn-sm btn-ghost" id="logoutBtn">로그아웃</button>`
          : `<a href="login.html" class="btn btn-sm btn-ghost">로그인</a><a href="login.html?signup=1" class="btn btn-sm">회원가입</a>`}
        <button class="menu-btn" aria-label="메뉴" id="menuBtn">☰</button>
      </div>`;
    $("#menuBtn").onclick = () => $("#menu").classList.toggle("open");
    const lo = $("#logoutBtn");
    if (lo) lo.onclick = async () => { await sb.auth.signOut(); location.href = "index.html"; };
  }

  function renderFooter() {
    const f = $("#foot");
    if (!f) return;
    const biz = [S.operator && "상호 " + S.operator, S.ceo && "대표 " + S.ceo, S.bizNo && "사업자등록번호 " + S.bizNo, S.mailOrderNo && "통신판매업 " + S.mailOrderNo].filter(Boolean).join(" · ");
    f.innerHTML = `
      <div class="wrap foot-in">
        <div>
          <p class="logo"><span class="logo-mark">W</span><span>${esc(S.brand)}</span></p>
          <p class="foot-sub">운영 ${esc(S.operator)} · ${esc(S.address)}</p>
          <p class="foot-sub">${esc(biz)}</p>
          <p class="foot-sub"><a href="terms.html"><b>이용약관</b></a> · <a href="privacy.html"><b>개인정보처리방침</b></a></p>
        </div>
        <div class="foot-contact">
          <a href="tel:${esc(S.phone.replace(/[^0-9+]/g, ""))}">☎ ${esc(S.phone)}</a>
          <a href="mailto:${esc(S.email)}">✉ ${esc(S.email)}</a>
          ${S.kakao ? `<a class="kakao" href="${esc(S.kakao)}" target="_blank" rel="noopener">카카오톡 상담</a>` : ""}
        </div>
      </div>`;
  }

  // ---------- 분류·요금 (캐시) ----------
  let cache = null;
  async function catalog() {
    if (cache) return cache;
    const [c, i, p, pr] = await Promise.all([
      sb.from("categories").select("*").order("sort"),
      sb.from("checklist_items").select("*").order("sort"),
      sb.from("processes").select("*").order("id"),
      sb.from("pricing").select("*"),
    ]);
    const err = c.error || i.error || p.error || pr.error;
    if (err) throw err;
    const pricing = Object.fromEntries(pr.data.map((x) => [x.key, x.value]));
    const majors = c.data.filter((x) => x.parent_id == null);
    const minorsOf = (id) => c.data.filter((x) => x.parent_id === id);
    const catName = (id) => (c.data.find((x) => x.id === id) || {}).name || "";
    cache = { categories: c.data, majors, minorsOf, catName, items: i.data, processes: p.data, pricing };
    return cache;
  }
  // 수요자 금액 계산 (DB quote_amount와 같은 규칙)
  function quote(cat, kind, supplierCount, itemIds) {
    const p = cat.pricing;
    const base = kind === "direct" ? p.direct_base : p.open_base;
    const extra = Math.max(supplierCount - p.base_suppliers, 0) * (kind === "direct" ? p.direct_extra_supplier : p.open_extra_supplier);
    const items = cat.items.filter((x) => itemIds.includes(x.id) && !x.is_required).reduce((s, x) => s + x.price, 0);
    return { base, extra, items, total: base + extra + items };
  }
  // 이 대분류에서 공급자가 답할 선택형 필수 항목 (C1~C3 범위 항목 제외)
  const requiredItems = (cat, majorId) => cat.items.filter((x) => x.is_required && x.kind === "choice" && (x.major_id == null || x.major_id === majorId));
  const conditionItems = (cat, majorId, minorId) => cat.items.filter((x) => !x.is_required && x.major_id === majorId && (x.minor_id == null || x.minor_id === minorId));

  async function signedUrl(path) {
    const { data } = await sb.storage.from(S.storageBucket).createSignedUrl(path, 3600);
    return data && data.signedUrl;
  }

  const SIDO = ["서울", "경기", "인천", "강원", "충북", "충남", "대전", "세종", "전북", "전남", "광주", "경북", "경남", "대구", "울산", "부산", "제주"];

  window.APP = { sb, S, esc, won, num, range, date, $, $$, toast, errMsg, loadMe, requireLogin, renderNav, renderFooter, catalog, quote,
    requiredItems, conditionItems, reqStatus, badge, ans, rangeMark, signedUrl, SIDO, STATUS };

  document.addEventListener("DOMContentLoaded", () => { renderNav(); renderFooter(); });
})();

(function () {
  const S = window.SITE || {};

  // ---- 설정값을 화면에 채우기 ----
  document.querySelectorAll("[data-site]").forEach((el) => {
    const v = S[el.dataset.site];
    if (v !== undefined && v !== "") el.textContent = v;
  });
  document.querySelectorAll("[data-fee]").forEach((el) => {
    const v = (S.fees || {})[el.dataset.fee];
    if (v) el.textContent = v;
  });
  const links = { tel: "tel:" + (S.phone || "").replace(/[^0-9+]/g, ""), mail: "mailto:" + S.email, kakao: S.kakao };
  document.querySelectorAll("[data-href]").forEach((el) => {
    const v = links[el.dataset.href];
    if (el.dataset.href === "kakao") { if (S.kakao) { el.href = v; el.hidden = false; el.target = "_blank"; el.rel = "noopener"; } return; }
    el.href = v;
  });

  // ---- 사업자 정보 (하단) ----
  const biz = document.getElementById("bizInfo");
  if (biz) {
    biz.textContent = [
      S.operator && "상호 " + S.operator, S.ceo && "대표 " + S.ceo,
      S.bizNo && "사업자등록번호 " + S.bizNo, S.mailOrderNo && "통신판매업 " + S.mailOrderNo,
    ].filter(Boolean).join(" · ");
  }

  // ---- 게시판 ----
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const board = document.getElementById("boardList");
  if (board) {
    board.innerHTML = (S.board || []).map((j) => `
      <article class="job">
        <div class="job-top">
          <span class="job-cat">${esc(j.cat)}</span>
          ${j.example ? '<span class="job-ex">예시</span>' : ""}
          <span class="job-st ${j.status === "연결 완료" ? "done" : ""}">${esc(j.status)}</span>
        </div>
        <b>${esc(j.title)}</b>
        <span class="job-meta">수량 ${esc(j.qty)} · 납기 ${esc(j.due)}</span>
      </article>`).join("");
  }

  // ---- 폼 접수 ----
  document.querySelectorAll("form[data-kind]").forEach((form) => {
    const msg = form.querySelector(".form-msg");
    const btn = form.querySelector("button[type=submit]");
    const say = (t, cls) => { msg.textContent = t; msg.className = "form-msg " + (cls || ""); };

    form.addEventListener("input", (e) => e.target.classList.remove("invalid"));

    form.addEventListener("submit", async (e) => {
      e.preventDefault();
      let bad = null;
      form.querySelectorAll("[required]").forEach((f) => {
        const empty = f.type === "checkbox" ? !f.checked : !f.value.trim();
        f.classList.toggle("invalid", empty);
        if (empty && !bad) bad = f;
      });
      if (bad) { say("표시된 항목을 채워 주세요.", "err"); bad.focus(); return; }

      const data = { 구분: form.dataset.kind, 접수일시: new Date().toLocaleString("ko-KR") };
      new FormData(form).forEach((v, k) => { if (!["동의", "제공동의", "수수료동의"].includes(k)) data[k] = String(v).trim(); });
      data.개인정보동의 = "수집·이용, 제3자 제공 동의 " + data.접수일시;
      if (form.querySelector("[name=수수료동의]")) data.수수료동의 = "동의 " + data.접수일시;

      btn.disabled = true; say("보내는 중…");
      try {
        if (S.endpoint) {
          // Apps Script 웹앱은 CORS 응답을 주지 않으므로 no-cors + text/plain 으로 보냅니다.
          await fetch(S.endpoint, { method: "POST", mode: "no-cors", headers: { "Content-Type": "text/plain;charset=utf-8" }, body: JSON.stringify(data) });
          form.reset();
          say("접수되었습니다. 하루 안에 연락드리겠습니다.", "ok");
        } else {
          const body = Object.entries(data).map(([k, v]) => `${k}: ${v || "-"}`).join("\n");
          const subject = `[${S.brand}] ${data.구분} - ${data.회사 || data.업체명 || data.이름}`;
          location.href = `mailto:${S.email}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
          say("메일 앱이 열리면 '보내기'를 눌러 주세요. 열리지 않으면 " + S.phone + "로 연락 주세요.", "ok");
        }
      } catch (err) {
        say("전송에 실패했습니다. " + S.phone + "로 연락 주세요.", "err");
      } finally {
        btn.disabled = false;
      }
    });
  });

  // ---- 앱 설치(PWA) ----
  if ("serviceWorker" in navigator && location.protocol !== "file:") {
    navigator.serviceWorker.register("sw.js").catch(() => {});
  }
  document.querySelectorAll(".menu a").forEach((a) => a.addEventListener("click", () => document.getElementById("menu").classList.remove("open")));
})();

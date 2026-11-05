// 공급자 리스트(체크리스트) 화면 그리기 — report.html 과 admin.html 미리보기에서 함께 씁니다.
(function () {
  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const ANS = {
    O: { label: "가능", mark: "●", cls: "a-o", pt: 1 },
    P: { label: "조건부", mark: "▲", cls: "a-p", pt: 0.5 },
    X: { label: "불가", mark: "✕", cls: "a-x", pt: 0 },
    "": { label: "미확인", mark: "–", cls: "a-n" },
  };

  // 적합도: 확인한 질문 기준 (가능 1점, 조건부 0.5점)
  function score(s, n) {
    const ans = (s.answers || []).slice(0, n).filter((a) => a && ANS[a.a] && a.a !== "");
    if (!ans.length) return { pct: null, checked: 0, total: n };
    const pts = ans.reduce((t, a) => t + ANS[a.a].pt, 0);
    return { pct: Math.round((pts / ans.length) * 100), checked: ans.length, total: n };
  }

  const badge = (a) => { const x = ANS[(a && a.a) || ""] || ANS[""]; return `<span class="ans ${x.cls}">${x.mark} ${x.label}</span>`; };

  function render(el, d, opts) {
    opts = opts || {};
    const qs = d.questions || [];
    const sups = (d.suppliers || []).map((s, i) => ({ s, i, sc: score(s, qs.length) }))
      .sort((a, b) => (b.sc.pct ?? -1) - (a.sc.pct ?? -1));
    const brand = (window.SITE && window.SITE.brand) || "";
    const phone = (window.SITE && window.SITE.phone) || "";

    const cards = sups.map(({ s, sc }, rank) => `
      <article class="rp-card">
        <div class="rp-card-top">
          <div>
            ${rank === 0 && sc.pct !== null ? '<span class="rp-best">가장 잘 맞음</span>' : ""}
            <h3>${esc(s.name || "공급사")}</h3>
            ${s.region ? `<span class="rp-region">${esc(s.region)}</span>` : ""}
          </div>
          <div class="rp-score">
            <b>${sc.pct === null ? "–" : sc.pct + "%"}</b>
            <small>적합도 · 확인 ${sc.checked}/${sc.total}</small>
          </div>
        </div>
        <div class="rp-bar"><span style="width:${sc.pct || 0}%"></span></div>
        <ul class="rp-checks">
          ${qs.map((q, qi) => {
            const a = (s.answers || [])[qi] || {};
            return `<li><span class="rp-q">${esc(q)}</span>${badge(a)}${a.note ? `<span class="rp-note">${esc(a.note)}</span>` : ""}</li>`;
          }).join("")}
        </ul>
        ${(s.price || s.moq || s.due) ? `<dl class="rp-facts">
          ${s.price ? `<div><dt>단가</dt><dd>${esc(s.price)}</dd></div>` : ""}
          ${s.moq ? `<div><dt>MOQ</dt><dd>${esc(s.moq)}</dd></div>` : ""}
          ${s.due ? `<div><dt>납기</dt><dd>${esc(s.due)}</dd></div>` : ""}
        </dl>` : ""}
        ${s.memo ? `<p class="rp-memo"><b>상담 메모</b> ${esc(s.memo)}</p>` : ""}
        ${d.reveal ? `
          <div class="rp-contact">
            ${s.person ? `<span>담당 <b>${esc(s.person)}</b></span>` : ""}
            ${s.phone ? `<a class="btn btn-sm" href="tel:${esc(String(s.phone).replace(/[^0-9+]/g, ""))}">☎ ${esc(s.phone)}</a>` : ""}
            ${s.email ? `<a class="btn btn-sm btn-ghost" href="mailto:${esc(s.email)}">✉ 메일</a>` : ""}
          </div>` : `
          <div class="rp-locked">🔒 업체명과 연락처는 연결비 확인 후 이 화면에 공개됩니다.</div>`}
      </article>`).join("");

    const table = qs.length && sups.length > 1 ? `
      <h2 class="rp-h2">한눈에 비교</h2>
      <div class="rp-table-wrap"><table class="rp-table">
        <thead><tr><th>질문</th>${sups.map(({ s }) => `<th>${esc(s.name)}</th>`).join("")}</tr></thead>
        <tbody>
          ${qs.map((q, qi) => `<tr><td>${esc(q)}</td>${sups.map(({ s }) => `<td>${badge((s.answers || [])[qi])}</td>`).join("")}</tr>`).join("")}
          <tr class="rp-total"><td>적합도</td>${sups.map(({ sc }) => `<td>${sc.pct === null ? "–" : sc.pct + "%"}</td>`).join("")}</tr>
        </tbody>
      </table></div>` : "";

    el.innerHTML = `
      <header class="rp-head">
        <p class="eyebrow">${esc(brand)} 공급자 리스트${opts.example ? ' <span class="job-ex">예시</span>' : ""}</p>
        <h1>${esc(d.item || "의뢰")}</h1>
        <p class="rp-meta">
          <span>의뢰번호 <b>${esc(d.id)}</b></span>
          ${d.cat ? `<span>${esc(d.cat)}</span>` : ""}
          ${d.qty ? `<span>수량 ${esc(d.qty)}</span>` : ""}
          ${d.due ? `<span>납기 ${esc(d.due)}</span>` : ""}
          ${d.date ? `<span>리스트 제공일 ${esc(String(d.date).slice(0, 10))}</span>` : ""}
        </p>
        <p class="rp-legend">${badge({ a: "O" })} ${badge({ a: "P" })} ${badge({ a: "X" })} ${badge({ a: "" })}
          <small>적합도는 확인한 질문 중 가능 1점, 조건부 0.5점으로 계산합니다.</small></p>
      </header>
      ${d.reveal ? `<div class="rp-howto"><b>업체에 연락하실 때</b> "${esc(brand)} 리스트 보고 연락드립니다, 의뢰번호 ${esc(d.id)}"라고 말씀해 주세요. 이미 내용을 알고 있어 바로 상담이 이어집니다.</div>` : ""}
      ${sups.length ? `<div class="rp-cards">${cards}</div>` : '<p class="empty">아직 등록된 공급자가 없습니다.</p>'}
      ${table}
      <footer class="rp-foot">
        <p>이 리스트는 의뢰인 전용입니다. 제3자에게 공유하지 말아 주세요.</p>
        <p>리스트에 있는 업체는 ${esc(brand)}가 소개한 업체로 기록되며, 공급자와의 약정에 따라 소개일부터 1년 동안 소개 관계가 유지됩니다. 의뢰인에게는 연결비 외에 추가 비용이 없습니다.</p>
        <p>문의 ${esc(phone)}</p>
      </footer>`;
  }

  window.ReportView = { render, score, ANS };
})();

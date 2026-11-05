/**
 * 윈-윈 커넥트 접수용 Google Apps Script
 * - 홈페이지 의뢰서/공급사 등록을 구글 시트에 저장하고 알림 메일을 보냅니다.
 * - 관리자 페이지(admin.html)에서 목록 조회, 진행상태 변경, 공급자 리스트(체크리스트) 작성을 합니다.
 * - 수요자는 report.html 링크로 자기 의뢰의 공급자 리스트를 봅니다. 열람 기록이 시트에 남습니다.
 *
 * 설치 방법은 README.md 참고. 코드를 고친 뒤에는 "배포 관리 → 수정 → 새 버전"으로 다시 배포하세요.
 */

// 관리자 비밀번호: 아무도 모르는 긴 문자열로 바꾸세요. admin.html 로그인에 씁니다.
const ADMIN_TOKEN = "여기에-긴-비밀번호를-넣으세요";
// 새 접수 알림을 받을 메일 (비우면 알림 안 보냄)
const NOTIFY_EMAIL = "info@kblogistics.kr";

const SHEETS = {
  "의뢰": ["의뢰번호", "접수일시", "상태", "회사", "이름", "연락처", "이메일", "분야", "품목", "수량", "예산", "납기", "질문", "내용",
           "개인정보동의", "메모", "리포트", "연락처공개", "리포트제공일", "열람기록", "리포트키"],
  "공급사": ["접수일시", "상태", "업체명", "이름", "연락처", "이메일", "분야", "지역", "공정", "MOQ", "여력", "소개",
            "개인정보동의", "수수료동의", "메모"],
};
const STATUSES = ["신규", "확인중", "업체수배", "리스트전달", "연결완료", "정산완료", "보류"];
const TZ = "Asia/Seoul";

// ---------- 시트 도우미 ----------
function sheet_(name) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.appendRow(SHEETS[name]);
    sh.setFrozenRows(1);
  }
  // 열이 추가된 경우 머리글을 뒤에 덧붙임 (기존 데이터 보존)
  const head = header_(sh);
  const missing = SHEETS[name].filter((h) => head.indexOf(h) < 0);
  if (missing.length) sh.getRange(1, head.length + 1, 1, missing.length).setValues([missing]);
  sh.getRange(1, 1, 1, sh.getLastColumn()).setFontWeight("bold");
  return sh;
}
function header_(sh) {
  if (sh.getLastColumn() === 0) return [];
  return sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String).filter((h) => h);
}
function setCell_(sh, row, col, value) {
  const head = header_(sh);
  sh.getRange(row, head.indexOf(col) + 1).setValue(value);
}
function getRowObj_(sh, row) {
  const head = header_(sh);
  const vals = sh.getRange(row, 1, 1, head.length).getValues()[0];
  const o = {};
  head.forEach((h, i) => (o[h] = vals[i] instanceof Date ? fmt_(vals[i]) : vals[i]));
  return o;
}
function findRow_(sh, col, value) {
  const head = header_(sh);
  const c = head.indexOf(col) + 1;
  if (!c || sh.getLastRow() < 2) return 0;
  const vals = sh.getRange(2, c, sh.getLastRow() - 1, 1).getValues();
  for (let i = 0; i < vals.length; i++) if (String(vals[i][0]) === String(value)) return i + 2;
  return 0;
}
function safe_(v) {
  v = String(v == null ? "" : v).slice(0, 2000);
  return /^[=+\-@]/.test(v) ? "'" + v : v; // 수식 주입 방지
}
function fmt_(d) { return Utilities.formatDate(d, TZ, "yyyy-MM-dd HH:mm"); }
function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}
function out_(obj, callback) {
  if (callback && /^[A-Za-z_$][\w$]*$/.test(callback)) {
    return ContentService.createTextOutput(callback + "(" + JSON.stringify(obj) + ")").setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return json_(obj);
}

// ---------- 접수 / 관리자 저장 ----------
function doPost(e) {
  const data = JSON.parse(e.postData.contents || "{}");
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try {
    if (data.action) {
      if (data.token !== ADMIN_TOKEN) return json_({ ok: false, error: "unauthorized" });
      return adminPost_(data);
    }
    return submit_(data);
  } finally {
    lock.releaseLock();
  }
}

function submit_(data) {
  const kind = SHEETS[data["구분"]] ? data["구분"] : "의뢰";
  const sh = sheet_(kind);
  data["상태"] = "신규";
  data["접수일시"] = fmt_(new Date());
  if (kind === "의뢰") {
    data["의뢰번호"] = "R" + Utilities.formatDate(new Date(), TZ, "yyMMdd") + "-" + String(sh.getLastRow()).padStart(3, "0");
    data["리포트키"] = Utilities.getUuid().replace(/-/g, "").slice(0, 16);
    data["연락처공개"] = "N";
  }
  const head = header_(sh);
  // 질문 목록은 JSON 그대로 저장 (수식 방지 처리 안 함)
  sh.appendRow(head.map((h) => (h === "질문" ? String(data[h] || "[]") : safe_(data[h]))));

  if (NOTIFY_EMAIL) {
    const lines = head.filter((h) => h !== "리포트키" && h !== "리포트" && data[h]).map((h) => {
      if (h === "질문") { try { return "질문:\n" + JSON.parse(data[h]).map((q, i) => "  " + (i + 1) + ". " + q).join("\n"); } catch (err) {} }
      return h + ": " + data[h];
    });
    MailApp.sendEmail(NOTIFY_EMAIL, "[윈-윈 커넥트] 새 " + kind + " - " + (data["회사"] || data["업체명"] || data["이름"]), lines.join("\n"));
  }
  return json_({ ok: true });
}

function adminPost_(data) {
  const sh = sheet_(data.sheet || "의뢰");
  if (data.action === "status") {
    if (data.status !== undefined) setCell_(sh, data.row, "상태", data.status);
    if (data.memo !== undefined) setCell_(sh, data.row, "메모", safe_(data.memo));
    return json_({ ok: true });
  }
  if (data.action === "saveReport") {
    // report: { questions: [..], suppliers: [{ name, person, phone, email, region, answers:[{a,note}], price, moq, due, memo }] }
    setCell_(sh, data.row, "리포트", JSON.stringify(data.report || {}));
    setCell_(sh, data.row, "연락처공개", data.reveal ? "Y" : "N");
    const cur = getRowObj_(sh, data.row);
    if (data.publish && !cur["리포트제공일"]) {
      setCell_(sh, data.row, "리포트제공일", fmt_(new Date()));
      if (["신규", "확인중", "업체수배"].indexOf(cur["상태"]) >= 0) setCell_(sh, data.row, "상태", "리스트전달");
    }
    return json_({ ok: true });
  }
  return json_({ ok: false, error: "unknown action" });
}

// ---------- 조회 ----------
// 관리자: ?token=...&callback=fn
// 수요자 리포트: ?action=report&id=의뢰번호&k=리포트키&callback=fn
function doGet(e) {
  const p = e.parameter || {};
  if (p.action === "report") return out_(report_(p.id, p.k), p.callback);
  if (p.token !== ADMIN_TOKEN) return out_({ ok: false, error: "unauthorized" }, p.callback);

  const out = { ok: true, statuses: STATUSES, data: {} };
  Object.keys(SHEETS).forEach((name) => {
    const sh = sheet_(name);
    const values = sh.getDataRange().getValues();
    const head = values.shift().map(String);
    out.data[name] = values.map((r, i) => {
      const o = { _row: i + 2 };
      head.forEach((h, j) => { if (h) o[h] = r[j] instanceof Date ? fmt_(r[j]) : r[j]; });
      return o;
    });
  });
  return out_(out, p.callback);
}

function report_(id, key) {
  const sh = sheet_("의뢰");
  const row = id ? findRow_(sh, "의뢰번호", id) : 0;
  if (!row) return { ok: false, error: "notfound" };
  const r = getRowObj_(sh, row);
  if (!key || String(r["리포트키"]) !== String(key)) return { ok: false, error: "notfound" };
  if (!r["리포트제공일"]) return { ok: false, error: "notready" };

  const reveal = r["연락처공개"] === "Y";
  let report = {};
  try { report = JSON.parse(r["리포트"] || "{}"); } catch (err) {}
  const suppliers = (report.suppliers || []).map((s, i) => {
    const o = { answers: s.answers || [], price: s.price, moq: s.moq, due: s.due, memo: s.memo, region: s.region };
    if (reveal) { o.name = s.name; o.person = s.person; o.phone = s.phone; o.email = s.email; }
    else { o.name = "공급사 " + String.fromCharCode(65 + i); }
    return o;
  });

  // 열람 기록 (소개 사실의 근거). 최근 20건만 유지
  const log = String(r["열람기록"] || "").split("\n").filter(String);
  log.push(fmt_(new Date()) + (reveal ? " 연락처공개" : " 미리보기"));
  setCell_(sh, row, "열람기록", log.slice(-20).join("\n"));

  return {
    ok: true, id: r["의뢰번호"], company: r["회사"], item: r["품목"], cat: r["분야"], qty: r["수량"], due: r["납기"],
    date: r["리포트제공일"], reveal: reveal, questions: report.questions || [], suppliers: suppliers,
  };
}

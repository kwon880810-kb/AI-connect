/**
 * KB커넥트 접수용 Google Apps Script
 * - 홈페이지 의뢰서/공급사 등록을 구글 시트에 저장하고 알림 메일을 보냅니다.
 * - 관리자 페이지(admin.html)에서 목록 조회와 진행상태 변경을 합니다.
 *
 * 설치 방법은 apps-script/README.md 참고.
 */

// 관리자 비밀번호: 아무도 모르는 긴 문자열로 바꾸세요. admin.html 로그인에 씁니다.
const ADMIN_TOKEN = "여기에-긴-비밀번호를-넣으세요";
// 새 접수 알림을 받을 메일 (비우면 알림 안 보냄)
const NOTIFY_EMAIL = "info@kblogistics.kr";

const SHEETS = {
  "의뢰":   ["접수일시", "상태", "회사", "이름", "연락처", "이메일", "분야", "품목", "수량", "예산", "납기", "내용", "메모"],
  "공급사": ["접수일시", "상태", "업체명", "이름", "연락처", "이메일", "분야", "지역", "공정", "MOQ", "여력", "소개", "메모"],
};
const STATUSES = ["신규", "확인중", "업체수배", "명함전달", "연결완료", "정산완료", "보류"];

function sheet_(name) {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  let sh = ss.getSheetByName(name);
  if (!sh) {
    sh = ss.insertSheet(name);
    sh.appendRow(SHEETS[name]);
    sh.setFrozenRows(1);
    sh.getRange(1, 1, 1, SHEETS[name].length).setFontWeight("bold");
  }
  return sh;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

// 홈페이지 폼 접수 + 관리자 상태 변경
function doPost(e) {
  const data = JSON.parse(e.postData.contents || "{}");

  if (data.action === "status") {
    if (data.token !== ADMIN_TOKEN) return json_({ ok: false, error: "unauthorized" });
    const sh = sheet_(data.sheet);
    const head = SHEETS[data.sheet];
    if (data.status !== undefined) sh.getRange(data.row, head.indexOf("상태") + 1).setValue(data.status);
    if (data.memo !== undefined) sh.getRange(data.row, head.indexOf("메모") + 1).setValue(data.memo);
    return json_({ ok: true });
  }

  const kind = SHEETS[data["구분"]] ? data["구분"] : "의뢰";
  const head = SHEETS[kind];
  data["상태"] = "신규";
  data["접수일시"] = data["접수일시"] || new Date().toLocaleString("ko-KR");
  // 수식 주입 방지: = + - @ 로 시작하는 값 앞에 ' 를 붙임
  const row = head.map((h) => {
    const v = String(data[h] || "").slice(0, 2000);
    return /^[=+\-@]/.test(v) ? "'" + v : v;
  });
  sheet_(kind).appendRow(row);

  if (NOTIFY_EMAIL) {
    const body = head.map((h, i) => h + ": " + (row[i] || "-")).join("\n");
    MailApp.sendEmail(NOTIFY_EMAIL, "[KB커넥트] 새 " + kind + " - " + (data["회사"] || data["업체명"] || data["이름"]), body);
  }
  return json_({ ok: true });
}

// 관리자 목록 조회: ?token=...  (JSONP 지원: &callback=fn)
function doGet(e) {
  const p = e.parameter || {};
  let out;
  if (p.token !== ADMIN_TOKEN) {
    out = { ok: false, error: "unauthorized" };
  } else {
    out = { ok: true, statuses: STATUSES, data: {} };
    Object.keys(SHEETS).forEach((name) => {
      const values = sheet_(name).getDataRange().getValues();
      const head = values.shift();
      out.data[name] = values.map((r, i) => {
        const o = { _row: i + 2 };
        head.forEach((h, j) => (o[h] = r[j] instanceof Date ? r[j].toLocaleString("ko-KR") : r[j]));
        return o;
      });
    });
  }
  if (p.callback && /^[A-Za-z_$][\w$]*$/.test(p.callback)) {
    return ContentService.createTextOutput(p.callback + "(" + JSON.stringify(out) + ")").setMimeType(ContentService.MimeType.JAVASCRIPT);
  }
  return json_(out);
}

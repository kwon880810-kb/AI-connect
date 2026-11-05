// =============================================================
//  사이트 설정 — 상호, 연락처, 접속 정보는 여기서만 고치면 됩니다.
//  금액은 Supabase의 pricing 표에서 관리합니다 (화면은 자동으로 따라감).
// =============================================================
window.SITE = {
  brand: "윈-윈 커넥트",
  tagline: "아이디어 현실화 플랫폼",   // 로고 옆 부제
  slogan: "아이디어를 가진 사람과, 그 아이디어를 실물로 만드는 공장을 잇습니다",
  operator: "KB물류",
  ceo: "권봉구",
  since: 2011,
  phone: "031-945-9851",
  email: "info@kblogistics.kr",
  address: "경기도 파주시 검산로 191",
  bizNo: "",            // 사업자등록번호 (입력하면 하단에 표시)
  mailOrderNo: "",      // 통신판매업 신고번호 (해당되면 입력)
  vatNote: "",          // 예: "모든 금액은 부가세 별도입니다."
  kakao: "",            // 카카오톡 채널 주소 (홈페이지 오픈 후)

  // 입금 안내 (PG 결제 연동 전까지 계좌이체로 받음)
  bankInfo: "입금 계좌는 의뢰 접수 후 문자로 안내드립니다.",

  // Supabase 접속 정보 (공개 키라 노출되어도 괜찮음. 데이터 보호는 DB 권한 규칙이 함)
  supabaseUrl: "https://ityavotmbqzatuhaygdg.supabase.co",
  supabaseKey: "sb_publishable_1j6pGXO7xZyX-eeOoY965g_6KgXGnDd",
  storageBucket: "request-files",
};

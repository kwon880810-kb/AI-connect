// =============================================================
//  사이트 설정 — 상호, 연락처, 비용, 접수 주소는 여기서만 고치면 됩니다.
// =============================================================
window.SITE = {
  brand: "KB커넥트",
  operator: "KB물류",
  since: 2011,
  phone: "031-945-9851",
  email: "info@kblogistics.kr",
  kakao: "",            // 카카오톡 채널 주소 (예: https://pf.kakao.com/_xxxx). 비워두면 버튼 숨김
  address: "경기도 파주시 검산로 191",

  // Google Apps Script 웹앱 주소 (apps-script/README 참고).
  // 비워두면 의뢰서가 이메일 앱으로 열립니다.
  endpoint: "",

  // 비용 안내 (금액은 언제든 바꿀 수 있는 제안값입니다)
  fees: {
    request: "무료",
    connect: "건당 50,000원~",
    success: "거래금액의 5~10%",
  },

  // '지금 찾고 있는 일' 게시판. 실제 의뢰가 들어오면 개인정보를 빼고 여기에 올리세요.
  // example: true 인 항목은 화면에 '예시' 표시가 붙습니다.
  board: [
    { cat: "소량 OEM", title: "반려동물 간식 파우치 소량 생산", qty: "1,000개", due: "6주 이내", status: "업체 찾는 중", example: true },
    { cat: "패키지 인쇄", title: "단상자 인쇄 (1도, 230×170×110)", qty: "3,000개", due: "1개월", status: "견적 비교 중", example: true },
    { cat: "포장·조립", title: "선물세트 키팅 작업 인력", qty: "2,000세트", due: "명절 전", status: "업체 찾는 중", example: true },
    { cat: "부자재", title: "친환경 완충재·종이 테이프 공급처", qty: "월 정기", due: "협의", status: "연결 완료", example: true },
  ],
};

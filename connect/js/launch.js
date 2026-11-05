// 출시 프로젝트 공통 정보: 차수·단계·선택지·도움말·AI 도구·인증 안내·판매 채널
// 문구를 바꾸려면 이 파일만 고치면 됩니다.
(function () {
  const PHASES = [
    { id: "1", label: "1차", name: "아이디어 · 제품 생산", steps: [1, 2], desc: "아이디어를 정리하고 만들어 줄 공장을 찾습니다. 샘플·제품을 받아 보고 다음으로 넘어가세요." },
    { id: "2", label: "2차", name: "포장 형태 · 디자인 · 포장재", steps: [3, 4, 5], desc: "제품을 담을 포장을 정하고 디자인과 포장재 제작을 준비합니다." },
    { id: "2-1", label: "2-1차", name: "표시사항 · 인증", steps: [6], desc: "판매 전에 필요한 표시사항과 인증을 확인합니다. 필요 없는 품목은 건너뛰세요." },
    { id: "3", label: "3차", name: "촬영 · 상세페이지 · 판매 채널", steps: [7, 9], desc: "판매 페이지를 만들고 어디서 팔지 정합니다." },
    { id: "4", label: "4차", name: "물류", steps: [8], desc: "보관과 발송을 어떻게 할지 정합니다." },
  ];

  // source: 이 선택지를 고르면 파트너 찾기 의뢰가 생김 (major/minor = 분류)
  // followup: 이미 연결된 파트너에게 무료로 문의
  const STEPS = {
    1: {
      title: "아이디어 · 컨셉",
      options: [
        { v: "text", label: "설명만 적기", help: "글로만 설명해도 충분합니다. 무엇을, 누구에게, 왜 팔고 싶은지 적어 주세요." },
        { v: "sketch", label: "내 스케치·이미지 올리기", help: "손그림, 참고 제품 사진, 비슷한 상품 캡처도 좋습니다. 공장이 원하는 모양을 훨씬 빨리 이해합니다." },
        { v: "ai", label: "AI 도구로 만든 이미지 올리기", help: "아래 AI 이미지 도구에서 컨셉 이미지를 만든 뒤 올려 주세요. 참고용 시안으로만 쓰입니다." },
      ],
    },
    2: {
      title: "제품 생산",
      options: [
        { v: "oem", label: "OEM", sub: "내 사양대로 생산", help: "레시피·설계·사양을 내가 정하고, 공장은 그대로 만들어 주는 방식입니다. 원하는 것이 분명할 때 맞습니다.", source: { kind: "product" } },
        { v: "odm", label: "ODM", sub: "레시피·설계까지 공장이", help: "공장이 가진 레시피·설계를 바탕으로 내 브랜드 제품을 만드는 방식입니다. 처음 시작하거나 빠르게 출시하고 싶을 때 맞습니다.", source: { kind: "product" } },
        { v: "same", label: "기존 공장에 다시 요청", sub: "무료", help: "이 프로젝트에서 이미 연결된 공장에 사양을 고쳐 다시 요청합니다. 추가 요금이 없습니다.", followup: true, needsPartners: true },
        { v: "have", label: "이미 거래처 있음", help: "만들어 줄 공장이 이미 있으면 이 단계는 건너뛰고 다음 차수로 넘어가세요." },
      ],
    },
    3: {
      title: "포장 형태",
      options: [
        { v: "box", label: "단상자", help: "종이로 만든 제품 상자입니다. 화장품·건강식품·선물용에 많이 씁니다. 골판지 택배 박스와는 다른 공장입니다." },
        { v: "pouch", label: "파우치", help: "지퍼백·스탠딩 파우치 같은 필름 포장입니다. 간식·분말·소포장에 많이 씁니다. 소량이면 디지털 인쇄 파우치가 판 제작비가 없어 유리합니다." },
        { v: "bottle", label: "병·용기", help: "유리병·플라스틱 용기·튜브 등입니다. 용기에 라벨을 붙이거나 직접 인쇄합니다." },
        { v: "label", label: "라벨만", help: "공장 기본 포장에 내 브랜드 라벨·스티커만 붙이는 방식입니다. 가장 빠르고 저렴하게 시작할 수 있습니다." },
        { v: "recommend", label: "추천받기", help: "제품에 맞는 포장을 파트너에게 추천받습니다. 수량과 판매 채널을 함께 알려 주시면 좋습니다." },
      ],
    },
    4: {
      title: "포장 디자인",
      options: [
        { v: "self", label: "직접 디자인", help: "일러스트레이터·포토샵·캔바 등으로 직접 디자인합니다. 인쇄소에 넘길 때는 칼선(재단선)에 맞춘 파일이 필요합니다." },
        { v: "ai", label: "AI 도구 활용", help: "AI_TOOLS" },
        { v: "designer", label: "컨셉만 정하고 디자이너에게", help: "원하는 분위기와 참고 이미지만 정하면 사업자등록이 확인된 디자이너가 완성합니다. 인쇄용 파일까지 받을 수 있는지 체크리스트로 확인합니다.", source: { kind: "service", major: 9, minor: 901 } },
        { v: "have", label: "완성 디자인 있음", help: "이미 완성된 디자인 파일이 있으면 포장재 제작(5단계)으로 넘어가세요." },
      ],
    },
    5: {
      title: "포장재 제작",
      options: [
        { v: "factory", label: "생산 공장에서 함께", sub: "기존 파트너 문의 · 무료", help: "제품을 만드는 공장이 포장재까지 맡을 수 있는지 문의합니다. 이미 연결된 공장이라 추가 요금이 없습니다.", followup: true, needsPartners: true },
        { v: "quote", label: "별도 업체 견적받기", help: "인쇄소·연포장 공장에 따로 견적을 받습니다. 3단계에서 고른 포장 형태에 맞는 업체를 찾습니다.", source: { kind: "packaging", major: 3 } },
        { v: "have", label: "이미 있음", help: "포장재가 이미 준비되어 있으면 건너뛰세요." },
        { v: "later", label: "나중에", help: "디자인이 끝난 뒤에 정해도 됩니다. 프로젝트는 그대로 저장됩니다." },
      ],
    },
    6: {
      title: "표시사항 · 인증",
      options: [
        { v: "none", label: "필요 없음", help: "아래 안내에 해당하는 항목이 없으면 이 단계는 생략합니다." },
        { v: "self", label: "직접 진행", help: "관계 기관에 직접 신고·인증을 진행합니다." },
        { v: "agency", label: "대행 맡기기", help: "신고·인증 대행 파트너를 찾습니다. 같은 분야 대행 실적과 진행 기간을 체크리스트로 확인합니다.", source: { kind: "service", major: 11 } },
      ],
    },
    7: {
      title: "촬영 · 상세페이지",
      options: [
        { v: "self", label: "직접", help: "직접 촬영하고 상세페이지를 만듭니다." },
        { v: "photo", label: "촬영만 맡기기", help: "제품 사진(누끼·연출 컷)만 맡기고 상세페이지는 직접 만듭니다.", source: { kind: "service", major: 10, minor: 1001 } },
        { v: "detail", label: "상세페이지까지 맡기기", help: "촬영부터 판매 채널 규격에 맞춘 상세페이지까지 맡깁니다.", source: { kind: "service", major: 10, minor: 1002 } },
      ],
    },
    8: {
      title: "물류",
      options: [
        { v: "self", label: "직접 발송", help: "보관과 포장·택배 발송을 직접 합니다. 주문이 적을 때 맞습니다." },
        { v: "3pl", label: "3PL 견적받기", help: "보관·포장·택배 출고를 전문 물류 업체(3PL)에 맡깁니다. 판매 채널 주문 연동이 되는지 체크리스트로 확인합니다.", source: { kind: "service", major: 8, minor: 801 } },
        { v: "factory", label: "생산 공장에서 가능한지 문의하기", sub: "기존 파트너 문의 · 무료", help: "제품을 만든 공장이 보관·발송까지 해 줄 수 있는지 문의합니다.", followup: true, needsPartners: true },
      ],
    },
    9: { title: "희망 판매 채널", channels: true },
  };
  // 포장 형태 → 포장재 중분류
  const PACK_MINOR = { box: 302, pouch: 306, label: 304, bottle: null, recommend: null };

  const AI_TOOLS = [
    { name: "ChatGPT", url: "https://chatgpt.com/", note: "대화하듯 설명하면 이미지를 만들고, 수정 요청도 쉽습니다" },
    { name: "Google Gemini", url: "https://gemini.google.com/", note: "구글 계정으로 바로 이미지 생성·편집" },
    { name: "Adobe Firefly", url: "https://firefly.adobe.com/", note: "상업적 이용을 염두에 둔 모델, 포토샵과 연동" },
    { name: "Canva", url: "https://www.canva.com/", note: "만든 이미지를 바로 포장·상세페이지 디자인에 사용" },
    { name: "Microsoft Designer", url: "https://designer.microsoft.com/", note: "무료로 시작하기 쉬움" },
    { name: "Ideogram", url: "https://ideogram.ai/", note: "이미지 안에 제품명·로고 글자 넣기에 강함" },
    { name: "Midjourney", url: "https://www.midjourney.com/", note: "분위기·컨셉 이미지 품질이 높음 (유료)" },
    { name: "Leonardo.ai", url: "https://leonardo.ai/", note: "제품 목업·컨셉 시안용" },
  ];
  const AI_NOTICE = [
    "AI 이미지는 컨셉을 전달하는 참고 시안입니다. 공장·인쇄소가 그대로 만들 수 있는 도면이 아니며, 실제 포장은 규격·칼선에 맞춰 다시 디자인해야 합니다.",
    "상업적 이용 가능 여부는 도구와 요금제마다 다릅니다. 판매 제품에 쓰기 전에 각 도구의 이용약관을 꼭 확인하세요.",
    "AI로 만든 이미지는 저작권 보호를 받기 어려울 수 있습니다. 다른 사람이 비슷하게 써도 막기 어렵습니다.",
    "다른 브랜드의 상표·캐릭터·디자인과 비슷하면 침해가 될 수 있으며, 책임은 이미지를 올린 분에게 있습니다.",
    "올린 이미지는 기본적으로 선정된 파트너에게만 공개됩니다.",
  ];

  // 6단계 인증 안내: 제품 분류(대분류·중분류)에 맞는 항목
  const CERT_NOTES = {
    food: "식품: 품목제조보고(제조 공장), 식품 표시사항(식품등의 표시기준), 자가품질검사",
    health: "건강기능식품: 기능성 원료 인정, 표시·광고 사전 심의",
    pet: "반려동물 간식·사료: 사료 성분 등록, 사료 표시사항",
    petcare: "반려동물 위생·케어: 효능(피부병 완화·살균 등)을 내세우면 동물용 의약외품 허가",
    cosmetic: "화장품: 화장품책임판매업 등록, 화장품 표시사항",
    chemical: "생활화학제품(세제·방향제·탈취제 등): 안전확인대상 생활화학제품 신고",
    kids: "어린이용품: KC 인증 (어린이제품 안전특별법)",
    electric: "전기·전자 제품: KC 전기안전·전자파 인증",
    foodpack: "식품을 담는 포장재: 기구 및 용기·포장 기준 적합 (포장재 업체에 서류 확인)",
  };
  function certNotesFor(major, minor) {
    const n = [];
    if (major === 1) { n.push(CERT_NOTES.food, CERT_NOTES.foodpack); if (minor === 109) n.push(CERT_NOTES.health); }
    if (major === 2) { if ([201, 202, 203].includes(minor) || !minor) n.push(CERT_NOTES.pet); if (minor === 204 || !minor) n.push(CERT_NOTES.petcare); }
    if (major === 4) n.push(CERT_NOTES.cosmetic);
    if (major === 5) n.push(CERT_NOTES.chemical, CERT_NOTES.kids, CERT_NOTES.electric);
    return n;
  }

  const CHANNEL_GROUPS = [
    { name: "오픈마켓·종합몰", items: ["네이버 스마트스토어", "쿠팡", "11번가", "G마켓", "옥션", "SSG닷컴", "롯데ON", "컬리", "카카오톡 선물하기", "오늘의집", "올리브영 온라인"] },
    { name: "패션·라이프 플랫폼", items: ["무신사", "29CM", "W컨셉", "에이블리", "지그재그", "아이디어스"] },
    { name: "자사몰·SNS", items: ["자사몰 (카페24·아임웹·식스샵 등)", "인스타그램·SNS 판매", "라이브커머스"] },
    { name: "해외", items: ["아마존", "쇼피", "그 밖의 해외 판매"] },
    { name: "그 밖의 목적", items: ["지인 선물", "굿즈", "텀블벅", "와디즈"] },
  ];
  const ETC_COUNT = 10;

  const STAGE_NAME = { 2: "제품 생산", 4: "포장 디자인", 5: "포장재 제작", 6: "표시사항·인증 대행", 7: "촬영·상세페이지", 8: "물류" };
  const phaseOfStep = (n) => PHASES.find((p) => p.steps.includes(n));
  const optionOf = (step, v) => ((STEPS[step] || {}).options || []).find((o) => o.v === v);

  // (?) 도움말 말풍선
  function helpButton(text) {
    const esc = window.APP ? APP.esc : (s) => s;
    return `<button type="button" class="qmark" data-help="${esc(text)}" aria-label="설명 보기">?</button>`;
  }
  document.addEventListener("click", (e) => {
    const b = e.target.closest(".qmark");
    document.querySelectorAll(".help-pop").forEach((p) => { if (!b || p.previousElementSibling !== b) p.remove(); });
    if (!b) return;
    e.preventDefault(); e.stopPropagation();
    if (b.nextElementSibling && b.nextElementSibling.classList.contains("help-pop")) { b.nextElementSibling.remove(); return; }
    const pop = document.createElement("div");
    pop.className = "help-pop";
    pop.innerHTML = b.dataset.help === "AI_TOOLS"
      ? "AI로 포장 시안을 만든 뒤 다듬는 방식입니다. 예시 도구: " + AI_TOOLS.slice(0, 6).map((t) => t.name).join(", ") + ". 1단계 아래 링크 목록에서 바로 열 수 있습니다. 인쇄용 파일은 칼선에 맞춰 다시 작업해야 합니다."
      : APP.esc(b.dataset.help);
    b.after(pop);
  });

  // 업체 종류 배지 (분류의 대분류 기준)
  const KIND_BY_MAJOR = { 1: "제조 공장", 2: "제조 공장", 4: "제조 공장", 5: "제조 공장", 6: "제조 공장", 3: "인쇄·포장재", 7: "포장·조립", 8: "3PL", 9: "디자이너", 10: "촬영·상세페이지", 11: "인증 대행사" };
  const KIND_ORDER = ["제조 공장", "인쇄·포장재", "디자이너", "촬영·상세페이지", "인증 대행사", "포장·조립", "3PL"];
  const kindsOf = (categoryIds) => [...new Set((categoryIds || []).map((id) => KIND_BY_MAJOR[id]).filter(Boolean))];

  window.LAUNCH = { KIND_BY_MAJOR, KIND_ORDER, kindsOf, PHASES, STEPS, PACK_MINOR, AI_TOOLS, AI_NOTICE, certNotesFor, CHANNEL_GROUPS, ETC_COUNT, STAGE_NAME, phaseOfStep, optionOf, helpButton };
})();

-- 출시 프로젝트용 분류: 디자인, 촬영·상세페이지, 표시사항·인증 대행 (+ 물류 중분류)
insert into categories (id, parent_id, name, sort) values
  (9,  null, '디자인', 9),
  (10, null, '촬영·상세페이지', 10),
  (11, null, '표시사항·인증 대행', 11)
on conflict (id) do nothing;

insert into categories (id, parent_id, name, aliases, confusion_note, sort) values
  (901, 9, '포장 디자인', '{패키지디자인,포장디자인,박스디자인,파우치디자인}', '인쇄소에 넘길 칼선(재단선)과 인쇄용 파일까지 받을 수 있는지 확인하세요.', 1),
  (902, 9, '로고·브랜딩', '{로고,브랜드,BI,CI,브랜딩}', null, 2),
  (903, 9, '라벨·스티커 디자인', '{라벨디자인,스티커디자인}', null, 3),
  (1001, 10, '제품 촬영', '{제품사진,누끼,연출컷,촬영}', null, 1),
  (1002, 10, '상세페이지 제작', '{상세페이지,상세,썸네일,랜딩}', '판매 채널마다 이미지 규격이 다릅니다. 9단계에서 고른 판매 채널을 함께 알려 주세요.', 2),
  (1003, 10, '영상 제작', '{영상,숏폼,릴스,유튜브}', null, 3),
  (1101, 11, '식품 표시·품목제조보고', '{식품표시,품목제조보고,영양성분}', null, 1),
  (1102, 11, 'KC 인증', '{KC,어린이제품,전기안전,전자파}', null, 2),
  (1103, 11, '화장품 표시·책임판매', '{화장품표시,책임판매업}', null, 3),
  (1104, 11, '생활화학제품 신고', '{생활화학,안전확인,방향제,세정제}', null, 4),
  (1105, 11, '사료 성분 등록·표시', '{사료등록,펫푸드표시}', null, 5),
  (801, 8, '3PL 보관·출고', '{3PL,풀필먼트,물류대행,택배대행}', null, 1),
  (802, 8, '소량 택배 발송', '{택배발송,소량발송}', null, 2)
on conflict (id) do nothing;

-- 대분류 필수 (무료)
insert into checklist_items (code, major_id, label, question, kind, is_required, price, sort) values
  ('D1', 9,  '비슷한 작업 포트폴리오', '비슷한 제품의 디자인 작업 예시를 보여 줄 수 있나요?', 'choice', true, 0, 10),
  ('D2', 9,  '원본·인쇄용 파일 제공', '원본 파일과 인쇄용 파일(칼선 포함)을 넘겨 주나요?', 'choice', true, 0, 11),
  ('S1', 10, '비슷한 작업 포트폴리오', '비슷한 제품의 촬영·상세페이지 예시를 보여 줄 수 있나요?', 'choice', true, 0, 10),
  ('S2', 10, '판매 채널 규격 대응', '판매 채널별 이미지 규격에 맞춰 줄 수 있나요?', 'choice', true, 0, 11),
  ('A1', 11, '대행 실적', '같은 분야의 신고·인증을 대행한 적이 있나요?', 'choice', true, 0, 10),
  ('A2', 11, '진행 기간 안내', '접수부터 완료까지 기간을 안내해 줄 수 있나요?', 'choice', true, 0, 11),
  ('W1', 8,  '보관 형태', '상온·냉장·냉동 중 요청 제품의 보관이 가능한가요?', 'choice', true, 0, 10),
  ('W2', 8,  '판매 채널 주문 연동', '9단계에서 고른 판매 채널의 주문을 연동해 출고할 수 있나요?', 'choice', true, 0, 11)
on conflict (code) do nothing;

-- 조건값 (각 5,000원)
insert into checklist_items (major_id, label, sort)
select 9, x, n from unnest(array['수정 3회 이상','AI 시안 다듬기','3D 목업 이미지','상표 출원 상담 연계','급행 (1주 이내)']) with ordinality as t(x, n);
insert into checklist_items (major_id, label, sort)
select 10, x, n from unnest(array['연출 촬영 (모델·소품)','영문 상세페이지','쇼츠·릴스 영상','썸네일 여러 버전','원본 사진 제공']) with ordinality as t(x, n);
insert into checklist_items (major_id, label, sort)
select 11, x, n from unnest(array['시험성적서 발급 대행','표시사항 디자인 검수','수출용 서류']) with ordinality as t(x, n);
insert into checklist_items (major_id, label, sort)
select 8, x, n from unnest(array['냉장·냉동 보관','당일 출고','선물 포장·키팅','쿠팡 로켓그로스 입고 대행','해외 배송']) with ordinality as t(x, n);
update checklist_items set question = label || ' 가능한가요?' where question is null;

-- 공정 (제작 파트너 가입 시 선택)
insert into processes (major_id, name)
select 9, x from unnest(array['패키지 디자인','칼선 작업','일러스트','로고 디자인','라벨 디자인']) x;
insert into processes (major_id, name)
select 10, x from unnest(array['누끼 촬영','연출 촬영','상세페이지 디자인','카피라이팅','영상 촬영·편집']) x;
insert into processes (major_id, name)
select 11, x from unnest(array['식품 표시 검토','품목제조보고 대행','KC 인증 대행','화장품 표시 검토','생활화학제품 신고','사료 성분 등록']) x;
insert into processes (major_id, name)
select 8, x from unnest(array['상온 보관','냉장 보관','택배 출고','주문 연동','입고 검수','키팅·합포장']) x;

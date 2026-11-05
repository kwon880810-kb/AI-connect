-- 권한 규칙 시험. 각 사용자로 로그인한 것처럼 바꿔 가며 보이는 것/안 보이는 것을 확인합니다.
\set QUIET on
\pset tuples_only on
\pset format unaligned

create or replace function t(ok boolean, msg text) returns text language plpgsql as $$
begin
  if ok is not true then raise exception 'FAIL: %', msg; end if;
  return 'PASS  ' || msg;
end $$;
grant execute on function t(boolean, text) to anon, authenticated;

-- ---------- 준비 (DB 소유자 권한) ----------
insert into auth.users values
 ('00000000-0000-0000-0000-00000000000a'), ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d2'),
 ('00000000-0000-0000-0000-0000000000b1'), ('00000000-0000-0000-0000-0000000000b2'), ('00000000-0000-0000-0000-0000000000b3');
insert into profiles (id, role, name, phone, company) values
 ('00000000-0000-0000-0000-00000000000a', 'admin', '관리자', null, null),
 ('00000000-0000-0000-0000-0000000000d1', 'demander', '홍길동', '010-1111-1111', '멍멍상회'),
 ('00000000-0000-0000-0000-0000000000d2', 'demander', '김철수', '010-2222-2222', '냥냥몰'),
 ('00000000-0000-0000-0000-0000000000b1', 'supplier', '김실장', '010-3333-3333', '가나식품'),
 ('00000000-0000-0000-0000-0000000000b2', 'supplier', '이팀장', '010-4444-4444', '다라푸드'),
 ('00000000-0000-0000-0000-0000000000b3', 'supplier', '미인증', '010-5555-5555', '미인증상사');
insert into suppliers (id, biz_no, biz_verified_at, company_name, contact_phone, region_sido, intro) values
 ('00000000-0000-0000-0000-0000000000b1', '1111111111', now(), '가나식품', '010-3333-3333', '경기', '져키 전문'),
 ('00000000-0000-0000-0000-0000000000b2', '2222222222', now(), '다라푸드', '010-4444-4444', '충북', '펫 간식 OEM'),
 ('00000000-0000-0000-0000-0000000000b3', '3333333333', null,  '미인증상사', '010-5555-5555', '서울', null);
insert into supplier_categories values ('00000000-0000-0000-0000-0000000000b1', 2), ('00000000-0000-0000-0000-0000000000b2', 2);

\echo '--- 수요자 D1: 의뢰 작성'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
insert into requests (id, demander_id, major_id, minor_id, title, qty_min, qty_max, price_min, price_max, due_min_days, due_max_days)
values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000d1', 2, 201, '강아지 져키 파우치', 500, 1000, 600, 800, 28, 42);
insert into request_items select '11111111-1111-1111-1111-111111111111', id, price from checklist_items where code = 'L201';
insert into request_files (request_id, path, is_image, visibility, sort) values
 ('11111111-1111-1111-1111-111111111111', 'req/1/ref.jpg', true, 'all', 1),
 ('11111111-1111-1111-1111-111111111111', 'req/1/design.ai', false, 'selected', 2);
select t((select code from requests) like 'R%-0001', '의뢰번호 자동 발급');
do $$ begin
  update requests set status = 'open' where id = '11111111-1111-1111-1111-111111111111';
  if (select status from requests where id = '11111111-1111-1111-1111-111111111111') <> 'draft' then raise exception 'SHOULD_FAIL'; end if;
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 수요자가 결제 없이 공개로 바꿈'; end if; end $$;
select t((select status from requests where id = '11111111-1111-1111-1111-111111111111') = 'draft', '수요자는 결제 없이 상태를 바꿀 수 없음');
select t(quote_amount('open', 3, array(select item_id from request_items)) = 50000 + 20000 + 5000, '일반 의뢰 금액: 착수금 + 업체 1곳 추가 + 조건값 1개');
select t(quote_amount('direct', 2, array(select item_id from request_items)) = 25000 + 5000, '지정 의뢰 금액: 착수금 절반 + 조건값 그대로');
reset role;

-- 결제 완료 처리 (서버)
update requests set status = 'open', paid_at = now(), amount_total = 55000, respond_until = now() + interval '48 hours'
 where id = '11111111-1111-1111-1111-111111111111';

\echo '--- 비회원'
set role anon; select from set_config('request.jwt.claim.sub', '', false);
select t((select count(*) from requests) = 0, '비회원은 의뢰를 볼 수 없음');
do $$ begin
  perform 1 from supplier_request_feed(); raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 비회원이 의뢰 피드에 접근함'; end if; end $$;
select t(true, '비회원은 의뢰 피드 접근 자체가 거부됨');
select t((select open_count from public_request_counts() where major_id = 2) = 1, '비회원도 분야별 진행 건수는 봄 (반려동물 1건)');
select t((select count(*) from supplier_directory()) = 2, '공급사 둘러보기: 인증된 공급사 2곳만');
select t((select count(*) from suppliers) = 0, '비회원은 공급사 업체명·연락처를 볼 수 없음');
reset role;
\echo '    (둘러보기 결과에는 업체명·연락처·신뢰도 칸이 없음:)'
select string_agg(column_name, ', ') from (select unnest(array['supplier_key','region_sido','intro','categories','processes','verified_licenses','response_count'])) c(column_name);

\echo '--- 미인증 공급자 B3'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
select t((select count(*) from supplier_request_feed()) = 0, '사업자 확인 전 공급자는 의뢰를 못 봄');
reset role;

\echo '--- 공급자 B1: 의뢰 보기와 응답'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t((select count(*) from supplier_request_feed()) = 1, '인증 공급자는 의뢰 피드에서 의뢰를 봄');
select t((select thumbnail_path from supplier_request_feed()) = 'req/1/ref.jpg', '목록 썸네일은 모두 공개 이미지 1개');
select t((select count(*) from requests) = 0, '공급자는 requests 원본(수요자 ID 포함)을 직접 못 봄');
select t((select count(*) from profiles where id = '00000000-0000-0000-0000-0000000000d1') = 0, '공급자는 수요자 회원 정보를 못 봄');
select t((select count(*) from request_files) = 1, '선정 전에는 모두 공개 파일만 보임');
insert into request_views (request_id, supplier_id) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000b1');
insert into responses (id, request_id, supplier_id, qty_min, qty_max, price_min, price_max, due_min_days, due_max_days, license_pledge, fit_pct, memo)
values ('22222222-2222-2222-2222-222222222221', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000b1',
        500, 3000, 650, 750, 30, 40, true, 999, '샘플 1주');
insert into response_answers values ('22222222-2222-2222-2222-222222222221', (select id from checklist_items where code = 'L201'), 'O', '등록증 있음');
select t((select fit_pct from responses) = 100, '적합도는 자동 계산 (공급자가 넣은 999 무시)');
do $$ begin
  update responses set status = 'selected' where id = '22222222-2222-2222-2222-222222222221';
  raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 공급자가 스스로 선정됨'; end if; end $$;
select t(true, '공급자는 스스로 선정 상태로 바꿀 수 없음');
select t(trust_score_of('00000000-0000-0000-0000-0000000000b1') = 100, '공급자는 자기 신뢰도를 봄');
select t(trust_score_of('00000000-0000-0000-0000-0000000000b2') is null, '공급자는 다른 공급자의 신뢰도를 못 봄');
update suppliers set is_restricted = false, biz_no = '9999999999', biz_verified_at = null, intro = '져키·트릿 전문' where id = auth.uid();
select t((select biz_no = '1111111111' and biz_verified_at is not null and intro = '져키·트릿 전문' from suppliers where id = auth.uid()),
         '공급자는 소개는 고칠 수 있지만 사업자번호·인증 상태는 못 바꿈');
reset role;

\echo '--- 공급자 B2: 범위가 맞지 않는 응답'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
insert into request_views (request_id, supplier_id) values ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000b2');
insert into responses (id, request_id, supplier_id, qty_min, qty_max, price_min, price_max, due_min_days, due_max_days, license_pledge)
values ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-0000000000b2',
        3000, 5000, 500, 700, 30, 40, true);
select t((select has_required_x from responses) = true, '수량이 ±20% 밖이면 필수 ✕ (선정 제외 대상)');
select t((select count(*) from responses) = 1, '공급자는 자기 응답만 봄');
reset role;
select t((select count(*) from rank_responses('11111111-1111-1111-1111-111111111111')) = 0, '관리자가 아니면 순위 함수 결과 없음 (DB 소유자도 auth 없음)');

\echo '--- 수요자 D1: 선정 전'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t((select count(*) from responses) = 0, '수요자는 리스트 전달 전에는 응답을 못 봄');
select t((select views = 2 and responses = 2 and response_rate = 100 from request_stats('11111111-1111-1111-1111-111111111111')), '수요자는 열람·응답 수와 응답률을 봄');
select t(trust_score_of('00000000-0000-0000-0000-0000000000b1') is null, '수요자는 신뢰도를 못 봄');
select t((select count(*) from suppliers) = 0, '수요자는 선정 전 공급자 연락처를 못 봄');
reset role;

\echo '--- 관리자: 순위 확인 후 선정, 리스트 전달'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select t((select string_agg(supplier_label || ':' || has_required_x, ',') from rank_responses('11111111-1111-1111-1111-111111111111'))
         = '가나식품:false,다라푸드:true', '관리자 순위: 필수 ✕ 업체는 뒤로');
update responses set status = 'selected', selected_at = now() where id = '22222222-2222-2222-2222-222222222221';
update responses set status = 'not_selected' where id = '22222222-2222-2222-2222-222222222222';
update requests set status = 'delivered', delivered_at = now(), verify_until = now() + interval '7 days'
 where id = '11111111-1111-1111-1111-111111111111';
reset role;

\echo '--- 수요자 D1: 리스트 전달 후'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t((select count(*) from responses) = 1, '수요자는 선정된 응답만 봄');
select t((select string_agg(company_name || '/' || contact_phone, ',') from suppliers) = '가나식품/010-3333-3333', '선정된 공급자의 연락처만 공개');
select t((select count(*) from response_answers) = 1, '선정 응답의 체크 결과를 봄');
select t((select count(*) from score_events) = 0, '수요자는 점수 기록을 못 봄');
insert into disputes (id, request_id, response_id, kind, claim)
values ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222221', 'required', 'MOQ 3,000개부터라고 함');
select t((select count(*) from disputes) = 1, '수요자는 검증기간 안에 이의신청 가능');
do $$ begin
  insert into disputes (request_id, response_id, kind, claim)
  values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'required', '선정 안 된 업체');
  raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 선정되지 않은 응답에 이의신청됨'; end if; end $$;
select t(true, '선정되지 않은 업체에는 이의신청 불가');
insert into contracts (request_id, response_id, demander_id, supplier_id, body)
values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222221', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', '{"품목":"져키"}');
do $$ begin
  update contracts set status = 'signed', demander_signed_at = now();
  if exists (select 1 from contracts where status = 'signed') then raise exception 'SHOULD_FAIL'; end if;
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 본인인증 없이 서명 처리됨'; end if; end $$;
select t(true, '계약서 서명 완료는 본인인증 서버만 처리');
reset role;

\echo '--- 공급자 B1: 선정 후'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t((select count(*) from request_files) = 2, '선정되면 선정사 공개 파일도 보임');
select t((select count(*) from disputes) = 1, '공급자는 자기 건 이의신청을 봄');
select t((select count(*) from contracts) = 1, '공급자는 자기 계약서를 봄');
select t((select count(*) from profiles where id = '00000000-0000-0000-0000-0000000000d1') = 0, '선정되어도 수요자 회원 정보는 여전히 가림');
do $$ begin
  perform submit_opinion('33333333-3333-3333-3333-333333333333', '의견');
  raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 요청 전 의견서 제출됨'; end if; end $$;
select t(true, '의견서는 운영자가 요청한 뒤에만 제출');
reset role;
update disputes set status = 'awaiting_opinion', opinion_due = now() + interval '3 days';
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select submit_opinion('33333333-3333-3333-3333-333333333333', '500개부터 가능, 3,000개는 오해');
select t((select opinion is not null from disputes), '의견서 제출');
reset role;

\echo '--- 공급자 B2, 수요자 D2: 남의 건'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select t((select count(*) from disputes) = 0, '다른 공급자는 이의신청을 못 봄');
select t((select count(*) from contracts) = 0, '다른 공급자는 계약서를 못 봄');
select t((select count(*) from request_files where visibility = 'selected') = 0, '미선정 공급자는 선정사 공개 파일을 못 봄');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
select t((select count(*) from requests) = 0 and (select count(*) from contracts) = 0 and (select count(*) from suppliers) = 0, '다른 수요자는 아무것도 못 봄');
reset role;

\echo '--- 지정 의뢰'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
insert into requests (id, demander_id, kind, major_id, title, qty_min, qty_max) values ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-0000000000d2', 'direct', 2, '고양이 스크래쳐', 300, 500);
insert into request_targets values ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-0000000000b2');
reset role;
update requests set status = 'open', paid_at = now() where id = '44444444-4444-4444-4444-444444444444';
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t((select count(*) from supplier_request_feed() where kind = 'direct') = 0, '지정되지 않은 공급자는 지정 의뢰를 못 봄');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select t((select count(*) from supplier_request_feed() where kind = 'direct') = 1, '지정된 공급자는 지정 의뢰를 봄');
reset role;

\echo '--- 신뢰도 점수'
insert into score_events (supplier_id, delta, reason) values ('00000000-0000-0000-0000-0000000000b1', -10, 'required_mismatch');
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t(trust_score_of(auth.uid()) = 90 and (select count(*) from score_events) = 1, '공급자는 차감된 자기 점수(90)와 사유를 봄');
reset role;

\echo ''
\echo '모든 시험 통과'

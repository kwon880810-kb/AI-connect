-- 출시 프로젝트·요금·쿠폰 시험 (10_rls_test.sql 다음에 실행, 같은 사용자 사용)
\set QUIET on
\pset tuples_only on
\pset format unaligned

\echo '--- 쿠폰: 휴대폰 번호당 1장'
insert into auth.users (id, email, raw_user_meta_data) values
 ('00000000-0000-0000-0000-0000000000d3', 'd3@t.kr', '{"role":"demander","name":"쿠폰A","phone":"010-7777-8888"}'),
 ('00000000-0000-0000-0000-0000000000d4', 'd4@t.kr', '{"role":"demander","name":"쿠폰B","phone":"01077778888"}');
select t((select count(*) from coupons where user_id = '00000000-0000-0000-0000-0000000000d3') = 1, '신규 수요자에게 쿠폰 1장 지급');
select t((select count(*) from coupons where user_id = '00000000-0000-0000-0000-0000000000d4') = 0, '같은 휴대폰 번호로 다시 가입하면 쿠폰 없음');

\echo '--- 첫 파트너 찾기: 쿠폰으로 접수비 0원, 착수금은 리스트 받을 때'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', false);
insert into projects (id, demander_id, title, product_major) values ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-0000000000d3', '강아지 얼굴 져키', 2);
select t((select fee_type = 'first' and intake = 0 and deposit = 55000 and has_coupon from preview_fee('55555555-5555-5555-5555-555555555555', 2, array(select id from checklist_items where code = 'L201'), '{}')),
         '미리보기: 첫 파트너 찾기, 쿠폰으로 접수비 0원, 착수금 55,000원');
insert into requests (id, demander_id, project_id, stage, phase, major_id, title, qty_min, qty_max, due_min_days, due_max_days, fee_type, intake_amount, amount_total)
values ('66666666-6666-6666-6666-666666666661', '00000000-0000-0000-0000-0000000000d3', '55555555-5555-5555-5555-555555555555', 2, '1', 2, '강아지 얼굴 져키', 500, 1000, 28, 42, 'followup', 0, 0);
insert into request_items select '66666666-6666-6666-6666-666666666661', id, price from checklist_items where code = 'L201';
update requests set submitted_at = now(), amount_total = 1 where id = '66666666-6666-6666-6666-666666666661';
select t((select fee_type = 'first' and intake_amount = 0 and deposit_amount = 55000 and amount_total = 0 and coupon_id is not null
          from requests where id = '66666666-6666-6666-6666-666666666661'), '제출: 서버가 요금 확정 (회원이 넣은 요금 칸은 무시)');
select t((select status = 'active' from projects where id = '55555555-5555-5555-5555-555555555555'), '제출하면 프로젝트가 진행 중으로');
select t((select used_at is not null from coupons where user_id = auth.uid()), '쿠폰 사용 처리');
reset role;

\echo '--- 다른 사람 프로젝트에는 의뢰를 넣을 수 없음, 공급자는 프로젝트를 못 봄'
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
do $$ begin
  insert into requests (demander_id, project_id, major_id, title) values ('00000000-0000-0000-0000-0000000000d1', '55555555-5555-5555-5555-555555555555', 2, '남의 프로젝트');
  raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 남의 프로젝트에 의뢰가 들어감'; end if; end $$;
select t(true, '다른 수요자는 남의 프로젝트에 의뢰를 넣을 수 없음');
select t((select count(*) from projects) = 0, '다른 수요자는 남의 프로젝트를 못 봄');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t((select count(*) from projects) = 0 and (select count(*) from coupons) = 0, '공급자는 프로젝트·쿠폰을 못 봄');
reset role;

\echo '--- 공개 → 응답 → 선정: 착수금 입금 대기 (연락처 비공개, 미리보기만)'
update requests set status = 'open', paid_at = now() where id = '66666666-6666-6666-6666-666666666661';
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select t((select stage = 2 and phase = '1' from supplier_request_feed() where id = '66666666-6666-6666-6666-666666666661'), '공급자 피드에 단계·차수 표시');
insert into responses (id, request_id, supplier_id, qty_min, qty_max, price_min, due_min_days, license_pledge)
values ('77777777-7777-7777-7777-777777777771', '66666666-6666-6666-6666-666666666661', '00000000-0000-0000-0000-0000000000b1', 500, 2000, 700, 30, true);
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select admin_deliver('66666666-6666-6666-6666-666666666661', array['77777777-7777-7777-7777-777777777771'::uuid]);
select t((select status::text = 'awaiting_deposit' from requests where id = '66666666-6666-6666-6666-666666666661'), '첫 리스트는 착수금 입금 대기로');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', false);
select t((select count(*) from responses) = 0 and (select count(*) from suppliers) = 0, '착수금 전에는 업체명·연락처 비공개');
select t((select label = '파트너 A' and region_sido = '경기' from request_preview('66666666-6666-6666-6666-666666666661')), '착수금 전 미리보기: 업체명 없이 지역·체크 결과');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
select admin_confirm_deposit('66666666-6666-6666-6666-666666666661');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', false);
select t((select count(*) from suppliers) = 1, '착수금 확인 후 연락처 공개');
select t((select payments.amount = 55000 from payments where request_id = '66666666-6666-6666-6666-666666666661'), '착수금 결제 기록 55,000원');

\echo '--- 이어하기: 새 파트너 찾기 9,900원(+추가요금), 기존 파트너 문의 0원'
select t((select fee_type = 'continue' and intake = 9900 + 20000 and deposit = 0 from preview_fee('55555555-5555-5555-5555-555555555555', 3, '{}', '{}')),
         '이어하기 미리보기: 9,900원 + 업체 추가 20,000원, 착수금 없음');
select t((select fee_type = 'followup' and intake = 0 from preview_fee('55555555-5555-5555-5555-555555555555', 1, '{}', array['00000000-0000-0000-0000-0000000000b1'::uuid])),
         '기존 파트너에게만 문의하면 0원');
select t((select string_agg(company_name, ',') = '가나식품' from my_project_partners('55555555-5555-5555-5555-555555555555')), '내 프로젝트의 기존 파트너 목록');
insert into requests (id, demander_id, project_id, kind, stage, phase, major_id, title)
values ('66666666-6666-6666-6666-666666666662', '00000000-0000-0000-0000-0000000000d3', '55555555-5555-5555-5555-555555555555', 'direct', 5, '2', 3, '포장재도 가능한지 문의');
insert into request_targets values ('66666666-6666-6666-6666-666666666662', '00000000-0000-0000-0000-0000000000b1');
update requests set submitted_at = now() where id = '66666666-6666-6666-6666-666666666662';
select t((select fee_type = 'followup' and intake_amount = 0 and deposit_amount = 0 from requests where id = '66666666-6666-6666-6666-666666666662'), '기존 파트너 문의 제출: 0원');
insert into requests (id, demander_id, project_id, stage, phase, major_id, title, supplier_count)
values ('66666666-6666-6666-6666-666666666663', '00000000-0000-0000-0000-0000000000d3', '55555555-5555-5555-5555-555555555555', 4, '2', 3, '파우치 디자인', 2);
update requests set submitted_at = now() where id = '66666666-6666-6666-6666-666666666663';
select t((select fee_type = 'continue' and intake_amount = 9900 and deposit_amount = 0 from requests where id = '66666666-6666-6666-6666-666666666663'), '이어하기 제출: 9,900원, 착수금 없음');
update projects set status = 'closed' where id = '55555555-5555-5555-5555-555555555555';
select t((select status = 'closed' and closed_at is not null from projects where id = '55555555-5555-5555-5555-555555555555'), '여기서 마치기 (프로젝트 종료)');
update projects set status = 'active' where id = '55555555-5555-5555-5555-555555555555';
select t((select status = 'active' and closed_at is null from projects where id = '55555555-5555-5555-5555-555555555555'), '종료한 프로젝트 다시 이어가기');
reset role;

\echo ''
\echo '프로젝트 시험 통과'

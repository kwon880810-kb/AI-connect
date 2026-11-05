-- 비회원사 목록·지정 의뢰 제한·회원가입 자동 연결 시험 (20_project_test.sql 다음)
\set QUIET on
\pset tuples_only on
\pset format unaligned

\echo '--- 비회원사 등록 (관리자)'
insert into offline_suppliers (company_name, biz_no, region_sido, category_ids, process_names, intro, source, source_name, source_date, active_checked_at, contact_phone)
values ('공공식품', '5555555555', '경기', '{1,104}', '{굽기}', '구움과자 소량 생산', 'public', '식약처 식품제조가공업 인허가 정보', '2026-11-05', now(), '031-000-0000'),
       ('거절공장', '6666666666', '충남', '{1}', '{}', null, 'public', '식약처 식품제조가공업 인허가 정보', '2026-11-05', null, null),
       ('인맥디자인', '7777777777', '서울', '{9,901}', '{패키지 디자인}', '패키지 디자인 10년', 'network', null, null, now(), '010-0000-0000');
update offline_suppliers set consent = 'refused' where biz_no = '6666666666';

set role anon; select from set_config('request.jwt.claim.sub', '', false);
select t((select count(*) from supplier_directory() where not is_member) = 2, '둘러보기: 공개 중인 비회원사 2곳 (목록 제외 요청한 곳은 숨김)');
select t((select operator_verified and source_label = '공개 정보 기반' and 104 = any(category_ids) from supplier_directory() where intro = '구움과자 소량 생산'), '비회원사: 활동 확인·출처·분류 표시');
select t((select members = 2 and public_listed = 1 and network_listed = 1 from supplier_counts()), '회원사·공개 정보·운영사 네트워크 숫자를 나눠서');
select t((select count(*) from offline_suppliers) = 0, '비회원사 업체명·연락처 원본은 비회원이 못 봄');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
select t((select count(*) from offline_suppliers) = 0, '수요자도 비회원사 원본(연락처)은 못 봄');
reset role;

\echo '--- 지정 의뢰 꺼짐'
update pricing set value = 0 where key = 'direct_request_enabled';
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
insert into requests (id, demander_id, kind, major_id, title) values ('88888888-8888-8888-8888-888888888881', '00000000-0000-0000-0000-0000000000d2', 'direct', 2, '지정 시도');
do $$ begin
  insert into request_targets values ('88888888-8888-8888-8888-888888888881', '00000000-0000-0000-0000-0000000000b2');
  raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 지정 의뢰가 꺼져 있는데 지정됨'; end if; end $$;
select t(true, '지정 의뢰가 꺼져 있으면 회원사도 지정할 수 없음');
do $$ begin
  insert into request_targets values ('88888888-8888-8888-8888-888888888881', (select id from offline_suppliers limit 1));
  raise exception 'SHOULD_FAIL';
exception when others then if sqlerrm = 'SHOULD_FAIL' then raise exception 'FAIL: 비회원사가 지정됨'; end if; end $$;
select t(true, '비회원사는 지정 대상이 될 수 없음');
reset role;
set role authenticated; select from set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d3', false);
insert into requests (id, demander_id, project_id, kind, stage, phase, major_id, title)
values ('88888888-8888-8888-8888-888888888882', '00000000-0000-0000-0000-0000000000d3', '55555555-5555-5555-5555-555555555555', 'direct', 8, '4', 2, '물류도 가능한지 문의');
insert into request_targets values ('88888888-8888-8888-8888-888888888882', '00000000-0000-0000-0000-0000000000b1');
select t((select count(*) from request_targets where request_id = '88888888-8888-8888-8888-888888888882') = 1, '지정 의뢰가 꺼져 있어도 기존 파트너 문의는 가능');
reset role;

\echo '--- 같은 사업자번호로 가입하면 회원사로 연결'
insert into auth.users (id, email, raw_user_meta_data) values ('00000000-0000-0000-0000-0000000000b9', 'gg@t.kr', '{"role":"supplier","name":"공공"}');
insert into suppliers (id, biz_no, company_name, region_sido) values ('00000000-0000-0000-0000-0000000000b9', '5555555555', '공공식품', '경기');
select t((select linked_supplier_id = '00000000-0000-0000-0000-0000000000b9' and not listed and consent = 'agreed' from offline_suppliers where biz_no = '5555555555'),
         '가입하면 비회원사 기록이 회원사와 연결되고 목록에서는 중복 표시 안 함');

\echo ''
\echo '비회원사 시험 통과'

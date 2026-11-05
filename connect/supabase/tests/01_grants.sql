-- Supabase 기본 권한과 동일: 테이블 권한은 열어 두고 RLS로 막음
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
-- Supabase 기본: 새 함수는 PUBLIC 실행 가능. 0003에서 회수한 것을 시험에서도 유지
revoke execute on function supplier_request_feed() from anon;

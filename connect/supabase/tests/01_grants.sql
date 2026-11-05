-- Supabase 기본 권한과 동일: 테이블 권한은 열어 두고 RLS로 막음
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to anon, authenticated;
grant usage, select on all sequences in schema public to anon, authenticated;
revoke all on supplier_request_feed from anon;

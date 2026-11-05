-- 화면 시험용 관리자 계정 (admin@test.kr / password1). 가짜 Supabase 서버의 비밀번호 방식에 맞춤
insert into auth.users (id, email, encrypted_password, raw_user_meta_data)
values ('aaaaaaaa-0000-0000-0000-000000000001', 'admin@test.kr', encode(sha256('mock:password1'::bytea), 'hex'), '{"name":"관리자"}');
update profiles set role = 'admin' where id = 'aaaaaaaa-0000-0000-0000-000000000001';

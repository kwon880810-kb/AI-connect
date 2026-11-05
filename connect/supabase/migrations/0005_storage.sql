-- 첨부 파일 저장소 (Supabase Storage). 로컬 시험에는 storage 스키마가 없어 적용하지 않음
-- 경로 규칙: <의뢰 id>/<번호>-<파일명>
-- 열람 권한은 request_files 표의 권한 규칙과 같음 (모두 공개 / 선정사 공개)

insert into storage.buckets (id, name, public, file_size_limit)
values ('request-files', 'request-files', false, 10485760)
on conflict (id) do nothing;

-- 올리기: 자기 의뢰 폴더에만 (관리자는 전체)
create policy "request files upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'request-files' and (public.is_admin() or public.owns_request(((storage.foldername(name))[1])::uuid)));

-- 보기: request_files에서 볼 수 있는 파일만 (그 표의 RLS가 그대로 적용됨)
create policy "request files read" on storage.objects for select to authenticated
  using (bucket_id = 'request-files' and (public.is_admin() or exists (select 1 from public.request_files f where f.path = storage.objects.name)));

-- 지우기: 자기 의뢰 파일 (관리자는 전체)
create policy "request files delete" on storage.objects for delete to authenticated
  using (bucket_id = 'request-files' and (public.is_admin() or public.owns_request(((storage.foldername(name))[1])::uuid)));

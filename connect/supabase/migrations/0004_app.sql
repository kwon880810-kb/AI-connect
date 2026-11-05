-- 화면 작업에 필요한 기능
-- 1. 회원가입 시 회원 정보(profiles) 자동 생성 (이메일 인증을 켜도 동작)
-- 2. 의뢰 제출: 금액은 서버가 계산, 제출 후에는 수요자가 내용을 바꿀 수 없음
-- 3. 관리자 처리: 입금 확인(PG 연동 전), 리스트 전달, 확정

-- ---------- 1. 회원가입 ----------
create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  m jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
  r user_role := case when m->>'role' = 'supplier' then 'supplier'::user_role else 'demander'::user_role end;
begin
  insert into profiles (id, role, name, phone, email, company)
  values (new.id, r, coalesce(nullif(m->>'name', ''), nullif(split_part(new.email, '@', 1), ''), '회원'), m->>'phone', new.email, m->>'company')
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
revoke execute on function handle_new_user() from public, anon, authenticated;

-- ---------- 2. 의뢰 제출 ----------
alter table requests add column if not exists submitted_at timestamptz;

-- 수요자가 고칠 수 있는 의뢰 = 본인 것 + 작성 중(제출 전)
create or replace function request_editable(p_request uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from requests where id = p_request and demander_id = auth.uid() and status = 'draft' and submitted_at is null)
$$;
revoke execute on function request_editable(uuid) from public, anon;
grant execute on function request_editable(uuid) to authenticated;

drop policy owner_update_draft on requests;
create policy owner_update_draft on requests for update to authenticated
  using (demander_id = auth.uid() and status = 'draft' and submitted_at is null)
  with check (demander_id = auth.uid() and status = 'draft');

drop policy owner_all on request_items;
create policy owner_read on request_items for select to authenticated using (owns_request(request_id));
create policy owner_write on request_items for insert to authenticated with check (request_editable(request_id));
create policy owner_delete on request_items for delete to authenticated using (request_editable(request_id));

drop policy owner_all on request_targets;
create policy owner_read on request_targets for select to authenticated using (owns_request(request_id));
create policy owner_write on request_targets for insert to authenticated with check (request_editable(request_id));
create policy owner_delete on request_targets for delete to authenticated using (request_editable(request_id));

-- 제출 순간 금액·업체 수를 서버가 확정. 회원이 넣은 금액·결제 칸은 무시
create or replace function guard_requests() returns trigger
language plpgsql set search_path = public as $$
begin
  if not is_privileged() then
    if tg_op = 'INSERT' then
      new.status := 'draft'; new.amount_total := null; new.paid_at := null; new.respond_until := null;
      new.delivered_at := null; new.verify_until := null; new.confirmed_at := null; new.submitted_at := null; new.code := null;
    else
      new.demander_id := old.demander_id; new.code := old.code; new.status := old.status;
      new.paid_at := old.paid_at; new.respond_until := old.respond_until; new.delivered_at := old.delivered_at;
      new.verify_until := old.verify_until; new.confirmed_at := old.confirmed_at;
      if new.submitted_at is not null and old.submitted_at is null then
        new.submitted_at := now();
        if new.kind = 'direct' then
          new.supplier_count := greatest(1, (select count(*) from request_targets where request_id = new.id));
        end if;
        new.amount_total := quote_amount(new.kind, new.supplier_count,
                                         array(select item_id from request_items where request_id = new.id));
      else
        new.amount_total := old.amount_total;
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger trg_guard_requests before insert or update on requests for each row execute function guard_requests();
-- 의뢰번호 트리거(trg_request_code)는 이름순으로 이 트리거 뒤에 실행되어 번호를 붙임

-- ---------- 3. 관리자 처리 ----------
-- 입금 확인 (PG 연동 전에는 계좌이체 확인 후 관리자가 누름)
create or replace function admin_confirm_payment(p_request uuid, p_pg text default 'bank', p_tid text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r requests;
begin
  if not is_admin() then raise exception '관리자만 할 수 있습니다'; end if;
  select * into r from requests where id = p_request for update;
  if r.status <> 'draft' or r.submitted_at is null then raise exception '제출된 결제 대기 의뢰가 아닙니다'; end if;
  update requests set status = 'open', paid_at = now(),
         respond_until = now() + make_interval(hours => price_of('respond_hours'))
   where id = p_request;
  insert into payments (request_id, pg, pg_tid, amount) values (p_request, p_pg, p_tid, r.amount_total);
  -- 지정 의뢰: 지정 공급사 응답칸을 미리 만들어 둠 (응답 대기)
  insert into responses (request_id, supplier_id, status)
  select p_request, t.supplier_id, 'invited' from request_targets t where t.request_id = p_request and r.kind = 'direct'
  on conflict do nothing;
end $$;

-- 리스트 전달: 고른 응답은 선정, 나머지는 미선정
create or replace function admin_deliver(p_request uuid, p_selected uuid[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception '관리자만 할 수 있습니다'; end if;
  if coalesce(array_length(p_selected, 1), 0) = 0 then raise exception '선정할 업체를 고르세요'; end if;
  update responses set status = case when id = any(p_selected) then 'selected'::response_status else 'not_selected'::response_status end,
                       selected_at = case when id = any(p_selected) then now() end
   where request_id = p_request and status in ('submitted', 'selected', 'not_selected');
  update requests set status = 'delivered', delivered_at = now(),
         verify_until = now() + make_interval(days => price_of('verify_days'))
   where id = p_request and status in ('open', 'selecting');
  if not found then raise exception '전달할 수 있는 상태가 아닙니다'; end if;
end $$;

-- 확정: 검증기간이 끝났고 처리 중인 이의가 없을 때. 문제없이 통과한 공급자는 신뢰도 +1
create or replace function admin_confirm_request(p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception '관리자만 할 수 있습니다'; end if;
  if exists (select 1 from disputes where request_id = p_request and status in ('open', 'awaiting_opinion')) then
    raise exception '처리 중인 이의신청이 있습니다';
  end if;
  update requests set status = 'confirmed', confirmed_at = now() where id = p_request and status in ('delivered', 'disputed');
  if not found then raise exception '확정할 수 있는 상태가 아닙니다'; end if;
  insert into score_events (supplier_id, delta, reason, request_id)
  select x.supplier_id, 1, 'clean_pass', p_request from responses x
   where x.request_id = p_request and x.status = 'selected' and x.supplier_id is not null
     and not exists (select 1 from disputes d where d.response_id = x.id and d.supplier_fault)
     and (select coalesce(sum(delta), 0) from score_events e where e.supplier_id = x.supplier_id) < 0;
end $$;

-- 이의신청이 들어오면 의뢰 상태를 '이의 처리 중'으로
create or replace function on_dispute_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update requests set status = 'disputed' where id = new.request_id and status = 'delivered';
  return null;
end $$;
create trigger trg_dispute_created after insert on disputes for each row execute function on_dispute_created();
revoke execute on function on_dispute_created() from public, anon, authenticated;

revoke execute on function admin_confirm_payment(uuid, text, text), admin_deliver(uuid, uuid[]), admin_confirm_request(uuid) from public, anon;
grant execute on function admin_confirm_payment(uuid, text, text), admin_deliver(uuid, uuid[]), admin_confirm_request(uuid) to authenticated;

-- 작성 중(제출 전) 의뢰는 수요자가 지울 수 있음
create policy owner_delete_draft on requests for delete to authenticated using (request_editable(id));

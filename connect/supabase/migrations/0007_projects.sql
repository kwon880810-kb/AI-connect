-- =====================================================================
-- 출시 프로젝트 (출시프로젝트_설계.md)
--   총 프로젝트 1개 안에 차수(1차, 2차, 2-1차, 3차, 4차)와 단계(1~9)가 있고,
--   "파트너 찾기"를 고른 단계마다 의뢰(requests) 1건이 생깁니다.
--
-- 요금 (pricing 표에서 조정)
--   첫 파트너 찾기:  접수 시 접수비 9,900원(쿠폰이면 0원) → 리스트 받을 때 착수금 50,000원 + 추가 조건 + 업체 추가
--   이어하기:        접수 시 9,900원 + 추가 조건 + 업체 추가 (착수금 없음)
--   기존 파트너 문의: 0원 (이미 선정된 파트너에게만 보내는 지정 의뢰)
-- =====================================================================

-- ---------- 요금 항목 ----------
insert into pricing (key, value, note) values
  ('intake_fee',     9900, '첫 파트너 찾기 접수비 (공개 조건)'),
  ('continue_fee',   9900, '이어하기: 파트너 찾기 1건당'),
  ('coupon_amount', 10000, '초기 쿠폰 금액 (접수비에 적용)'),
  ('coupon_days',      30, '쿠폰 사용 기한 (가입 후 일)'),
  ('coupon_active',     1, '신규 가입자 쿠폰 지급 (1=지급, 0=중단)')
on conflict (key) do nothing;
update pricing set note = '착수금 (첫 리스트 받을 때, 업체 2곳 + 필수값)' where key = 'open_base';
update pricing set note = '업체 추가 1곳당 (착수금·이어하기 공통) [예시]' where key = 'open_extra_supplier';
delete from pricing where key in ('direct_base', 'direct_extra_supplier');   -- 지정 의뢰 할인 폐지

-- ---------- 총 프로젝트 ----------
create table projects (
  id             uuid primary key default gen_random_uuid(),
  demander_id    uuid not null references profiles(id) on delete cascade,
  title          text not null default '새 아이디어',
  idea_mode      text,                      -- text / sketch / ai
  idea_desc      text,
  product_major  int references categories(id),
  product_minor  int references categories(id),
  plan           jsonb not null default '{}',   -- 단계별 선택 (s2..s9), 차수별 제출 기록 (phases)
  draft          jsonb not null default '{}',   -- 작성 중인 화면 상태 (자동 저장)
  status         text not null default 'draft' check (status in ('draft', 'active', 'closed')),
  closed_at      timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index on projects (demander_id, updated_at desc);

alter table requests
  add column if not exists project_id      uuid references projects(id) on delete set null,
  add column if not exists stage           int,          -- 2 제품 생산, 4 디자인, 5 포장재, 6 인증 대행, 7 촬영·상세, 8 물류
  add column if not exists phase           text,         -- '1', '2', '2-1', '3', '4'
  add column if not exists context         text,         -- 파트너에게 보이는 프로젝트 요약 (예: 제품: 져키 / 포장: 파우치)
  add column if not exists fee_type        text,         -- first / continue / followup (제출 시 서버가 결정)
  add column if not exists intake_amount   int,          -- 접수 시 낼 금액
  add column if not exists deposit_amount  int,          -- 리스트 받을 때 낼 착수금 (첫 파트너 찾기만)
  add column if not exists deposit_paid_at timestamptz,
  add column if not exists coupon_id       uuid;
create index on requests (project_id);

-- ---------- 쿠폰 ----------
create table coupons (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references profiles(id) on delete cascade,
  phone_key        text,                       -- 숫자만 남긴 휴대폰 번호 (1인 1장 확인용)
  amount           int not null,
  expires_at       timestamptz not null,
  used_request_id  uuid references requests(id) on delete set null,
  used_at          timestamptz,
  created_at       timestamptz not null default now()
);
create unique index coupons_one_per_phone on coupons (phone_key) where phone_key is not null and phone_key <> '';
alter table requests add constraint requests_coupon_fk foreign key (coupon_id) references coupons(id) on delete set null;

-- 신규 수요자에게 쿠폰 지급 (지급 중일 때, 휴대폰 번호당 1장)
create or replace function issue_signup_coupon() returns trigger
language plpgsql security definer set search_path = public as $$
declare k text := regexp_replace(coalesce(new.phone, ''), '\D', '', 'g');
begin
  if new.role = 'demander' and coalesce(price_of('coupon_active'), 0) = 1 and length(k) >= 10
     and not exists (select 1 from coupons where phone_key = k) then
    insert into coupons (user_id, phone_key, amount, expires_at)
    values (new.id, k, price_of('coupon_amount'), now() + make_interval(days => price_of('coupon_days')));
  end if;
  return null;
end $$;
create trigger trg_signup_coupon after insert on profiles for each row execute function issue_signup_coupon();
revoke execute on function issue_signup_coupon() from public, anon, authenticated;

-- ---------- 권한 도우미 ----------
create or replace function owns_project(p_project uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from projects where id = p_project and demander_id = auth.uid())
$$;
revoke execute on function owns_project(uuid) from public, anon;
grant execute on function owns_project(uuid) to authenticated;

-- 이 프로젝트에서 이미 선정된 적 있는 파트너 (기존 파트너 문의 = 무료)
create or replace function project_partner_ids(p_project uuid) returns uuid[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct x.supplier_id), '{}')
  from responses x join requests r on r.id = x.request_id
  where r.project_id = p_project and x.status = 'selected' and x.supplier_id is not null
    and r.status in ('delivered', 'disputed', 'confirmed')
$$;
revoke execute on function project_partner_ids(uuid) from public, anon, authenticated;  -- 다른 서버 함수 안에서만 사용

-- 수요자용: 이 프로젝트의 기존 파트너 목록 (업체명·분야만, 이미 연락처를 받은 업체들)
create or replace function my_project_partners(p_project uuid)
returns table (supplier_id uuid, company_name text, region_sido text, stage int)
language sql stable security definer set search_path = public as $$
  select distinct on (x.supplier_id) x.supplier_id, s.company_name, s.region_sido, r.stage
  from responses x join requests r on r.id = x.request_id join suppliers s on s.id = x.supplier_id
  where r.project_id = p_project and owns_project(p_project) and x.status = 'selected'
    and r.status in ('delivered', 'disputed', 'confirmed')
  order by x.supplier_id, r.created_at
$$;
revoke execute on function my_project_partners(uuid) from public, anon;
grant execute on function my_project_partners(uuid) to authenticated;

-- ---------- 요금 계산 (제출 시) ----------
create or replace function request_fee(p_request uuid)
returns table (fee_type text, intake int, deposit int, coupon uuid)
language plpgsql stable security definer set search_path = public as $$
declare
  r requests; extra int; cond int; partners uuid[]; targets uuid[]; cp uuid;
begin
  select * into r from requests where id = p_request;
  extra := greatest(r.supplier_count - price_of('base_suppliers'), 0) * price_of('open_extra_supplier');
  cond  := coalesce((select sum(i.price) from request_items ri join checklist_items i on i.id = ri.item_id
                     where ri.request_id = r.id and not i.is_required), 0)::int;
  -- 기존 파트너에게만 보내는 지정 의뢰 → 무료
  if r.project_id is not null and r.kind = 'direct' then
    partners := project_partner_ids(r.project_id);
    targets  := array(select supplier_id from request_targets where request_id = r.id);
    if array_length(targets, 1) > 0 and targets <@ partners then
      return query select 'followup'::text, 0, 0, null::uuid; return;
    end if;
  end if;
  -- 프로젝트의 첫 파트너 찾기인가 (착수금을 이미 매긴 의뢰가 없으면 첫 번째)
  if r.project_id is null or not exists (
       select 1 from requests o where o.project_id = r.project_id and o.id <> r.id
         and o.fee_type = 'first' and o.status <> 'cancelled') then
    select c.id into cp from coupons c
     where c.user_id = r.demander_id and c.used_at is null and c.expires_at > now()
       and not exists (select 1 from requests q where q.coupon_id is not null and q.demander_id = r.demander_id
                       and q.status in ('draft', 'open', 'selecting', 'awaiting_deposit') and q.id <> r.id)
     order by c.expires_at limit 1;
    return query select 'first'::text,
                        case when cp is null then price_of('intake_fee') else greatest(price_of('intake_fee') - (select amount from coupons where id = cp), 0) end,
                        price_of('open_base') + extra + cond, cp;
    return;
  end if;
  return query select 'continue'::text, price_of('continue_fee') + extra + cond, 0, null::uuid;
end $$;
revoke execute on function request_fee(uuid) from public, anon, authenticated;

-- 수요자 화면용 미리보기 (제출 전 금액 안내). 계산 규칙은 request_fee와 같음
create or replace function preview_fee(p_project uuid, p_supplier_count int, p_item_ids int[], p_target_ids uuid[])
returns table (fee_type text, intake int, deposit int, has_coupon boolean)
language plpgsql stable security definer set search_path = public as $$
declare extra int; cond int; partners uuid[]; cp uuid;
begin
  if p_project is not null and not owns_project(p_project) then return; end if;
  extra := greatest(coalesce(p_supplier_count, 2) - price_of('base_suppliers'), 0) * price_of('open_extra_supplier');
  cond  := coalesce((select sum(price) from checklist_items where id = any(p_item_ids) and not is_required), 0)::int;
  if p_project is not null and coalesce(array_length(p_target_ids, 1), 0) > 0 then
    partners := project_partner_ids(p_project);
    if p_target_ids <@ partners then return query select 'followup'::text, 0, 0, false; return; end if;
  end if;
  if p_project is null or not exists (select 1 from requests o where o.project_id = p_project and o.fee_type = 'first' and o.status <> 'cancelled') then
    select c.id into cp from coupons c where c.user_id = auth.uid() and c.used_at is null and c.expires_at > now()
      and not exists (select 1 from requests q where q.coupon_id is not null and q.demander_id = auth.uid()
                      and q.status in ('draft', 'open', 'selecting', 'awaiting_deposit'))
      order by c.expires_at limit 1;
    return query select 'first'::text,
      case when cp is null then price_of('intake_fee') else greatest(price_of('intake_fee') - (select amount from coupons where id = cp), 0) end,
      price_of('open_base') + extra + cond, cp is not null;
    return;
  end if;
  return query select 'continue'::text, price_of('continue_fee') + extra + cond, 0, false;
end $$;
revoke execute on function preview_fee(uuid, int, int[], uuid[]) from public, anon;
grant execute on function preview_fee(uuid, int, int[], uuid[]) to authenticated;

-- ---------- 의뢰 보호 트리거 (0004 대체): 제출 순간 요금을 서버가 확정 ----------
create or replace function guard_requests() returns trigger
language plpgsql set search_path = public as $$
declare f record;
begin
  if not is_privileged() then
    if tg_op = 'INSERT' then
      new.status := 'draft'; new.amount_total := null; new.paid_at := null; new.respond_until := null;
      new.delivered_at := null; new.verify_until := null; new.confirmed_at := null; new.submitted_at := null; new.code := null;
      new.fee_type := null; new.intake_amount := null; new.deposit_amount := null; new.deposit_paid_at := null; new.coupon_id := null;
      if new.project_id is not null and not owns_project(new.project_id) then raise exception '내 프로젝트가 아닙니다'; end if;
    else
      new.demander_id := old.demander_id; new.code := old.code; new.status := old.status; new.project_id := old.project_id;
      new.paid_at := old.paid_at; new.respond_until := old.respond_until; new.delivered_at := old.delivered_at;
      new.verify_until := old.verify_until; new.confirmed_at := old.confirmed_at; new.deposit_paid_at := old.deposit_paid_at;
      if new.submitted_at is not null and old.submitted_at is null then
        new.submitted_at := now();
        if new.kind = 'direct' then
          new.supplier_count := greatest(1, (select count(*) from request_targets where request_id = new.id));
        end if;
      else
        new.fee_type := old.fee_type; new.intake_amount := old.intake_amount; new.deposit_amount := old.deposit_amount;
        new.coupon_id := old.coupon_id; new.amount_total := old.amount_total;
      end if;
    end if;
  end if;
  return new;
end $$;

-- 제출 직후(AFTER) 요금 확정: supplier_count 등 BEFORE에서 정한 값이 반영된 뒤 계산
create or replace function finalize_request_fee() returns trigger
language plpgsql security definer set search_path = public as $$
declare f record;
begin
  if new.submitted_at is not null and old.submitted_at is null and pg_trigger_depth() = 1 then
    select * into f from request_fee(new.id);
    update requests set fee_type = f.fee_type, intake_amount = f.intake, deposit_amount = f.deposit,
                        amount_total = f.intake, coupon_id = f.coupon
     where id = new.id;
    if f.coupon is not null then update coupons set used_request_id = new.id, used_at = now() where id = f.coupon; end if;
    if new.project_id is not null then update projects set status = 'active', updated_at = now() where id = new.project_id and status = 'draft'; end if;
  end if;
  return null;
end $$;
create trigger trg_finalize_fee after update on requests for each row execute function finalize_request_fee();
revoke execute on function finalize_request_fee() from public, anon, authenticated;

-- ---------- 관리자 처리 (0004 대체·추가) ----------
-- 공개 승인: 접수비 입금 확인(0원이면 확인만) → 파트너에게 공개
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
  if coalesce(r.amount_total, 0) > 0 then
    insert into payments (request_id, pg, pg_tid, amount) values (p_request, p_pg, p_tid, r.amount_total);
  end if;
  insert into responses (request_id, supplier_id, status)
  select p_request, t.supplier_id, 'invited' from request_targets t where t.request_id = p_request and r.kind = 'direct'
  on conflict do nothing;
end $$;

-- 리스트 전달: 착수금이 있으면 '착수금 입금 대기', 없으면 바로 전달(연락처 공개)
create or replace function admin_deliver(p_request uuid, p_selected uuid[]) returns void
language plpgsql security definer set search_path = public as $$
declare r requests;
begin
  if not is_admin() then raise exception '관리자만 할 수 있습니다'; end if;
  if coalesce(array_length(p_selected, 1), 0) = 0 then raise exception '선정할 업체를 고르세요'; end if;
  select * into r from requests where id = p_request for update;
  if r.status not in ('open', 'selecting') then raise exception '전달할 수 있는 상태가 아닙니다'; end if;
  update responses set status = case when id = any(p_selected) then 'selected'::response_status else 'not_selected'::response_status end,
                       selected_at = case when id = any(p_selected) then now() end
   where request_id = p_request and status in ('submitted', 'selected', 'not_selected');
  if coalesce(r.deposit_amount, 0) > 0 and r.deposit_paid_at is null then
    update requests set status = 'awaiting_deposit' where id = p_request;
  else
    update requests set status = 'delivered', delivered_at = now(),
           verify_until = now() + make_interval(days => price_of('verify_days'))
     where id = p_request;
  end if;
end $$;

-- 착수금 입금 확인 → 연락처 공개, 검증기간 시작
create or replace function admin_confirm_deposit(p_request uuid, p_pg text default 'bank', p_tid text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r requests;
begin
  if not is_admin() then raise exception '관리자만 할 수 있습니다'; end if;
  select * into r from requests where id = p_request for update;
  if r.status <> 'awaiting_deposit' then raise exception '착수금 입금 대기 상태가 아닙니다'; end if;
  update requests set status = 'delivered', deposit_paid_at = now(), delivered_at = now(),
         verify_until = now() + make_interval(days => price_of('verify_days'))
   where id = p_request;
  insert into payments (request_id, pg, pg_tid, amount) values (p_request, p_pg, coalesce(p_tid, '착수금'), r.deposit_amount);
end $$;
revoke execute on function admin_confirm_deposit(uuid, text, text) from public, anon;
grant execute on function admin_confirm_deposit(uuid, text, text) to authenticated;

-- 착수금 입금 대기 중 수요자가 보는 미리보기: 업체명·연락처 없이 적합도와 체크 결과만
create or replace function request_preview(p_request uuid)
returns table (label text, fit_pct numeric, qty_min numeric, qty_max numeric, price_min numeric, price_max numeric,
               due_min_days int, due_max_days int, region_sido text, answers jsonb, memo text)
language sql stable security definer set search_path = public as $$
  select '파트너 ' || chr(64 + row_number() over (order by x.fit_pct desc nulls last)::int),
         x.fit_pct, x.qty_min, x.qty_max, x.price_min, x.price_max, x.due_min_days, x.due_max_days,
         coalesce(s.region_sido, o.region_sido),
         (select coalesce(jsonb_agg(jsonb_build_object('item_id', a.item_id, 'value', a.value, 'note', a.note)), '[]') from response_answers a where a.response_id = x.id),
         x.memo
  from responses x left join suppliers s on s.id = x.supplier_id left join offline_suppliers o on o.id = x.offline_supplier_id
  join requests r on r.id = x.request_id
  where x.request_id = p_request and x.status = 'selected' and r.status = 'awaiting_deposit'
    and (r.demander_id = auth.uid() or is_admin())
$$;
revoke execute on function request_preview(uuid) from public, anon;
grant execute on function request_preview(uuid) to authenticated;

-- ---------- 공급자 피드: 단계·차수·프로젝트 요약 추가 ----------
drop function if exists supplier_request_feed();
create or replace function supplier_request_feed()
returns table (id uuid, code text, kind request_kind, major_id int, minor_id int, title text, description text,
               qty_min numeric, qty_max numeric, price_min numeric, price_max numeric, due_min_days int, due_max_days int,
               sample_needed boolean, deliver_sido text, supplier_count int, status request_status,
               respond_until timestamptz, created_at timestamptz, thumbnail_path text,
               stage int, phase text, context text, fee_type text)
language sql stable security definer set search_path = public as $$
  select r.id, r.code, r.kind, r.major_id, r.minor_id, r.title, r.description,
         r.qty_min, r.qty_max, r.price_min, r.price_max, r.due_min_days, r.due_max_days,
         r.sample_needed, r.deliver_sido, r.supplier_count, r.status, r.respond_until, r.created_at,
         (select f.path from request_files f where f.request_id = r.id and f.visibility = 'all' and f.is_image order by f.sort limit 1),
         r.stage, r.phase, r.context, r.fee_type
  from requests r
  where supplier_can_see(r.id)
  order by r.created_at desc
$$;
revoke execute on function supplier_request_feed() from public, anon;
grant execute on function supplier_request_feed() to authenticated;

-- ---------- 권한 규칙 ----------
alter table projects enable row level security;
alter table coupons  enable row level security;
create policy admin_all on projects for all to authenticated using (is_admin()) with check (is_admin());
create policy admin_all on coupons  for all to authenticated using (is_admin()) with check (is_admin());
create policy owner_select on projects for select to authenticated using (demander_id = auth.uid());
create policy owner_insert on projects for insert to authenticated with check (demander_id = auth.uid() and status = 'draft');
create policy owner_update on projects for update to authenticated using (demander_id = auth.uid()) with check (demander_id = auth.uid());
create policy owner_delete_draft on projects for delete to authenticated
  using (demander_id = auth.uid() and status = 'draft' and not exists (select 1 from requests r where r.project_id = projects.id and r.submitted_at is not null));
create policy owner_read on coupons for select to authenticated using (user_id = auth.uid());

-- 프로젝트 상태 보호: 회원은 draft→active 직접 전환 불가(제출 시 서버가 바꿈), closed는 직접 가능
create or replace function guard_projects() returns trigger
language plpgsql set search_path = public as $$
begin
  if not is_privileged() then
    new.demander_id := old.demander_id;
    if new.status = 'active' and old.status = 'draft' then new.status := old.status; end if;
    if new.status = 'draft' and old.status <> 'draft' then new.status := old.status; end if;
    if new.status = 'closed' and old.status <> 'closed' then new.closed_at := now(); end if;
    if new.status <> 'closed' and old.status = 'closed' then new.closed_at := null; end if;
    new.updated_at := now();
  end if;
  return new;
end $$;
create trigger trg_guard_projects before update on projects for each row execute function guard_projects();

-- 데이터베이스 검사 경고용: search_path 고정
alter function guard_projects() set search_path = public;

-- 금액 계산(이전 방식) 정리: 지정 의뢰 할인 폐지로 일반·지정 같은 계산
create or replace function quote_amount(p_kind request_kind, p_supplier_count int, p_item_ids int[])
returns int language sql stable set search_path = public as $$
  select price_of('open_base')
    + greatest(p_supplier_count - price_of('base_suppliers'), 0) * price_of('open_extra_supplier')
    + coalesce((select sum(price) from checklist_items where id = any(p_item_ids) and not is_required), 0)::int
$$;

-- =====================================================================
-- 비회원사 목록 (공공데이터·운영자 인맥으로 미리 등록한 공급사)
--   - 공개 둘러보기에 "비회원사" 배지로 함께 표시 (업체명·연락처는 공개하지 않음)
--   - 비회원사는 지정 의뢰 대상이 될 수 없음 (브로커가 전화로 확인 후 대리 입력)
--   - 같은 사업자번호로 회원가입하면 회원사로 자동 연결
--   - 지정 의뢰 기능은 요금 설정 direct_request_enabled 로 켜고 끔 (지금은 0 = 끔)
-- =====================================================================

alter table offline_suppliers
  add column if not exists biz_no             text,
  add column if not exists category_ids       int[] not null default '{}',   -- 대분류·중분류 id
  add column if not exists process_names      text[] not null default '{}',
  add column if not exists intro              text,
  add column if not exists source             text not null default 'network' check (source in ('public', 'network')),
  add column if not exists source_name        text,          -- 예: 식약처 식품제조가공업 인허가 정보
  add column if not exists source_date        date,          -- 수집일
  add column if not exists active_checked_at  timestamptz,   -- 활동 확인 (운영사 확인)
  add column if not exists listed             boolean not null default true,
  add column if not exists consent            text not null default 'unknown' check (consent in ('unknown', 'agreed', 'refused')),
  add column if not exists linked_supplier_id uuid references suppliers(id) on delete set null,
  add column if not exists updated_at         timestamptz not null default now();
create unique index if not exists offline_suppliers_biz_no on offline_suppliers (biz_no) where biz_no is not null and biz_no <> '';

insert into pricing (key, value, note) values ('direct_request_enabled', 0, '지정 의뢰 기능 (1=켬, 0=끔). 회원사가 모이면 켜기')
on conflict (key) do nothing;

-- ---------- 공개 둘러보기: 회원사 + 공개 중인 비회원사 ----------
drop function if exists supplier_directory();
create or replace function supplier_directory()
returns table (supplier_key uuid, is_member boolean, operator_verified boolean, region_sido text, intro text,
               category_ids int[], categories text[], processes text[], verified_licenses text[], response_count bigint, source_label text)
language sql stable security definer set search_path = public as $$
  select s.id, true, false, s.region_sido, s.intro,
    array(select sc.category_id from supplier_categories sc where sc.supplier_id = s.id),
    array(select c.name from supplier_categories sc join categories c on c.id = sc.category_id where sc.supplier_id = s.id order by c.sort),
    array(select p.name from supplier_processes sp join processes p on p.id = sp.process_id where sp.supplier_id = s.id),
    array(select i.label from supplier_licenses l join checklist_items i on i.id = l.item_id where l.supplier_id = s.id and l.verified_at is not null),
    (select count(*) from responses x where x.supplier_id = s.id and x.submitted_at is not null),
    '회원사'::text
  from suppliers s
  where s.biz_verified_at is not null and not s.is_restricted
  union all
  select o.id, false, o.active_checked_at is not null, o.region_sido, o.intro,
    o.category_ids,
    array(select c.name from categories c where c.id = any(o.category_ids) order by c.parent_id nulls first, c.sort),
    o.process_names, '{}'::text[],
    (select count(*) from responses x where x.offline_supplier_id = o.id and x.submitted_at is not null),
    case when o.source = 'public' then '공개 정보 기반' else '운영사 네트워크' end
  from offline_suppliers o
  where o.listed and o.consent <> 'refused' and o.linked_supplier_id is null
$$;
revoke execute on function supplier_directory() from public;
grant execute on function supplier_directory() to anon, authenticated;

-- ---------- 지정 의뢰 제한 ----------
-- 지정 대상 추가 가능: (지정 의뢰가 켜져 있음) 또는 (이 프로젝트에서 이미 연결된 파트너 = 기존 파트너 문의)
create or replace function can_target(p_request uuid, p_supplier uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select request_editable(p_request) and (
    coalesce(price_of('direct_request_enabled'), 0) = 1
    or p_supplier = any(project_partner_ids((select project_id from requests where id = p_request))))
$$;
revoke execute on function can_target(uuid, uuid) from public, anon;
grant execute on function can_target(uuid, uuid) to authenticated;

drop policy if exists owner_write on request_targets;
create policy owner_write on request_targets for insert to authenticated with check (can_target(request_id, supplier_id));
-- request_targets.supplier_id 는 suppliers(회원사)를 가리키므로 비회원사는 애초에 지정할 수 없음

-- ---------- 회원가입 시 같은 사업자번호의 비회원사와 자동 연결 ----------
create or replace function link_offline_supplier() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.biz_no is not null and new.biz_no <> '' then
    update offline_suppliers set linked_supplier_id = new.id, listed = false, consent = 'agreed', updated_at = now()
     where biz_no = new.biz_no and linked_supplier_id is null;
  end if;
  return null;
end $$;
create trigger trg_link_offline after insert on suppliers for each row execute function link_offline_supplier();
revoke execute on function link_offline_supplier() from public, anon, authenticated;

-- 공개 숫자: 회원사 / 공개 정보 기반 / 운영사 네트워크
create or replace function supplier_counts()
returns table (members bigint, public_listed bigint, network_listed bigint)
language sql stable security definer set search_path = public as $$
  select (select count(*) from suppliers where biz_verified_at is not null and not is_restricted),
         (select count(*) from offline_suppliers where listed and consent <> 'refused' and linked_supplier_id is null and source = 'public'),
         (select count(*) from offline_suppliers where listed and consent <> 'refused' and linked_supplier_id is null and source = 'network')
$$;
revoke execute on function supplier_counts() from public;
grant execute on function supplier_counts() to anon, authenticated;

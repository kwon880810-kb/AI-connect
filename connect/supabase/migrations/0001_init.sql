-- =====================================================================
-- 윈-윈 커넥트 데이터베이스 구조 (Supabase / PostgreSQL)
-- 기준 문서: BM_확정안.md, 화면_흐름도.md, 카테고리표_초안.md
--
-- 핵심 권한 규칙 (DB에서 강제)
--   1. 공급자는 수요자 정보(회사명·이름·연락처·이메일)를 볼 수 없다
--   2. 공급자는 자기 응답과 자기 신뢰도 점수만 볼 수 있다. 신뢰도는 수요자에게도 안 보인다
--   3. 비회원은 의뢰를 볼 수 없다 (분야별 건수와 가린 공급사 프로필만)
--   4. 수요자는 리스트에 선정된 공급자의 연락처만 볼 수 있다
--   5. 첨부 파일은 '모두 공개'와 '선정사 공개'로 나뉜다
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 0. 열거형
-- ---------------------------------------------------------------------
create type user_role       as enum ('demander', 'supplier', 'admin');
create type request_kind    as enum ('open', 'direct');            -- 일반 의뢰 / 지정 의뢰
create type request_status  as enum ('draft', 'paid', 'open', 'selecting', 'delivered', 'disputed', 'confirmed', 'cancelled');
create type item_kind       as enum ('range', 'choice');           -- 범위 입력 / 선택형
create type answer_value    as enum ('O', 'P', 'X', 'N');          -- 가능 / 조건부 / 불가 / 미확인
create type file_visibility as enum ('all', 'selected');           -- 모두 공개 / 선정사 공개
create type response_status as enum ('invited', 'submitted', 'selected', 'not_selected', 'mismatched', 'no_response', 'replaced');
create type dispute_kind    as enum ('required', 'condition', 'no_contact');
create type dispute_status  as enum ('open', 'awaiting_opinion', 'accepted', 'rejected');
create type dispute_remedy  as enum ('refund', 'replace');
create type contract_status as enum ('draft', 'proposed', 'signed', 'cancelled');

-- ---------------------------------------------------------------------
-- 1. 회원
-- ---------------------------------------------------------------------
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        user_role not null,
  name        text not null,
  phone       text,
  email       text,
  company     text,
  created_at  timestamptz not null default now()
);

-- 공급자 회사 정보. 업체명·연락처는 공개 둘러보기에서 가려진다 (supplier_directory 뷰 참고)
create table suppliers (
  id              uuid primary key references profiles(id) on delete cascade,
  biz_no          text not null unique,          -- 사업자등록번호 (숫자 10자리)
  biz_verified_at timestamptz,                   -- 국세청 진위확인 완료 시각 (필수)
  company_name    text not null,
  ceo_name        text,
  contact_name    text,
  contact_phone   text,
  contact_email   text,
  region_sido     text,                          -- 시·도 (공개)
  intro           text,                          -- 소개 (공개, 업체명·연락처를 적지 않도록 안내)
  is_restricted   boolean not null default false,-- 신뢰도 50점 미만 등 응답 제한
  created_at      timestamptz not null default now()
);

-- 비회원 공급자 (브로커가 대리 입력할 때)
create table offline_suppliers (
  id             uuid primary key default gen_random_uuid(),
  company_name   text not null,
  contact_name   text,
  contact_phone  text,
  region_sido    text,
  memo           text,
  created_by     uuid references profiles(id),
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. 분류 (카테고리표)
-- ---------------------------------------------------------------------
create table categories (
  id             serial primary key,
  parent_id      int references categories(id),  -- null = 대분류, 값 있음 = 중분류
  name           text not null,
  aliases        text[] not null default '{}',   -- 별칭·검색어
  confusion_note text,                           -- 헷갈리기 쉬운 점 (선택 시 안내)
  sort           int not null default 0,
  active         boolean not null default true
);

create table processes (
  id        serial primary key,
  major_id  int not null references categories(id),
  name      text not null
);

-- 체크리스트 항목. major_id·minor_id가 모두 null이면 공통 필수(C1~C5)
create table checklist_items (
  id          serial primary key,
  code        text unique,                       -- C1, F1, K2 ...
  major_id    int references categories(id),
  minor_id    int references categories(id),
  label       text not null,                     -- 수요자에게 보이는 이름
  question    text,                              -- 공급자에게 보이는 질문
  kind        item_kind not null default 'choice',
  unit        text,                              -- 범위 항목 단위: 개, 원, 일
  is_required boolean not null default false,    -- 필수값(무료) / 조건값(유료)
  is_license  boolean not null default false,    -- 인허가 서류 확인 (권장 조건값)
  price       int not null default 5000,         -- 조건값 추가요금 (필수값은 0으로 계산)
  sort        int not null default 0,
  active      boolean not null default true
);

-- 분류 변경 기록 (분류 개선용 데이터)
create table category_changes (
  id          bigserial primary key,
  request_id  uuid,
  from_major  int, from_minor int,
  to_major    int, to_minor   int,
  changed_by  uuid references profiles(id),
  changed_at  timestamptz not null default now()
);

create table supplier_categories (supplier_id uuid references suppliers(id) on delete cascade, category_id int references categories(id), primary key (supplier_id, category_id));
create table supplier_processes  (supplier_id uuid references suppliers(id) on delete cascade, process_id  int references processes(id),  primary key (supplier_id, process_id));

-- 인허가 서류 (관리자가 확인하면 verified_at)
create table supplier_licenses (
  id           bigserial primary key,
  supplier_id  uuid not null references suppliers(id) on delete cascade,
  item_id      int not null references checklist_items(id),   -- is_license 항목
  doc_path     text,
  verified_at  timestamptz,
  verified_by  uuid references profiles(id),
  unique (supplier_id, item_id)
);

-- ---------------------------------------------------------------------
-- 3. 요금 설정 (나중에 금액만 바꾸면 됨)
-- ---------------------------------------------------------------------
create table pricing (
  key    text primary key,
  value  int not null,
  note   text
);
insert into pricing values
  ('open_base',           50000, '일반 의뢰 착수금 (업체 2곳 + 필수값)'),
  ('direct_base',         25000, '지정 의뢰 착수금 (절반)'),
  ('base_suppliers',          2, '착수금에 포함된 업체 수'),
  ('open_extra_supplier', 20000, '일반 의뢰 업체 추가 1곳당 [예시]'),
  ('direct_extra_supplier',10000,'지정 의뢰 업체 추가 1곳당 [예시]'),
  ('verify_days',             7, '검증기간 (일)'),
  ('respond_hours',          48, '공급자 응답 기한 (시간)'),
  ('range_tolerance_pct',    20, '범위 노출 허용 오차 (%)');

create or replace function price_of(k text) returns int language sql stable as
$$ select value from pricing where key = k $$;

-- ---------------------------------------------------------------------
-- 4. 의뢰
-- ---------------------------------------------------------------------
create table requests (
  id             uuid primary key default gen_random_uuid(),
  code           text unique,                          -- R261105-001
  demander_id    uuid not null references profiles(id),
  kind           request_kind not null default 'open',
  major_id       int not null references categories(id),
  minor_id       int references categories(id),        -- 선택 (없으면 대분류 전체 노출)
  title          text not null,                        -- 만들고 싶은 것
  description    text,
  qty_min numeric, qty_max numeric,                    -- 수량 범위
  price_min numeric, price_max numeric,                -- 단가 범위
  due_min_days int, due_max_days int,                  -- 납기 범위 (일)
  sample_needed  boolean not null default false,
  deliver_sido   text,
  supplier_count int not null default 2 check (supplier_count >= 1),
  amount_total   int,                                  -- 결제 금액 (확정 시점 스냅샷)
  status         request_status not null default 'draft',
  paid_at        timestamptz,
  respond_until  timestamptz,                          -- 공급자 응답 마감
  delivered_at   timestamptz,                          -- 리스트 전달 = 소개일
  verify_until   timestamptz,                          -- 검증기간 끝
  confirmed_at   timestamptz,
  created_at     timestamptz not null default now()
);
create index on requests (status, major_id, minor_id);

-- 선택한 조건값 (필수값은 분류로 자동 포함되므로 저장하지 않음)
create table request_items (
  request_id uuid references requests(id) on delete cascade,
  item_id    int references checklist_items(id),
  price      int not null,                             -- 선택 시점 가격 스냅샷
  primary key (request_id, item_id)
);

-- 지정 의뢰 대상
create table request_targets (
  request_id  uuid references requests(id) on delete cascade,
  supplier_id uuid references suppliers(id),
  primary key (request_id, supplier_id)
);

create table request_files (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references requests(id) on delete cascade,
  path        text not null,                          -- Storage 경로
  file_name   text,
  is_image    boolean not null default false,
  visibility  file_visibility not null default 'selected',
  sort        int not null default 0,
  created_at  timestamptz not null default now()
);

-- 공급자 열람 기록 (응답률 = 응답 수 / 열람 수)
create table request_views (
  request_id  uuid references requests(id) on delete cascade,
  supplier_id uuid references suppliers(id) on delete cascade,
  first_viewed_at timestamptz not null default now(),
  primary key (request_id, supplier_id)
);

-- ---------------------------------------------------------------------
-- 5. 공급자 응답 (체크리스트)
-- ---------------------------------------------------------------------
create table responses (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references requests(id) on delete cascade,
  supplier_id        uuid references suppliers(id),         -- 회원 공급자
  offline_supplier_id uuid references offline_suppliers(id),-- 비회원 (대리 입력)
  proxy_by           uuid references profiles(id),          -- 대리 입력한 관리자
  status             response_status not null default 'submitted',
  qty_min numeric, qty_max numeric,
  price_min numeric, price_max numeric,
  due_min_days int, due_max_days int,
  sample_ok          answer_value,
  sample_cost        text,
  memo               text,                                   -- 상담 메모 (수요자에게 보임)
  license_pledge     boolean not null default false,         -- 인허가 보유 서약
  fit_pct            numeric,                                -- 적합도 (자동 계산)
  has_required_x     boolean not null default false,         -- 필수값 ✕ 여부 (선정 제외)
  submitted_at       timestamptz,
  selected_at        timestamptz,
  created_at         timestamptz not null default now(),
  check (num_nonnulls(supplier_id, offline_supplier_id) = 1),
  unique (request_id, supplier_id),
  unique (request_id, offline_supplier_id)
);

create table response_answers (
  response_id uuid references responses(id) on delete cascade,
  item_id     int references checklist_items(id),
  value       answer_value not null default 'N',
  note        text,
  checked_at  timestamptz,                -- 브로커 대리 입력 시 확인 일시
  checked_via text,                       -- 전화 / 문자 / 방문
  primary key (response_id, item_id)
);

-- ---------------------------------------------------------------------
-- 6. 결제·환불
-- ---------------------------------------------------------------------
create table payments (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references requests(id),
  pg          text,                       -- PG사
  pg_tid      text,                       -- PG 거래번호
  amount      int not null,
  status      text not null default 'paid',
  paid_at     timestamptz not null default now()
);

create table refunds (
  id           uuid primary key default gen_random_uuid(),
  payment_id   uuid not null references payments(id),
  response_id  uuid references responses(id),
  dispute_id   uuid,
  amount       int not null check (amount > 0),
  reason       text not null,             -- no_response / direct_mismatch / dispute / shortfall
  pg_cancel_id text,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7. 이의신청·의견서·신뢰도
-- ---------------------------------------------------------------------
create table disputes (
  id             uuid primary key default gen_random_uuid(),
  request_id     uuid not null references requests(id),
  response_id    uuid not null references responses(id),
  item_id        int references checklist_items(id),
  kind           dispute_kind not null,
  claim          text not null,           -- 수요자가 들은 실제 내용
  evidence_paths text[] not null default '{}',
  status         dispute_status not null default 'open',
  opinion        text,                    -- 공급자 의견서
  opinion_due    timestamptz,
  opinion_at     timestamptz,
  decision_note  text,
  supplier_fault boolean,                 -- 공급자 책임 여부 (점수 차감 판단, 환불과 별개)
  remedy         dispute_remedy,          -- 인정 시 수요자 선택
  decided_by     uuid references profiles(id),
  decided_at     timestamptz,
  created_at     timestamptz not null default now()
);
alter table refunds add constraint refunds_dispute_fk foreign key (dispute_id) references disputes(id);

-- 신뢰도 점수 변동 기록. 점수 = 100 + 합계 (최대 100)
create table score_events (
  id           bigserial primary key,
  supplier_id  uuid not null references suppliers(id) on delete cascade,
  delta        int not null,
  reason       text not null,             -- required_mismatch -10 / condition_mismatch -3 / no_contact -15 / opinion_late -5 / clean_pass +1
  dispute_id   uuid references disputes(id),
  request_id   uuid references requests(id),
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 8. 온라인 기본계약서 (계약 사실 기록)
-- ---------------------------------------------------------------------
create table contracts (
  id                  uuid primary key default gen_random_uuid(),
  request_id          uuid not null references requests(id),
  response_id         uuid not null references responses(id),
  demander_id         uuid not null references profiles(id),
  supplier_id         uuid not null references suppliers(id),
  body                jsonb not null,     -- 품목, 사양, 수량, 단가, 납기, 지급 조건, 검수·하자, 해지, 분쟁
  status              contract_status not null default 'draft',
  pdf_path            text,
  sha256              text,               -- 서명 완료 PDF의 위변조 확인값
  demander_signed_at  timestamptz,
  supplier_signed_at  timestamptz,
  created_at          timestamptz not null default now()
);

-- =====================================================================
-- 함수
-- =====================================================================

-- 의뢰번호 R + yyMMdd + 일련번호
create sequence request_code_seq;
create or replace function set_request_code() returns trigger language plpgsql as $$
begin
  if new.code is null then
    new.code := 'R' || to_char(now() at time zone 'Asia/Seoul', 'YYMMDD') || '-' || lpad(nextval('request_code_seq')::text, 4, '0');
  end if;
  return new;
end $$;
create trigger trg_request_code before insert on requests for each row execute function set_request_code();

-- 범위 비교: 겹치면 O, 수요자 범위 ±허용오차 안에서 겹치면 P, 아니면 X. 한쪽이 비어 있으면 N
create or replace function range_mark(d_min numeric, d_max numeric, s_min numeric, s_max numeric)
returns answer_value language plpgsql stable as $$
declare
  tol numeric := coalesce(price_of('range_tolerance_pct'), 20) / 100.0;
  dl numeric := coalesce(d_min, d_max); dh numeric := coalesce(d_max, d_min);
  sl numeric := coalesce(s_min, s_max); sh numeric := coalesce(s_max, s_min);
begin
  if dl is null or sl is null then return 'N'; end if;
  if sl <= dh and sh >= dl then return 'O'; end if;
  if sl <= dh * (1 + tol) and sh >= dl * (1 - tol) then return 'P'; end if;
  return 'X';
end $$;

-- 결제 금액 계산 (요청서 화면 미리보기와 결제 시 동일 계산)
create or replace function quote_amount(p_kind request_kind, p_supplier_count int, p_item_ids int[])
returns int language sql stable as $$
  select
    case when p_kind = 'direct' then price_of('direct_base') else price_of('open_base') end
    + greatest(p_supplier_count - price_of('base_suppliers'), 0)
      * case when p_kind = 'direct' then price_of('direct_extra_supplier') else price_of('open_extra_supplier') end
    + coalesce((select sum(price) from checklist_items where id = any(p_item_ids) and not is_required), 0)::int
$$;

create or replace function is_admin() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin')
$$;

-- 신뢰도 점수 (0~100). 공급자 본인과 관리자만 값을 받음 (그 외에는 null)
create or replace function trust_score_of(p_supplier uuid) returns int language sql stable security definer set search_path = public as $$
  select case when p_supplier = auth.uid() or is_admin()
              then least(100, greatest(0, 100 + coalesce((select sum(delta) from score_events where supplier_id = p_supplier), 0)))::int
         end
$$;

-- ---------- 권한 판단용 도우미 (RLS 순환 방지를 위해 security definer) ----------
create or replace function is_supplier() returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from suppliers s join profiles p on p.id = s.id
                 where s.id = auth.uid() and p.role = 'supplier' and s.biz_verified_at is not null)
$$;
create or replace function owns_request(p_request uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from requests where id = p_request and demander_id = auth.uid())
$$;
-- 공급자가 이 의뢰를 볼 수 있는가: 일반 의뢰는 공개 이후 모든 인증 공급자, 지정 의뢰는 지정된 공급자만. 응답한 의뢰는 계속 볼 수 있음
create or replace function supplier_can_see(p_request uuid) returns boolean language sql stable security definer set search_path = public as $$
  select is_supplier() and exists (
    select 1 from requests r
    where r.id = p_request and r.status not in ('draft', 'paid', 'cancelled') and (
      (r.kind = 'open' and r.status = 'open')
      or (r.kind = 'direct' and exists (select 1 from request_targets t where t.request_id = r.id and t.supplier_id = auth.uid()))
      or exists (select 1 from responses x where x.request_id = r.id and x.supplier_id = auth.uid())
    ))
$$;
-- 이 공급자가 이 의뢰에 선정되었는가 (지정 의뢰는 지정만으로 선정사 파일 열람)
create or replace function supplier_is_selected(p_request uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from responses where request_id = p_request and supplier_id = auth.uid() and status = 'selected')
      or exists (select 1 from request_targets where request_id = p_request and supplier_id = auth.uid())
$$;
-- 수요자가 이 공급자의 연락처를 볼 수 있는가: 자기 의뢰에 선정된 경우만
create or replace function demander_can_see_supplier(p_supplier uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from responses x join requests r on r.id = x.request_id
                 where x.supplier_id = p_supplier and x.status = 'selected' and r.demander_id = auth.uid()
                   and r.status in ('delivered', 'disputed', 'confirmed'))
$$;

-- 응답 저장 시 적합도·필수 ✕ 자동 계산
create or replace function calc_response_fit(p_response uuid) returns void language plpgsql security definer set search_path = public as $$
declare
  r requests; x responses; marks answer_value[]; req_x boolean; pts numeric := 0; cnt int := 0; m answer_value;
begin
  select * into x from responses where id = p_response;
  select * into r from requests where id = x.request_id;
  marks := array[
    range_mark(r.qty_min, r.qty_max, x.qty_min, x.qty_max),
    range_mark(r.price_min, r.price_max, x.price_min, x.price_max),
    range_mark(r.due_min_days, r.due_max_days, x.due_min_days, x.due_max_days)
  ];
  -- 수량·납기 ✕는 필수 불일치. 단가는 수요자가 비워 둘 수 있으므로 N 허용
  req_x := marks[1] = 'X' or marks[3] = 'X' or marks[2] = 'X'
        or exists (select 1 from response_answers a join checklist_items i on i.id = a.item_id
                   where a.response_id = x.id and i.is_required and a.value = 'X');
  foreach m in array marks || array(select a.value from response_answers a where a.response_id = x.id) loop
    if m <> 'N' then cnt := cnt + 1; pts := pts + case m when 'O' then 1 when 'P' then 0.5 else 0 end; end if;
  end loop;
  update responses set fit_pct = case when cnt = 0 then null else round(pts / cnt * 100, 1) end,
                       has_required_x = req_x
   where id = x.id;
end $$;

-- 일반 의뢰 순위: 필수 ✕ 제외, 적합도 70% + 신뢰도 30% (관리자 화면용)
create or replace function rank_responses(p_request uuid)
returns table (response_id uuid, supplier_label text, fit_pct numeric, trust int, rank_score numeric, has_required_x boolean)
language sql stable security definer set search_path = public as $$
  select x.id,
         coalesce(s.company_name, o.company_name),
         x.fit_pct,
         case when x.supplier_id is null then null else trust_score_of(x.supplier_id) end,
         round(coalesce(x.fit_pct, 0) * 0.7 + coalesce(case when x.supplier_id is null then 100 else trust_score_of(x.supplier_id) end, 100) * 0.3, 1),
         x.has_required_x
  from responses x
  left join suppliers s on s.id = x.supplier_id
  left join offline_suppliers o on o.id = x.offline_supplier_id
  where x.request_id = p_request and is_admin() and x.status in ('submitted', 'selected')
  order by x.has_required_x, 5 desc
$$;

-- =====================================================================
-- 공개 데이터 (비회원도 볼 수 있음)
-- =====================================================================

-- 분야별 진행 중 의뢰 건수
create or replace function public_request_counts()
returns table (major_id int, major_name text, open_count bigint)
language sql stable security definer set search_path = public as $$
  select c.id, c.name, count(r.id)
  from categories c left join requests r on r.major_id = c.id and r.status in ('open', 'selecting')
  where c.parent_id is null and c.active
  group by c.id, c.name, c.sort order by c.sort
$$;

-- 공급사 둘러보기: 업체명·연락처·신뢰도는 빠짐
create or replace function supplier_directory()
returns table (supplier_key uuid, region_sido text, intro text, categories text[], processes text[], verified_licenses text[], response_count bigint)
language sql stable security definer set search_path = public as $$
  select s.id, s.region_sido, s.intro,
    array(select c.name from supplier_categories sc join categories c on c.id = sc.category_id where sc.supplier_id = s.id order by c.sort),
    array(select p.name from supplier_processes sp join processes p on p.id = sp.process_id where sp.supplier_id = s.id),
    array(select i.label from supplier_licenses l join checklist_items i on i.id = l.item_id where l.supplier_id = s.id and l.verified_at is not null),
    (select count(*) from responses x where x.supplier_id = s.id and x.submitted_at is not null)
  from suppliers s
  where s.biz_verified_at is not null and not s.is_restricted
$$;

-- 수요자용 응답 현황: 열람 1,000 / 응답 100 · 응답률 10%
create or replace function request_stats(p_request uuid)
returns table (views bigint, responses bigint, response_rate numeric)
language sql stable security definer set search_path = public as $$
  select v.cnt, x.cnt, case when v.cnt = 0 then 0 else round(x.cnt::numeric / v.cnt * 100, 1) end
  from (select count(*) cnt from request_views where request_id = p_request) v,
       (select count(*) cnt from responses where request_id = p_request and submitted_at is not null) x
  where owns_request(p_request) or is_admin()
$$;

-- 공급자용 의뢰 보기: 수요자 정보 컬럼이 아예 없음
create or replace view supplier_request_feed with (security_invoker = false) as
  select r.id, r.code, r.kind, r.major_id, r.minor_id, r.title, r.description,
         r.qty_min, r.qty_max, r.price_min, r.price_max, r.due_min_days, r.due_max_days,
         r.sample_needed, r.deliver_sido, r.supplier_count, r.status, r.respond_until, r.created_at,
         (select f.path from request_files f where f.request_id = r.id and f.visibility = 'all' and f.is_image order by f.sort limit 1) as thumbnail_path
  from requests r
  where supplier_can_see(r.id);

-- =====================================================================
-- 보호 트리거: 일반 회원이 바꾸면 안 되는 칸
--   (관리자·서버 키(service_role)·DB 소유자는 통과)
-- =====================================================================
create or replace function is_privileged() returns boolean language sql stable as $$
  select current_user not in ('authenticated', 'anon') or is_admin()
$$;

create or replace function guard_suppliers() returns trigger language plpgsql as $$
begin
  if not is_privileged() then
    if tg_op = 'INSERT' then
      new.biz_verified_at := null; new.is_restricted := false;
    else
      new.biz_verified_at := old.biz_verified_at; new.is_restricted := old.is_restricted;
      new.biz_no := old.biz_no;
    end if;
  end if;
  return new;
end $$;
create trigger trg_guard_suppliers before insert or update on suppliers for each row execute function guard_suppliers();

create or replace function guard_responses() returns trigger language plpgsql as $$
begin
  if not is_privileged() then
    new.proxy_by := null;
    if tg_op = 'INSERT' then new.selected_at := null; new.submitted_at := now();
    else new.selected_at := old.selected_at; new.request_id := old.request_id; new.supplier_id := old.supplier_id;
         new.submitted_at := coalesce(old.submitted_at, now());
    end if;
  end if;
  return new;
end $$;
create trigger trg_guard_responses before insert or update on responses for each row execute function guard_responses();

-- 응답이나 답이 바뀌면 적합도 재계산 (회원이 fit_pct를 직접 넣어도 덮어씀)
create or replace function recalc_fit_from_response() returns trigger language plpgsql as $$
begin
  if pg_trigger_depth() = 1 then perform calc_response_fit(new.id); end if;
  return null;
end $$;
create trigger trg_fit_response after insert or update on responses for each row execute function recalc_fit_from_response();

create or replace function recalc_fit_from_answer() returns trigger language plpgsql as $$
begin
  perform calc_response_fit(coalesce(new.response_id, old.response_id));
  return null;
end $$;
create trigger trg_fit_answer after insert or update or delete on response_answers for each row execute function recalc_fit_from_answer();

-- =====================================================================
-- 행 수준 보안 (RLS)
-- =====================================================================
alter table profiles           enable row level security;
alter table suppliers          enable row level security;
alter table offline_suppliers  enable row level security;
alter table categories         enable row level security;
alter table processes          enable row level security;
alter table checklist_items    enable row level security;
alter table category_changes   enable row level security;
alter table supplier_categories enable row level security;
alter table supplier_processes enable row level security;
alter table supplier_licenses  enable row level security;
alter table pricing            enable row level security;
alter table requests           enable row level security;
alter table request_items      enable row level security;
alter table request_targets    enable row level security;
alter table request_files      enable row level security;
alter table request_views      enable row level security;
alter table responses          enable row level security;
alter table response_answers   enable row level security;
alter table payments           enable row level security;
alter table refunds            enable row level security;
alter table disputes           enable row level security;
alter table score_events       enable row level security;
alter table contracts          enable row level security;

-- 관리자는 모든 테이블 전체 권한
do $$ declare t text; begin
  foreach t in array array['profiles','suppliers','offline_suppliers','categories','processes','checklist_items','category_changes',
    'supplier_categories','supplier_processes','supplier_licenses','pricing','requests','request_items','request_targets','request_files',
    'request_views','responses','response_answers','payments','refunds','disputes','score_events','contracts'] loop
    execute format('create policy admin_all on %I for all to authenticated using (is_admin()) with check (is_admin())', t);
  end loop;
end $$;

-- 분류·요금: 누구나 읽기
create policy read_all on categories      for select to anon, authenticated using (active);
create policy read_all on processes       for select to anon, authenticated using (true);
create policy read_all on checklist_items for select to anon, authenticated using (active);
create policy read_all on pricing         for select to anon, authenticated using (true);

-- 회원 정보: 본인만. (공급자는 수요자 profiles를 볼 수 없음)
create policy self_read   on profiles for select to authenticated using (id = auth.uid());
create policy self_insert on profiles for insert to authenticated with check (id = auth.uid() and role <> 'admin');
create policy self_update on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid() and role <> 'admin');

-- 공급자 회사 정보: 본인 / 선정된 경우 해당 수요자만 (연락처 공개)
create policy self_all on suppliers for all to authenticated using (id = auth.uid()) with check (id = auth.uid());
create policy demander_selected on suppliers for select to authenticated using (demander_can_see_supplier(id));
-- 사업자 확인 완료(biz_verified_at), 사업자번호, 응답 제한(is_restricted)은 서버(관리자·Edge Function)만 바꿀 수 있음 → guard_suppliers 트리거

create policy self_all on supplier_categories for all to authenticated using (supplier_id = auth.uid()) with check (supplier_id = auth.uid());
create policy self_all on supplier_processes  for all to authenticated using (supplier_id = auth.uid()) with check (supplier_id = auth.uid());
create policy self_read on supplier_licenses for select to authenticated using (supplier_id = auth.uid());
create policy self_insert on supplier_licenses for insert to authenticated with check (supplier_id = auth.uid() and verified_at is null);

-- 의뢰: 수요자 본인 전체. 공급자는 supplier_request_feed 뷰로만 (requests 테이블 직접 조회 불가)
create policy owner_select on requests for select to authenticated using (demander_id = auth.uid());
create policy owner_insert on requests for insert to authenticated with check (demander_id = auth.uid() and status = 'draft');
create policy owner_update_draft on requests for update to authenticated
  using (demander_id = auth.uid() and status = 'draft') with check (demander_id = auth.uid() and status = 'draft');
-- 결제 이후 상태 변경은 서버(결제 확인 Edge Function, 관리자)만

create policy owner_all on request_items   for all to authenticated using (owns_request(request_id)) with check (owns_request(request_id));
create policy owner_all on request_targets for all to authenticated using (owns_request(request_id)) with check (owns_request(request_id));
create policy supplier_read on request_items for select to authenticated using (supplier_can_see(request_id));

-- 첨부 파일: 수요자 본인 전체 / 공급자는 '모두 공개' 또는 선정·지정된 경우
create policy owner_all on request_files for all to authenticated using (owns_request(request_id)) with check (owns_request(request_id));
create policy supplier_read on request_files for select to authenticated
  using (supplier_can_see(request_id) and (visibility = 'all' or supplier_is_selected(request_id)));

-- 열람 기록: 공급자가 상세를 열 때 자기 기록만 추가
create policy supplier_insert on request_views for insert to authenticated with check (supplier_id = auth.uid() and supplier_can_see(request_id));

-- 응답: 공급자는 자기 응답만. 마감 전·제출 상태에서만 수정
create policy supplier_select on responses for select to authenticated using (supplier_id = auth.uid());
create policy supplier_insert on responses for insert to authenticated
  with check (supplier_id = auth.uid() and offline_supplier_id is null and proxy_by is null and status = 'submitted'
              and supplier_can_see(request_id) and not exists (select 1 from suppliers where id = auth.uid() and is_restricted));
create policy supplier_update on responses for update to authenticated
  using (supplier_id = auth.uid() and status in ('invited', 'submitted'))
  with check (supplier_id = auth.uid() and status = 'submitted');
-- 수요자: 자기 의뢰에서 선정된 응답만 (리스트 전달 이후)
create policy demander_selected on responses for select to authenticated
  using (owns_request(request_id) and status = 'selected'
         and exists (select 1 from requests r where r.id = request_id and r.status in ('delivered', 'disputed', 'confirmed')));

create policy supplier_all on response_answers for all to authenticated
  using (exists (select 1 from responses x where x.id = response_id and x.supplier_id = auth.uid() and x.status in ('invited', 'submitted')))
  with check (exists (select 1 from responses x where x.id = response_id and x.supplier_id = auth.uid() and x.status in ('invited', 'submitted')));
create policy supplier_read on response_answers for select to authenticated
  using (exists (select 1 from responses x where x.id = response_id and x.supplier_id = auth.uid()));
create policy demander_read on response_answers for select to authenticated
  using (exists (select 1 from responses x where x.id = response_id and x.status = 'selected' and owns_request(x.request_id)));

-- 결제·환불: 수요자 본인 읽기만 (쓰기는 결제 Edge Function)
create policy owner_read on payments for select to authenticated using (owns_request(request_id));
create policy owner_read on refunds  for select to authenticated using (exists (select 1 from payments p where p.id = payment_id and owns_request(p.request_id)));

-- 이의신청: 수요자가 검증기간 안에 자기 의뢰의 선정 응답에 대해 생성 / 공급자는 자기 응답 건 읽기·의견서
create policy demander_insert on disputes for insert to authenticated
  with check (owns_request(request_id) and status = 'open'
              and exists (select 1 from requests r where r.id = request_id and r.status in ('delivered', 'disputed') and now() <= r.verify_until)
              and exists (select 1 from responses x where x.id = response_id and x.request_id = disputes.request_id and x.status = 'selected'));
create policy demander_read on disputes for select to authenticated using (owns_request(request_id));
create policy supplier_read on disputes for select to authenticated
  using (exists (select 1 from responses x where x.id = response_id and x.supplier_id = auth.uid()));
-- 공급자 의견서 작성은 submit_opinion() 함수로만 (다른 칸을 못 바꾸게)

-- 신뢰도: 공급자 본인만 (수요자 불가)
create policy self_read on score_events for select to authenticated using (supplier_id = auth.uid());

-- 계약서: 양 당사자
create policy party_read on contracts for select to authenticated using (demander_id = auth.uid() or supplier_id = auth.uid());
create policy party_insert on contracts for insert to authenticated
  with check ((demander_id = auth.uid() or supplier_id = auth.uid()) and status = 'draft'
              and exists (select 1 from responses x join requests r on r.id = x.request_id
                          where x.id = response_id and x.status = 'selected' and r.id = request_id
                            and r.demander_id = contracts.demander_id and x.supplier_id = contracts.supplier_id));
create policy party_update on contracts for update to authenticated
  using ((demander_id = auth.uid() or supplier_id = auth.uid()) and status in ('draft', 'proposed'))
  with check ((demander_id = auth.uid() or supplier_id = auth.uid()) and status in ('draft', 'proposed'));
-- 서명(signed)과 PDF·해시 기록은 본인인증을 거치는 Edge Function만

-- 공급자 의견서 제출
create or replace function submit_opinion(p_dispute uuid, p_text text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update disputes d set opinion = p_text, opinion_at = now()
   where d.id = p_dispute and d.status = 'awaiting_opinion'
     and exists (select 1 from responses x where x.id = d.response_id and x.supplier_id = auth.uid());
  if not found then raise exception '의견서를 제출할 수 없는 건입니다'; end if;
end $$;

-- 뷰·공개 함수 권한
revoke all on supplier_request_feed from anon;
grant select on supplier_request_feed to authenticated;
grant execute on function public_request_counts() to anon, authenticated;
grant execute on function supplier_directory()   to anon, authenticated;
grant execute on function quote_amount(request_kind, int, int[]) to anon, authenticated;
grant execute on function request_stats(uuid), submit_opinion(uuid, text), trust_score_of(uuid) to authenticated;

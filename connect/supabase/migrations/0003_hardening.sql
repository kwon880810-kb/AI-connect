-- 보안 점검(Supabase Advisor) 반영
-- 1. 공급자 의뢰 피드: security definer 뷰 → 함수로 교체 (같은 결과, 수요자 정보 칸 없음)
-- 2. 내부 도우미 함수는 비회원(anon)이 호출할 수 없게
-- 3. 모든 함수의 search_path 고정

drop view if exists supplier_request_feed;
create or replace function supplier_request_feed()
returns table (id uuid, code text, kind request_kind, major_id int, minor_id int, title text, description text,
               qty_min numeric, qty_max numeric, price_min numeric, price_max numeric, due_min_days int, due_max_days int,
               sample_needed boolean, deliver_sido text, supplier_count int, status request_status,
               respond_until timestamptz, created_at timestamptz, thumbnail_path text)
language sql stable security definer set search_path = public as $$
  select r.id, r.code, r.kind, r.major_id, r.minor_id, r.title, r.description,
         r.qty_min, r.qty_max, r.price_min, r.price_max, r.due_min_days, r.due_max_days,
         r.sample_needed, r.deliver_sido, r.supplier_count, r.status, r.respond_until, r.created_at,
         (select f.path from request_files f where f.request_id = r.id and f.visibility = 'all' and f.is_image order by f.sort limit 1)
  from requests r
  where supplier_can_see(r.id)
  order by r.created_at desc
$$;

-- search_path 고정
alter function price_of(text)                          set search_path = public;
alter function quote_amount(request_kind, int, int[])  set search_path = public;
alter function set_request_code()                      set search_path = public;
alter function range_mark(numeric, numeric, numeric, numeric) set search_path = public;
alter function is_privileged()                         set search_path = public;
alter function guard_suppliers()                       set search_path = public;
alter function guard_responses()                       set search_path = public;

-- 적합도 재계산 트리거는 서버 권한으로 실행 → calc_response_fit을 회원에게 열 필요 없음
alter function recalc_fit_from_response() security definer set search_path = public;
alter function recalc_fit_from_answer()   security definer set search_path = public;

-- 기본 실행 권한(PUBLIC) 회수 후 필요한 곳만 다시 허용
revoke execute on function
  calc_response_fit(uuid), rank_responses(uuid), request_stats(uuid), submit_opinion(uuid, text), trust_score_of(uuid),
  is_admin(), is_supplier(), owns_request(uuid), supplier_can_see(uuid), supplier_is_selected(uuid), demander_can_see_supplier(uuid),
  supplier_request_feed()
from public, anon;
revoke execute on function calc_response_fit(uuid) from authenticated;

-- 회원(authenticated): 권한 규칙(RLS) 계산에 필요한 도우미 + 화면용 함수
--   도우미들은 모두 "로그인한 본인" 기준 참/거짓만 돌려주므로 다른 사람 정보가 새지 않음
grant execute on function
  is_admin(), is_supplier(), owns_request(uuid), supplier_can_see(uuid), supplier_is_selected(uuid), demander_can_see_supplier(uuid),
  rank_responses(uuid), request_stats(uuid), submit_opinion(uuid, text), trust_score_of(uuid), supplier_request_feed()
to authenticated;

-- 비회원(anon)에게 열어 두는 것: 분야별 건수, 가린 공급사 목록, 금액 계산
grant execute on function public_request_counts(), supplier_directory(), quote_amount(request_kind, int, int[]) to anon, authenticated;

-- 트리거 함수는 직접 호출할 일이 없음 (트리거 실행에는 이 권한이 필요 없음)
revoke execute on function recalc_fit_from_response(), recalc_fit_from_answer() from public, anon, authenticated;

# Supabase 구조

`BM_확정안.md`와 `화면_흐름도.md`를 데이터베이스로 옮긴 것입니다.

## 파일
| 파일 | 내용 |
|---|---|
| `migrations/0001_init.sql` | 테이블, 금액 계산, 범위 비교(●▲✕), 적합도 자동 계산, 권한 규칙(RLS) |
| `migrations/0002_seed_categories.sql` | 카테고리표 1차안 (대분류 8, 중분류 30, 체크리스트 항목, 공정) |
| `migrations/0003_hardening.sql` | 보안 점검 반영: 공급자 피드를 함수로, 비회원 호출 권한 정리, search_path 고정 |
| `migrations/0004_app.sql` | 화면용: 가입 시 회원 정보 자동 생성, 의뢰 제출(금액 서버 계산·제출 후 수정 불가), 관리자 처리(입금 확인·리스트 전달·확정), 이의신청 시 상태 변경 |
| `migrations/0005_storage.sql` | 첨부 파일 저장소 `request-files`와 권한 (실제 Supabase에만 적용) |
| `migrations/0006_status_deposit.sql` | 의뢰 상태 '착수금 입금 대기' 추가 |
| `migrations/0007_projects.sql` | 출시 프로젝트(총 프로젝트·차수·단계), 접수비·착수금·이어하기·기존 파트너 문의 요금, 쿠폰, 착수금 전 미리보기 |
| `migrations/0008_launch_categories.sql` | 디자인, 촬영·상세페이지, 표시사항·인증 대행, 물류 중분류 |
| `migrations/0009_listed_suppliers.sql` | 비회원사 목록(공공데이터·운영사 네트워크): 출처·활동 확인·공개·제외 요청, 둘러보기에 함께 표시, 같은 사업자번호 가입 시 자동 연결, 지정 의뢰 켜고 끄기(`direct_request_enabled`, 기본 꺼짐) |
| `tests/` | 로컬 PostgreSQL로 권한 규칙을 시험하는 파일 (실제 Supabase에는 넣지 않음) |

## 연결된 프로젝트 (2026-11-05 생성)
| 항목 | 값 |
|---|---|
| 프로젝트 | `winwin-connect` (조직 `winwin-connect`, 리전 서울 `ap-northeast-2`, 무료) |
| Project URL | `https://ityavotmbqzatuhaygdg.supabase.co` |
| 공개 키 (publishable) | `sb_publishable_1j6pGXO7xZyX-eeOoY965g_6KgXGnDd` |
| 적용된 마이그레이션 | `init`, `seed_categories`, `hardening`, `app`, `storage`, `status_deposit`, `projects`, `launch_categories` |

공개 키는 홈페이지에 넣는 값이라 공개되어도 괜찮습니다. 데이터 보호는 권한 규칙(RLS)이 합니다.
**service_role 키와 DB 비밀번호는 저장소나 채팅에 절대 넣지 마세요.**

### Supabase 보안 점검(Advisor) 결과
남은 경고는 모두 **의도한 것**입니다.
- 비회원이 호출 가능: `public_request_counts`(분야별 건수), `supplier_directory`(가린 공급사 목록, 회원사+비회원사), `supplier_counts`(회원사·비회원사 수) → 공개하기로 한 기능
- 회원이 호출 가능: 권한 규칙 계산용 도우미(`is_admin` 등, 본인 기준 참/거짓만 반환), `supplier_request_feed`, `request_stats`, `trust_score_of`(본인·관리자 외에는 빈 값), `rank_responses`(관리자 외에는 빈 결과), `submit_opinion`

## 새 프로젝트에 적용하기
1. supabase.com에서 프로젝트 만들기 (리전: Seoul)
2. SQL Editor에서 `0001` → `0009` 순서로 실행 (`0006`은 따로 실행)
3. 첫 관리자 지정: Authentication에서 대표님 계정으로 가입한 뒤 SQL Editor에서
   ```sql
   insert into profiles (id, role, name) values ('<대표님 user id>', 'admin', '권봉구');
   ```

## 시험
**권한 규칙 시험** (로컬 PostgreSQL)
```bash
bash supabase/tests/run.sh
```

**화면 전체 흐름 시험**: 로컬 PostgreSQL 위에서 Supabase를 흉내 내는 시험 서버(`tests/mock_supabase.py`)를 띄우고, Playwright로 출시 프로젝트 전체 흐름(1차 접수·착수금·이의신청·2차 기존 파트너 문의·판매 채널·비회원사 CSV 등록과 둘러보기·지정 의뢰 꺼짐/켜짐) 47개 항목을 확인합니다.
```bash
bash supabase/tests/reset_app_db.sh
```
```bash
su postgres -c "python3 supabase/tests/mock_supabase.py --db wwc_app --port 8787 --root $(pwd)"
```
```bash
node supabase/tests/e2e.js http://localhost:8787
```
비회원, 미인증 공급자, 공급자, 수요자, 관리자로 바꿔 가며 79개 항목(권한 48 + 출시 프로젝트·요금·쿠폰 22 + 비회원사 9)을 확인합니다. 예를 들면 이런 것들입니다.
- 공급자는 수요자 정보를 못 봄
- 신뢰도는 본인과 관리자만 봄
- 선정된 공급자의 연락처만 수요자에게 공개됨
- 선정사 공개 파일은 선정된 공급자만 봄
- 회원이 결제·선정·서명 상태를 직접 바꿀 수 없음

## 금액·기준 바꾸기
`pricing` 테이블의 값만 바꾸면 됩니다: 착수금, 업체 추가비, 검증기간, 응답 기한, 범위 허용 오차(20%).
조건값 가격은 `checklist_items.price`에서 항목별로 바꿉니다.

## 아직 남은 것 (서버 기능, Edge Functions)
| 기능 | 하는 일 |
|---|---|
| 결제 확인 | PG 결제 완료를 확인하고 의뢰를 `open`으로 바꿈, 응답 마감 시각 설정 |
| 환불 | PG 부분취소 호출, `refunds` 기록 |
| 사업자 확인 | 국세청 진위확인 API 호출 후 `biz_verified_at` 기록 |
| 마감 처리 (매시간) | 응답 마감, 지정 의뢰 무응답 환불, 7일 검증기간 끝나면 자동 확정과 신뢰도 +1 |
| 계약서 서명 | 휴대폰 본인인증 → 서명 시각 기록 → PDF 생성, 해시 저장 |
| 알림 | 맞는 의뢰가 올라오면 공급자에게, 리스트 전달·이의신청 시 당사자에게 |
| 파일 저장소 권한 | Storage 버킷 정책 (`request_files`의 공개 범위와 같게) |

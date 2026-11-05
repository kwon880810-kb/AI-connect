# Supabase 구조

`BM_확정안.md`와 `화면_흐름도.md`를 데이터베이스로 옮긴 것입니다.

## 파일
| 파일 | 내용 |
|---|---|
| `migrations/0001_init.sql` | 테이블, 금액 계산, 범위 비교(●▲✕), 적합도 자동 계산, 권한 규칙(RLS) |
| `migrations/0002_seed_categories.sql` | 카테고리표 1차안 (대분류 8, 중분류 30, 체크리스트 항목, 공정) |
| `tests/` | 로컬 PostgreSQL로 권한 규칙을 시험하는 파일 (실제 Supabase에는 넣지 않음) |

## Supabase에 적용하기
1. supabase.com에서 프로젝트 만들기 (리전: Seoul)
2. SQL Editor에서 `0001_init.sql` → `0002_seed_categories.sql` 순서로 실행
3. 첫 관리자 지정: Authentication에서 대표님 계정으로 가입한 뒤 SQL Editor에서
   ```sql
   insert into profiles (id, role, name) values ('<대표님 user id>', 'admin', '권봉구');
   ```

## 시험
```bash
bash supabase/tests/run.sh
```
비회원, 미인증 공급자, 공급자, 수요자, 관리자로 바꿔 가며 49개 항목을 확인합니다. 예를 들면 이런 것들입니다.
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

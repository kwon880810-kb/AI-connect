-- 리스트를 고른 뒤 착수금 입금을 기다리는 상태 (연락처는 아직 비공개)
-- 열거형 값 추가는 다른 변경과 같은 트랜잭션에서 쓸 수 없어 따로 적용합니다.
alter type request_status add value if not exists 'awaiting_deposit' after 'selecting';

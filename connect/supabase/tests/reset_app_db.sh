#!/bin/bash
# 화면 시험용 로컬 DB(wwc_app)를 새로 만들고 관리자 계정(admin@test.kr / password1)을 넣습니다.
set -e
cd "$(dirname "$0")/.."
su postgres -c "psql -qc 'drop database if exists wwc_app' -c 'create database wwc_app'" >/dev/null
for f in tests/00_supabase_stub.sql migrations/0001_init.sql migrations/0002_seed_categories.sql migrations/0003_hardening.sql migrations/0004_app.sql migrations/0006_status_deposit.sql migrations/0007_projects.sql migrations/0008_launch_categories.sql migrations/0009_listed_suppliers.sql tests/01_grants.sql tests/02_admin_seed.sql; do
  su postgres -c "psql -v ON_ERROR_STOP=1 -q -d wwc_app -f $f" >/dev/null
done
echo "wwc_app 준비 완료"

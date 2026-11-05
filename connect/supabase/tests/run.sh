#!/bin/bash
# 로컬 PostgreSQL로 스키마와 권한 규칙을 시험합니다. 사용법: bash supabase/tests/run.sh
set -e
cd "$(dirname "$0")/.."
PSQL="su postgres -c"
$PSQL "psql -qc 'drop database if exists wwc_test' -c 'create database wwc_test'" >/dev/null
for f in tests/00_supabase_stub.sql migrations/0001_init.sql migrations/0002_seed_categories.sql migrations/0003_hardening.sql tests/01_grants.sql tests/10_rls_test.sql; do
  $PSQL "psql -v ON_ERROR_STOP=1 -q -d wwc_test -f $f"
done

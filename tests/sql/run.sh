#!/usr/bin/env bash
# SO_SCHEMA=1 aplica só o schema.sql (instalação nova), sem migracao_v2.sql.
# Aplica stub + schema.sql + migracao_v2.sql e migracao_v3.sql (2x cada, se existirem) num PostgreSQL
# temporário e roda cada tests/sql/[1-9]*.sql. Sai com código != 0 em qualquer falha.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PGBIN="${PGBIN:-/usr/lib/postgresql/16/bin}"
[ -x "$PGBIN/initdb" ] || PGBIN="$(dirname "$(command -v initdb 2>/dev/null || echo /nonexistent/initdb)")"

if [ "$(id -u)" = 0 ]; then RUNAS=(su postgres -s /bin/bash -c); else RUNAS=(bash -c); fi
as_pg() { "${RUNAS[@]}" "$1"; }

TMP="$(mktemp -d)"
chmod 755 "$TMP"
[ "$(id -u)" = 0 ] && chown postgres "$TMP"
DATA="$TMP/data"; SOCK="$TMP/sock"
mkdir -p "$SOCK"; [ "$(id -u)" = 0 ] && chown postgres "$SOCK"
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"

started=0
cleanup() {
  if [ "$started" = 1 ]; then as_pg "'$PGBIN/pg_ctl' -D '$DATA' -m immediate stop" >/dev/null 2>&1; fi
  rm -rf "$TMP"
}
trap cleanup EXIT

as_pg "'$PGBIN/initdb' -D '$DATA' -A trust -E UTF8 --locale=C" >"$TMP/initdb.log" 2>&1 \
  || { cat "$TMP/initdb.log"; echo "FALHA: initdb" >&2; exit 1; }
as_pg "'$PGBIN/pg_ctl' -D '$DATA' -o \"-p $PORT -k '$SOCK' -c listen_addresses=''\" -l '$TMP/pg.log' -w start" >/dev/null 2>&1 \
  || { cat "$TMP/pg.log" 2>/dev/null; echo "FALHA: pg_ctl start" >&2; exit 1; }
started=1

PSQL=("$PGBIN/psql" -h "$SOCK" -p "$PORT" -U postgres -X -q -v ON_ERROR_STOP=1)
"$PGBIN/createdb" -h "$SOCK" -p "$PORT" -U postgres eamsp_test || { echo "FALHA: createdb" >&2; exit 1; }
export PGDATABASE=eamsp_test PGOPTIONS='-c client_min_messages=warning'

apply() {
  local f="$1"
  "${PSQL[@]}" -f "$f" >/dev/null 2>"$TMP/err.log" \
    || { cat "$TMP/err.log" >&2; echo "FALHA ao aplicar: ${f#$ROOT/}" >&2; exit 1; }
}

apply "$ROOT/tests/sql/00_stub.sql"
apply "$ROOT/schema.sql"
if [ -z "${SO_SCHEMA:-}" ] && [ -f "$ROOT/migracao_v2.sql" ]; then
  apply "$ROOT/migracao_v2.sql"
  apply "$ROOT/migracao_v2.sql"   # idempotência
  if [ -f "$ROOT/migracao_v3.sql" ]; then
    apply "$ROOT/migracao_v3.sql"
    apply "$ROOT/migracao_v3.sql"   # idempotência
  fi
fi

fail=0; n=0
for t in "$ROOT"/tests/sql/[1-9]*.sql; do
  [ -e "$t" ] || continue
  n=$((n+1))
  if ! "${PSQL[@]}" -f "$t" >"$TMP/out.log" 2>&1; then
    cat "$TMP/out.log" >&2
    echo "FALHOU: ${t#$ROOT/}" >&2
    fail=1
  fi
done
[ "$fail" = 0 ] && echo "SQL: schema aplicado, $n teste(s) ok"
exit "$fail"

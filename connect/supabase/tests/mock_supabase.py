"""
로컬 시험용 '가짜 Supabase' 서버 (개발 전용, 운영에는 쓰지 않음)

- 로컬 PostgreSQL(마이그레이션 적용본) 위에서 Supabase의 일부 기능을 흉내 냅니다.
  * 인증:   /auth/v1/signup, /auth/v1/token (password, refresh_token), /auth/v1/user, /auth/v1/logout
  * 데이터: /rest/v1/<table>  (select, 필터 eq/neq/gt/gte/lt/lte/in/is/ilike, order, limit, insert, upsert, update, delete)
  * 함수:   /rest/v1/rpc/<function>
  * 파일:   /storage/v1/object/<bucket>/<path> 업로드, /storage/v1/object/sign/... 서명 주소
- 모든 데이터 요청은 실제 Supabase처럼 anon/authenticated 역할 + 사용자 ID로 실행되므로 권한 규칙(RLS)이 그대로 적용됩니다.
- 홈페이지 파일도 같은 주소에서 제공합니다. js/config.js의 Supabase 주소는 이 서버 주소로 바꿔서 내보냅니다.

사용법: python3 mock_supabase.py --db wwc_app --port 8787 --root ../..
"""
import argparse, base64, datetime, decimal, hashlib, hmac, json, mimetypes, os, re, secrets, sys, uuid
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qsl, unquote

import psycopg2
from psycopg2 import sql
from psycopg2.extras import Json, register_default_jsonb

ap = argparse.ArgumentParser()
ap.add_argument("--db", default="wwc_app")
ap.add_argument("--port", type=int, default=8787)
ap.add_argument("--root", default=os.path.join(os.path.dirname(__file__), "..", ".."))
ap.add_argument("--files", default="/tmp/mock_storage")
args = ap.parse_args()

ANON_KEY = "mock-anon-key"
SECRET = b"mock-secret"
os.makedirs(args.files, exist_ok=True)
register_default_jsonb(loads=lambda x: json.loads(x))


def connect():
    return psycopg2.connect(dbname=args.db, user="postgres", host="/var/run/postgresql")


def to_json(o):
    if isinstance(o, (datetime.datetime, datetime.date)):
        return o.isoformat()
    if isinstance(o, decimal.Decimal):
        return float(o)
    if isinstance(o, uuid.UUID):
        return str(o)
    if isinstance(o, memoryview):
        return o.tobytes().decode()
    raise TypeError(type(o))


def adapt(v):
    return Json(v) if isinstance(v, dict) else v


class ApiError(Exception):
    def __init__(self, status, message, code=None):
        super().__init__(message)
        self.status, self.message, self.code = status, message, code


# ---------------------------------------------------------------- 인증
def make_session(user_id, email):
    return {
        "access_token": "mock." + str(user_id),
        "token_type": "bearer",
        "expires_in": 3600,
        "expires_at": int(datetime.datetime.now().timestamp()) + 3600,
        "refresh_token": "refresh." + str(user_id),
        "user": user_obj(user_id, email),
    }


def user_obj(user_id, email, meta=None):
    return {"id": str(user_id), "aud": "authenticated", "role": "authenticated", "email": email,
            "email_confirmed_at": datetime.datetime.now().isoformat(), "app_metadata": {"provider": "email"},
            "user_metadata": meta or {}, "created_at": datetime.datetime.now().isoformat()}


def pw_hash(pw):
    return hashlib.sha256(("mock:" + pw).encode()).hexdigest()


def user_from_token(token):
    if not token or token == ANON_KEY:
        return None
    if token.startswith("mock."):
        return token[5:]
    raise ApiError(401, "invalid token")


# ---------------------------------------------------------------- REST
OPS = {"eq": "=", "neq": "<>", "gt": ">", "gte": ">=", "lt": "<", "lte": "<=", "like": "like", "ilike": "ilike"}
RESERVED = {"select", "order", "limit", "offset", "on_conflict", "columns"}


def parse_filters(params):
    clauses, values = [], []
    for k, v in params:
        if k in RESERVED:
            continue
        neg = False
        op, _, val = v.partition(".")
        if op == "not":
            neg = True
            op, _, val = val.partition(".")
        col = sql.Identifier(k)
        if op in OPS:
            if op in ("like", "ilike"):
                val = val.replace("*", "%")
            c = sql.SQL("{} {} %s").format(col, sql.SQL(OPS[op]))
            values.append(val)
        elif op == "in":
            items = [x.strip().strip('"') for x in val.strip("()").split(",") if x.strip()]
            c = sql.SQL("{}::text = any(%s)").format(col)
            values.append(items)
        elif op == "is":
            c = sql.SQL("{} is {}").format(col, sql.SQL({"null": "null", "true": "true", "false": "false"}[val]))
        else:
            raise ApiError(400, "unsupported filter " + op)
        clauses.append(sql.SQL("not ({})").format(c) if neg else c)
    where = sql.SQL(" where ") + sql.SQL(" and ").join(clauses) if clauses else sql.SQL("")
    return where, values


def select_list(s):
    if not s or s == "*":
        return sql.SQL("*")
    cols = [c.strip() for c in s.split(",") if c.strip()]
    for c in cols:
        if "(" in c or ":" in c:
            raise ApiError(400, "embedded resources are not supported by the mock: " + c)
    return sql.SQL(", ").join(sql.Identifier(c) for c in cols)


def order_clause(o):
    if not o:
        return sql.SQL("")
    parts = []
    for item in o.split(","):
        bits = item.split(".")
        col = sql.Identifier(bits[0])
        direction = "desc" if "desc" in bits[1:] else "asc"
        nulls = " nulls first" if "nullsfirst" in bits else (" nulls last" if "nullslast" in bits else "")
        parts.append(sql.SQL("{} " + direction + nulls).format(col))
    return sql.SQL(" order by ") + sql.SQL(", ").join(parts)


def run(uid, fn):
    conn = connect()
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute("set local role " + ("authenticated" if uid else "anon"))
                cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
                return fn(cur)
    except psycopg2.Error as e:
        msg = (e.diag.message_primary or str(e)) if e.diag else str(e)
        code = e.pgcode
        status = 403 if code == "42501" else 409 if code == "23505" else 400
        raise ApiError(status, msg, code)
    finally:
        conn.close()


def rows(cur):
    if cur.description is None:
        return []
    names = [d.name for d in cur.description]
    return [dict(zip(names, r)) for r in cur.fetchall()]


def rest_table(method, table, params, body, headers, uid):
    tbl = sql.Identifier(table)
    q = dict(params)
    where, wvals = parse_filters(params)
    prefer = headers.get("Prefer", "")
    want_rep = "return=representation" in prefer

    def go(cur):
        if method == "GET" or method == "HEAD":
            stmt = sql.SQL("select {} from {}").format(select_list(q.get("select")), tbl) + where + order_clause(q.get("order"))
            vals = list(wvals)
            if "limit" in q:
                stmt += sql.SQL(" limit %s"); vals.append(int(q["limit"]))
            if "offset" in q:
                stmt += sql.SQL(" offset %s"); vals.append(int(q["offset"]))
            cur.execute(stmt, vals)
            return rows(cur)
        if method == "POST":
            items = body if isinstance(body, list) else [body]
            out = []
            for it in items:
                cols = list(it.keys())
                stmt = sql.SQL("insert into {} ({}) values ({})").format(
                    tbl, sql.SQL(", ").join(map(sql.Identifier, cols)), sql.SQL(", ").join(sql.Placeholder() * len(cols)))
                if "resolution=merge-duplicates" in prefer and q.get("on_conflict"):
                    conflict = [c.strip() for c in q["on_conflict"].split(",")]
                    upd = [c for c in cols if c not in conflict]
                    stmt += sql.SQL(" on conflict ({}) do ").format(sql.SQL(", ").join(map(sql.Identifier, conflict)))
                    stmt += (sql.SQL("update set ") + sql.SQL(", ").join(
                        sql.SQL("{0} = excluded.{0}").format(sql.Identifier(c)) for c in upd)) if upd else sql.SQL("nothing")
                elif "resolution=ignore-duplicates" in prefer:
                    stmt += sql.SQL(" on conflict do nothing")
                if want_rep:  # PostgREST도 return=representation일 때만 RETURNING (SELECT 권한 필요)
                    stmt += sql.SQL(" returning {}").format(select_list(q.get("select")))
                cur.execute(stmt, [adapt(it[c]) for c in cols])
                if want_rep:
                    out += rows(cur)
            return out if want_rep else None
        if method == "PATCH":
            cols = list(body.keys())
            stmt = sql.SQL("update {} set {}").format(tbl, sql.SQL(", ").join(
                sql.SQL("{} = %s").format(sql.Identifier(c)) for c in cols)) + where
            if want_rep:
                stmt += sql.SQL(" returning {}").format(select_list(q.get("select")))
            cur.execute(stmt, [adapt(body[c]) for c in cols] + wvals)
            return rows(cur) if want_rep else None
        if method == "DELETE":
            stmt = sql.SQL("delete from {}").format(tbl) + where + (sql.SQL(" returning *") if want_rep else sql.SQL(""))
            cur.execute(stmt, wvals)
            return rows(cur) if want_rep else None
        raise ApiError(405, "method not allowed")

    return run(uid, go)


def rest_rpc(fname, body, uid):
    def go(cur):
        cur.execute("""select p.proargnames, array(select format_type(t, null) from unnest(p.proargtypes) t), p.proretset,
                              format_type(p.prorettype, null)
                       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                       where n.nspname = 'public' and p.proname = %s""", (fname,))
        r = cur.fetchone()
        if not r:
            raise ApiError(404, "function not found: " + fname)
        names, types, retset, rettype = r
        names = names or []
        given = body or {}
        parts, vals = [], []
        for n, t in zip(names, types):
            if n in given:
                parts.append(sql.SQL("{} := %s::" + t).format(sql.Identifier(n)))
                vals.append(adapt(given[n]))
        call = sql.SQL("{}({})").format(sql.Identifier(fname), sql.SQL(", ").join(parts))
        if retset:
            cur.execute(sql.SQL("select * from ") + call, vals)
            return rows(cur)
        cur.execute(sql.SQL("select ") + call + sql.SQL(" as result"), vals)
        v = cur.fetchone()[0]
        return None if rettype == "void" else v

    return run(uid, go)


# ---------------------------------------------------------------- 저장소
def sign(path):
    return hmac.new(SECRET, path.encode(), hashlib.sha256).hexdigest()[:32]


def storage_can_read(uid, path):
    def go(cur):
        cur.execute("select is_admin() or exists (select 1 from request_files where path = %s)", (path,))
        return cur.fetchone()[0]
    return uid and run(uid, go)


def storage_can_write(uid, path):
    first = path.split("/")[0]
    def go(cur):
        cur.execute("select is_admin() or owns_request(%s::uuid)", (first,))
        return cur.fetchone()[0]
    try:
        return uid and run(uid, go)
    except ApiError:
        return False


def parse_multipart(body, ctype):
    m = re.search(r'boundary="?([^";]+)"?', ctype)
    if not m:
        return body
    boundary = ("--" + m.group(1)).encode()
    for part in body.split(boundary):
        head, _, data = part.partition(b"\r\n\r\n")
        if b"filename=" in head:
            return data[:-2] if data.endswith(b"\r\n") else data
    return b""


# ---------------------------------------------------------------- HTTP
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def send(self, status, payload=None, ctype="application/json", raw=None):
        data = raw if raw is not None else (b"" if payload is None else json.dumps(payload, default=to_json).encode())
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "*")
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send(204)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def token(self):
        a = self.headers.get("Authorization", "")
        return a[7:] if a.lower().startswith("bearer ") else self.headers.get("apikey")

    def handle_any(self, method):
        u = urlparse(self.path)
        path = unquote(u.path)
        params = parse_qsl(u.query, keep_blank_values=True)
        try:
            if path.startswith("/auth/v1/"):
                return self.auth(method, path[9:], dict(params))
            if path.startswith("/rest/v1/"):
                uid = user_from_token(self.token())
                raw = self.body()
                body = json.loads(raw) if raw else None
                name = path[9:]
                if name.startswith("rpc/"):
                    res = rest_rpc(name[4:], body, uid)
                    return self.send(200, res) if res is not None else self.send(204)
                res = rest_table(method, name, params, body, self.headers, uid)
                if res is None:
                    return self.send(201 if method == "POST" else 204)
                if "vnd.pgrst.object" in self.headers.get("Accept", ""):
                    if len(res) != 1:
                        raise ApiError(406, "JSON object requested, multiple (or no) rows returned", "PGRST116")
                    return self.send(200, res[0])
                return self.send(201 if method == "POST" else 200, res)
            if path.startswith("/storage/v1/"):
                return self.storage(method, path[12:], dict(params))
            return self.static(path)
        except ApiError as e:
            return self.send(e.status, {"message": e.message, "code": e.code, "error": e.message, "msg": e.message})

    def auth(self, method, ep, q):
        conn = connect(); conn.autocommit = True
        cur = conn.cursor()
        try:
            if ep == "signup":
                b = json.loads(self.body() or b"{}")
                cur.execute("select 1 from auth.users where email = %s", (b.get("email"),))
                if cur.fetchone():
                    raise ApiError(422, "User already registered")
                uid = str(uuid.uuid4())
                cur.execute("insert into auth.users (id, email, encrypted_password, raw_user_meta_data) values (%s, %s, %s, %s)",
                            (uid, b["email"], pw_hash(b["password"]), Json(b.get("data") or {})))
                return self.send(200, make_session(uid, b["email"]))
            if ep == "token":
                b = json.loads(self.body() or b"{}")
                if q.get("grant_type") == "password":
                    cur.execute("select id, email from auth.users where email = %s and encrypted_password = %s",
                                (b.get("email"), pw_hash(b.get("password", ""))))
                    r = cur.fetchone()
                    if not r:
                        raise ApiError(400, "Invalid login credentials")
                    return self.send(200, make_session(r[0], r[1]))
                if q.get("grant_type") == "refresh_token":
                    uid = b.get("refresh_token", "")[8:]
                    cur.execute("select id, email from auth.users where id::text = %s", (uid,))
                    r = cur.fetchone()
                    if not r:
                        raise ApiError(400, "Invalid refresh token")
                    return self.send(200, make_session(r[0], r[1]))
            if ep == "user":
                uid = user_from_token(self.token())
                cur.execute("select id, email, raw_user_meta_data from auth.users where id::text = %s", (uid,))
                r = cur.fetchone()
                if not r:
                    raise ApiError(401, "not logged in")
                return self.send(200, user_obj(*r))
            if ep == "logout":
                self.body()
                return self.send(204)
            raise ApiError(404, "unknown auth endpoint " + ep)
        finally:
            conn.close()

    def storage(self, method, ep, q):
        uid = user_from_token(self.token()) if not ep.startswith("object/sign/") or method == "POST" else None
        if ep.startswith("object/sign/"):
            rest = ep[len("object/sign/"):]
            bucket, _, path = rest.partition("/")
            if method == "POST":
                self.body()
                if not storage_can_read(uid, path):
                    raise ApiError(400, "Object not found")
                return self.send(200, {"signedURL": f"/object/sign/{bucket}/{path}?token={sign(path)}"})
            if q.get("token") != sign(path):
                raise ApiError(400, "invalid signature")
            fp = os.path.join(args.files, bucket, path)
            if not os.path.exists(fp):
                raise ApiError(404, "not found")
            return self.send(200, raw=open(fp, "rb").read(), ctype=mimetypes.guess_type(fp)[0] or "application/octet-stream")
        if ep.startswith("object/") and method in ("POST", "PUT"):
            bucket, _, path = ep[7:].partition("/")
            data = self.body()
            if not storage_can_write(uid, path):
                raise ApiError(403, "new row violates row-level security policy")
            data = parse_multipart(data, self.headers.get("Content-Type", ""))
            fp = os.path.join(args.files, bucket, path)
            os.makedirs(os.path.dirname(fp), exist_ok=True)
            open(fp, "wb").write(data)
            return self.send(200, {"Key": f"{bucket}/{path}", "Id": str(uuid.uuid4())})
        raise ApiError(404, "unknown storage endpoint")

    def static(self, path):
        if path.endswith("/"):
            path += "index.html"
        fp = os.path.normpath(os.path.join(args.root, path.lstrip("/")))
        if not fp.startswith(os.path.normpath(args.root)) or not os.path.isfile(fp):
            return self.send(404, raw=b"not found", ctype="text/plain")
        data = open(fp, "rb").read()
        if path.endswith("js/config.js"):
            origin = f"http://localhost:{args.port}"
            data = re.sub(rb'supabaseUrl:\s*"[^"]*"', f'supabaseUrl: "{origin}"'.encode(), data)
            data = re.sub(rb'supabaseKey:\s*"[^"]*"', f'supabaseKey: "{ANON_KEY}"'.encode(), data)
        self.send(200, raw=data, ctype=(mimetypes.guess_type(fp)[0] or "application/octet-stream") + ("; charset=utf-8" if fp.endswith((".html", ".js", ".css")) else ""))

    def do_GET(self): self.handle_any("GET")
    def do_POST(self): self.handle_any("POST")
    def do_PATCH(self): self.handle_any("PATCH")
    def do_PUT(self): self.handle_any("PUT")
    def do_DELETE(self): self.handle_any("DELETE")
    def do_HEAD(self): self.handle_any("HEAD")


if __name__ == "__main__":
    print(f"mock supabase on http://localhost:{args.port} (db={args.db}, root={os.path.abspath(args.root)})", flush=True)
    ThreadingHTTPServer(("127.0.0.1", args.port), H).serve_forever()

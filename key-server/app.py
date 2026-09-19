import csv
import hashlib
import hmac
import io
import os
import secrets
import sqlite3
import string
from datetime import datetime, timedelta, timezone
from functools import wraps
from pathlib import Path
from zoneinfo import ZoneInfo

from dotenv import load_dotenv
from flask import (
    Flask,
    Response,
    abort,
    flash,
    g,
    jsonify,
    redirect,
    render_template,
    request,
    session,
    url_for,
)

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent
DB_PATH = Path(os.getenv("DATABASE_PATH", str(BASE_DIR / "data" / "keys.db")))
DB_PATH.parent.mkdir(parents=True, exist_ok=True)

VN_TZ = ZoneInfo("Asia/Ho_Chi_Minh")
UTC = timezone.utc

app = Flask(__name__)
app.secret_key = os.getenv("SECRET_KEY", secrets.token_hex(32))
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=os.getenv("COOKIE_SECURE", "0") == "1",
)

ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD", "CHANGE-ME-NOW")
APP_NAME = os.getenv("APP_NAME", "Tizi Mod")
KEY_PREFIX = os.getenv("KEY_PREFIX", "TIZI")


def utcnow() -> datetime:
    return datetime.now(UTC)


def iso(dt: datetime | None) -> str | None:
    if not dt:
        return None
    return dt.astimezone(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(UTC)
    except ValueError:
        return None


def format_vn(value: str | None) -> str:
    dt = parse_iso(value)
    if not dt:
        return "—"
    return dt.astimezone(VN_TZ).strftime("%d/%m/%Y %H:%M:%S")


def duration_seconds(value: int, unit: str) -> int:
    multipliers = {
        "hours": 3600,
        "days": 86400,
        "weeks": 7 * 86400,
        "months": 30 * 86400,
    }
    if unit not in multipliers:
        raise ValueError("Đơn vị thời gian không hợp lệ")
    if value <= 0:
        raise ValueError("Thời lượng phải lớn hơn 0")
    return value * multipliers[unit]


def human_duration(seconds: int) -> str:
    if seconds <= 0:
        return "0 phút"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    parts = []
    if days:
        parts.append(f"{days} ngày")
    if hours:
        parts.append(f"{hours} giờ")
    if minutes and len(parts) < 2:
        parts.append(f"{minutes} phút")
    return " ".join(parts[:2]) or "< 1 phút"


def mask_key(key: str) -> str:
    parts = key.split("-")
    if len(parts) >= 4:
        return f"{parts[0]}-{parts[1]}-••••-{parts[-1]}"
    if len(key) <= 8:
        return key[:2] + "••••" + key[-2:]
    return key[:6] + "••••••" + key[-4:]


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def generate_key(prefix: str = KEY_PREFIX) -> str:
    alphabet = string.ascii_uppercase + string.digits
    prefix = "".join(ch for ch in prefix.upper() if ch.isalnum())[:10] or "TIZI"
    groups = ["".join(secrets.choice(alphabet) for _ in range(4)) for _ in range(3)]
    return "-".join([prefix, *groups])


def get_db() -> sqlite3.Connection:
    if "db" not in g:
        conn = sqlite3.connect(DB_PATH, timeout=30)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        g.db = conn
    return g.db


@app.teardown_appcontext
def close_db(_exc=None):
    conn = g.pop("db", None)
    if conn is not None:
        conn.close()


def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute("PRAGMA foreign_keys=ON")
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS license_keys (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key_code TEXT NOT NULL UNIQUE,
            enabled INTEGER NOT NULL DEFAULT 1,
            duration_seconds INTEGER NOT NULL,
            starts_on_first_use INTEGER NOT NULL DEFAULT 1,
            created_at TEXT NOT NULL,
            first_activated_at TEXT,
            expires_at TEXT,
            max_devices INTEGER NOT NULL DEFAULT 1,
            note TEXT NOT NULL DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS key_devices (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key_id INTEGER NOT NULL,
            device_id TEXT NOT NULL,
            device_model TEXT NOT NULL DEFAULT '',
            app_version TEXT NOT NULL DEFAULT '',
            first_seen TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            UNIQUE(key_id, device_id),
            FOREIGN KEY(key_id) REFERENCES license_keys(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS key_sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key_id INTEGER NOT NULL,
            device_id TEXT NOT NULL,
            token_hash TEXT NOT NULL UNIQUE,
            created_at TEXT NOT NULL,
            last_seen TEXT NOT NULL,
            FOREIGN KEY(key_id) REFERENCES license_keys(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS key_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            key_id INTEGER,
            event_type TEXT NOT NULL,
            device_id TEXT NOT NULL DEFAULT '',
            detail TEXT NOT NULL DEFAULT '',
            created_at TEXT NOT NULL,
            FOREIGN KEY(key_id) REFERENCES license_keys(id) ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS idx_devices_key_id ON key_devices(key_id);
        CREATE INDEX IF NOT EXISTS idx_sessions_token ON key_sessions(token_hash);
        CREATE INDEX IF NOT EXISTS idx_events_key_id ON key_events(key_id);
        """
    )
    conn.commit()
    conn.close()


init_db()


def log_event(key_id: int | None, event_type: str, device_id: str = "", detail: str = ""):
    db = get_db()
    db.execute(
        "INSERT INTO key_events(key_id,event_type,device_id,detail,created_at) VALUES(?,?,?,?,?)",
        (key_id, event_type, device_id, detail[:500], iso(utcnow())),
    )


def key_runtime_state(row: sqlite3.Row) -> str:
    if not row["enabled"]:
        return "disabled"
    exp = parse_iso(row["expires_at"])
    if exp and exp <= utcnow():
        return "expired"
    if not row["first_activated_at"]:
        return "unused"
    return "active"


def remaining_seconds(row: sqlite3.Row) -> int | None:
    exp = parse_iso(row["expires_at"])
    if not exp:
        return None
    return max(0, int((exp - utcnow()).total_seconds()))


def csrf_token() -> str:
    if "csrf_token" not in session:
        session["csrf_token"] = secrets.token_urlsafe(24)
    return session["csrf_token"]


app.jinja_env.globals.update(
    csrf_token=csrf_token,
    format_vn=format_vn,
    human_duration=human_duration,
    mask_key=mask_key,
)


def admin_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        if not session.get("admin"):
            return redirect(url_for("admin_login", next=request.path))
        if request.method == "POST":
            sent = request.form.get("csrf_token", "")
            expected = session.get("csrf_token", "")
            if not sent or not expected or not hmac.compare_digest(sent, expected):
                abort(400, "CSRF token không hợp lệ")
        return fn(*args, **kwargs)
    return wrapper


@app.get("/")
def root():
    return jsonify({"ok": True, "service": f"{APP_NAME} Key Server", "version": 1})


@app.post("/api/v1/activate")
def api_activate():
    payload = request.get_json(silent=True) or {}
    key_code = str(payload.get("key", "")).strip().upper()
    device_id = str(payload.get("deviceID", "")).strip()
    device_model = str(payload.get("deviceModel", ""))[:120]
    app_version = str(payload.get("appVersion", ""))[:40]

    if not key_code or not device_id:
        return jsonify(success=False, message="Thiếu key hoặc mã thiết bị."), 400

    db = get_db()
    row = db.execute("SELECT * FROM license_keys WHERE key_code=?", (key_code,)).fetchone()
    if not row:
        return jsonify(success=False, message="Key không tồn tại."), 404
    if not row["enabled"]:
        log_event(row["id"], "activation_denied_disabled", device_id)
        db.commit()
        return jsonify(success=False, message="Key đã bị khóa."), 403

    now = utcnow()
    exp = parse_iso(row["expires_at"])

    if row["starts_on_first_use"] and not row["first_activated_at"]:
        exp = now + timedelta(seconds=int(row["duration_seconds"]))
        db.execute(
            "UPDATE license_keys SET first_activated_at=?, expires_at=? WHERE id=?",
            (iso(now), iso(exp), row["id"]),
        )
        row = db.execute("SELECT * FROM license_keys WHERE id=?", (row["id"],)).fetchone()

    if exp and exp <= now:
        log_event(row["id"], "activation_denied_expired", device_id)
        db.commit()
        return jsonify(success=False, message="Key đã hết hạn."), 403

    if not row["first_activated_at"]:
        db.execute("UPDATE license_keys SET first_activated_at=? WHERE id=?", (iso(now), row["id"]))
        row = db.execute("SELECT * FROM license_keys WHERE id=?", (row["id"],)).fetchone()

    existing_device = db.execute(
        "SELECT * FROM key_devices WHERE key_id=? AND device_id=?",
        (row["id"], device_id),
    ).fetchone()

    if not existing_device:
        count = db.execute("SELECT COUNT(*) AS c FROM key_devices WHERE key_id=?", (row["id"],)).fetchone()["c"]
        if count >= int(row["max_devices"]):
            log_event(row["id"], "activation_denied_device_limit", device_id)
            db.commit()
            return jsonify(success=False, message="Key đã đạt giới hạn thiết bị."), 403
        db.execute(
            "INSERT INTO key_devices(key_id,device_id,device_model,app_version,first_seen,last_seen) VALUES(?,?,?,?,?,?)",
            (row["id"], device_id, device_model, app_version, iso(now), iso(now)),
        )
    else:
        db.execute(
            "UPDATE key_devices SET device_model=?, app_version=?, last_seen=? WHERE id=?",
            (device_model, app_version, iso(now), existing_device["id"]),
        )

    token = secrets.token_urlsafe(40)
    db.execute(
        "INSERT INTO key_sessions(key_id,device_id,token_hash,created_at,last_seen) VALUES(?,?,?,?,?)",
        (row["id"], device_id, token_hash(token), iso(now), iso(now)),
    )
    log_event(row["id"], "activated", device_id, f"{device_model} / {app_version}")
    db.commit()

    row = db.execute("SELECT * FROM license_keys WHERE id=?", (row["id"],)).fetchone()
    return jsonify(
        success=True,
        token=token,
        message="Kích hoạt thành công.",
        key_masked=mask_key(row["key_code"]),
        expires_at=row["expires_at"],
        remaining_seconds=remaining_seconds(row),
        status=key_runtime_state(row),
    )


def session_from_bearer():
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return None
    token = auth[7:].strip()
    if not token:
        return None
    db = get_db()
    return db.execute(
        """
        SELECT s.id AS session_id, s.device_id, s.key_id, k.*
        FROM key_sessions s
        JOIN license_keys k ON k.id=s.key_id
        WHERE s.token_hash=?
        """,
        (token_hash(token),),
    ).fetchone()


@app.get("/api/v1/status")
def api_status():
    row = session_from_bearer()
    if not row:
        return jsonify(success=False, message="Phiên key không hợp lệ."), 401

    state = key_runtime_state(row)
    if state in {"disabled", "expired"}:
        db = get_db()
        log_event(row["key_id"], f"session_revoked_{state}", row["device_id"])
        db.execute("DELETE FROM key_sessions WHERE id=?", (row["session_id"],))
        db.commit()
        message = "Key đã bị khóa." if state == "disabled" else "Key đã hết hạn."
        return jsonify(success=False, message=message, status=state), 403

    db = get_db()
    now = iso(utcnow())
    db.execute("UPDATE key_sessions SET last_seen=? WHERE id=?", (now, row["session_id"]))
    db.execute(
        "UPDATE key_devices SET last_seen=? WHERE key_id=? AND device_id=?",
        (now, row["key_id"], row["device_id"]),
    )
    db.commit()

    devices = db.execute("SELECT COUNT(*) AS c FROM key_devices WHERE key_id=?", (row["key_id"],)).fetchone()["c"]
    return jsonify(
        success=True,
        message="Key đang hoạt động.",
        key_masked=mask_key(row["key_code"]),
        expires_at=row["expires_at"],
        remaining_seconds=remaining_seconds(row),
        status=state,
        devices=devices,
        max_devices=row["max_devices"],
    )


@app.post("/api/v1/logout")
def api_logout():
    row = session_from_bearer()
    if row:
        db = get_db()
        db.execute("DELETE FROM key_sessions WHERE id=?", (row["session_id"],))
        log_event(row["key_id"], "logout", row["device_id"])
        db.commit()
    return jsonify(success=True)


@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    if request.method == "POST":
        password = request.form.get("password", "")
        if hmac.compare_digest(password, ADMIN_PASSWORD):
            session.clear()
            session["admin"] = True
            csrf_token()
            return redirect(url_for("admin_dashboard"))
        flash("Sai mật khẩu quản trị.", "error")
    return render_template("login.html", app_name=APP_NAME)


@app.post("/admin/logout")
@admin_required
def admin_logout():
    session.clear()
    return redirect(url_for("admin_login"))


@app.get("/admin")
@admin_required
def admin_dashboard():
    db = get_db()
    q = request.args.get("q", "").strip()
    state_filter = request.args.get("state", "all")

    sql = """
        SELECT k.*,
               (SELECT COUNT(*) FROM key_devices d WHERE d.key_id=k.id) AS device_count,
               (SELECT COUNT(*) FROM key_sessions s WHERE s.key_id=k.id) AS session_count
        FROM license_keys k
    """
    params = []
    if q:
        sql += " WHERE (k.key_code LIKE ? OR k.note LIKE ?)"
        params.extend([f"%{q.upper()}%", f"%{q}%"])
    sql += " ORDER BY k.id DESC"
    rows = db.execute(sql, params).fetchall()

    keys = []
    for row in rows:
        state = key_runtime_state(row)
        if state_filter != "all" and state != state_filter:
            continue
        item = dict(row)
        item["runtime_state"] = state
        item["remaining"] = remaining_seconds(row)
        keys.append(item)

    all_rows = db.execute("SELECT * FROM license_keys").fetchall()
    stats = {
        "total": len(all_rows),
        "active": sum(key_runtime_state(r) == "active" for r in all_rows),
        "unused": sum(key_runtime_state(r) == "unused" for r in all_rows),
        "expired": sum(key_runtime_state(r) == "expired" for r in all_rows),
        "disabled": sum(key_runtime_state(r) == "disabled" for r in all_rows),
    }
    recent_events = db.execute(
        """
        SELECT e.*, k.key_code FROM key_events e
        LEFT JOIN license_keys k ON k.id=e.key_id
        ORDER BY e.id DESC LIMIT 30
        """
    ).fetchall()

    return render_template(
        "admin.html",
        app_name=APP_NAME,
        keys=keys,
        stats=stats,
        q=q,
        state_filter=state_filter,
        recent_events=recent_events,
    )


@app.post("/admin/keys/create")
@admin_required
def admin_create_keys():
    try:
        quantity = max(1, min(int(request.form.get("quantity", "1")), 100))
        amount = int(request.form.get("amount", "1"))
        unit = request.form.get("unit", "days")
        seconds = duration_seconds(amount, unit)
        max_devices = max(1, min(int(request.form.get("max_devices", "1")), 20))
        starts_on_first_use = request.form.get("starts_on_first_use") == "on"
        prefix = request.form.get("prefix", KEY_PREFIX)
        note = request.form.get("note", "").strip()[:250]
    except (ValueError, TypeError) as exc:
        flash(str(exc), "error")
        return redirect(url_for("admin_dashboard"))

    db = get_db()
    now = utcnow()
    created = []
    for _ in range(quantity):
        for _attempt in range(20):
            key_code = generate_key(prefix)
            try:
                expires = None if starts_on_first_use else iso(now + timedelta(seconds=seconds))
                cur = db.execute(
                    """
                    INSERT INTO license_keys(key_code,enabled,duration_seconds,starts_on_first_use,created_at,expires_at,max_devices,note)
                    VALUES(?,1,?,?,?,?,?,?)
                    """,
                    (key_code, seconds, int(starts_on_first_use), iso(now), expires, max_devices, note),
                )
                log_event(cur.lastrowid, "created", detail=f"{human_duration(seconds)}, {max_devices} thiết bị")
                created.append(key_code)
                break
            except sqlite3.IntegrityError:
                continue
    db.commit()
    flash(f"Đã tạo {len(created)} key.", "success")
    return redirect(url_for("admin_dashboard"))


@app.post("/admin/keys/<int:key_id>/toggle")
@admin_required
def admin_toggle_key(key_id: int):
    db = get_db()
    row = db.execute("SELECT * FROM license_keys WHERE id=?", (key_id,)).fetchone() or abort(404)
    new_value = 0 if row["enabled"] else 1
    db.execute("UPDATE license_keys SET enabled=? WHERE id=?", (new_value, key_id))
    if not new_value:
        db.execute("DELETE FROM key_sessions WHERE key_id=?", (key_id,))
    log_event(key_id, "enabled" if new_value else "disabled")
    db.commit()
    flash("Đã mở khóa key." if new_value else "Đã khóa key.", "success")
    return redirect(request.referrer or url_for("admin_dashboard"))


@app.post("/admin/keys/<int:key_id>/add-time")
@admin_required
def admin_add_time(key_id: int):
    db = get_db()
    row = db.execute("SELECT * FROM license_keys WHERE id=?", (key_id,)).fetchone() or abort(404)
    try:
        amount = int(request.form.get("amount", "1"))
        unit = request.form.get("unit", "hours")
        delta = duration_seconds(abs(amount), unit)
        if amount < 0:
            delta *= -1
    except (ValueError, TypeError) as exc:
        flash(str(exc), "error")
        return redirect(request.referrer or url_for("admin_dashboard"))

    exp = parse_iso(row["expires_at"])
    if exp:
        if delta > 0 and exp < utcnow():
            exp = utcnow()
        new_exp = exp + timedelta(seconds=delta)
        db.execute("UPDATE license_keys SET expires_at=? WHERE id=?", (iso(new_exp), key_id))
    else:
        new_duration = max(60, int(row["duration_seconds"]) + delta)
        db.execute("UPDATE license_keys SET duration_seconds=? WHERE id=?", (new_duration, key_id))
    log_event(key_id, "time_adjusted", detail=f"{amount} {unit}")
    db.commit()
    flash("Đã cập nhật thời gian key.", "success")
    return redirect(request.referrer or url_for("admin_dashboard"))


@app.post("/admin/keys/<int:key_id>/set-expiry")
@admin_required
def admin_set_expiry(key_id: int):
    value = request.form.get("expiry", "").strip()
    if not value:
        flash("Hãy chọn ngày giờ hết hạn.", "error")
        return redirect(request.referrer or url_for("admin_dashboard"))
    try:
        local_dt = datetime.strptime(value, "%Y-%m-%dT%H:%M").replace(tzinfo=VN_TZ)
        exp = local_dt.astimezone(UTC)
    except ValueError:
        flash("Ngày giờ không hợp lệ.", "error")
        return redirect(request.referrer or url_for("admin_dashboard"))
    db = get_db()
    db.execute("UPDATE license_keys SET expires_at=? WHERE id=?", (iso(exp), key_id))
    log_event(key_id, "expiry_set", detail=format_vn(iso(exp)))
    db.commit()
    flash("Đã đặt ngày hết hạn.", "success")
    return redirect(request.referrer or url_for("admin_dashboard"))


@app.post("/admin/keys/<int:key_id>/reset-devices")
@admin_required
def admin_reset_devices(key_id: int):
    db = get_db()
    db.execute("DELETE FROM key_sessions WHERE key_id=?", (key_id,))
    db.execute("DELETE FROM key_devices WHERE key_id=?", (key_id,))
    log_event(key_id, "devices_reset")
    db.commit()
    flash("Đã reset thiết bị của key.", "success")
    return redirect(request.referrer or url_for("admin_dashboard"))


@app.post("/admin/keys/<int:key_id>/delete")
@admin_required
def admin_delete_key(key_id: int):
    db = get_db()
    row = db.execute("SELECT key_code FROM license_keys WHERE id=?", (key_id,)).fetchone() or abort(404)
    db.execute("DELETE FROM license_keys WHERE id=?", (key_id,))
    db.commit()
    flash(f"Đã xóa {row['key_code']}.", "success")
    return redirect(url_for("admin_dashboard"))


@app.post("/admin/keys/delete-expired")
@admin_required
def admin_delete_expired():
    db = get_db()
    rows = db.execute("SELECT * FROM license_keys").fetchall()
    ids = [r["id"] for r in rows if key_runtime_state(r) == "expired"]
    for key_id in ids:
        db.execute("DELETE FROM license_keys WHERE id=?", (key_id,))
    db.commit()
    flash(f"Đã xóa {len(ids)} key hết hạn.", "success")
    return redirect(url_for("admin_dashboard"))


@app.get("/admin/export.csv")
@admin_required
def admin_export_csv():
    db = get_db()
    rows = db.execute("SELECT * FROM license_keys ORDER BY id DESC").fetchall()
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["key", "state", "created_at", "first_activated_at", "expires_at", "max_devices", "note"])
    for row in rows:
        writer.writerow([
            row["key_code"],
            key_runtime_state(row),
            row["created_at"],
            row["first_activated_at"],
            row["expires_at"],
            row["max_devices"],
            row["note"],
        ])
    return Response(
        buf.getvalue(),
        mimetype="text/csv",
        headers={"Content-Disposition": "attachment; filename=tizi-keys.csv"},
    )


if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "8000"))
    debug = os.getenv("DEBUG", "0") == "1"
    app.run(host=host, port=port, debug=debug)

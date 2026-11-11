import asyncio, base64, hashlib, hmac, json, os, time
from pathlib import Path
from typing import Any
import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import FileResponse
from pydantic import BaseModel

class Settings:
    ords_base_url = os.getenv("ORDS_BASE_URL", "").rstrip("/")
    ords_oauth_client_id = os.getenv("ORDS_OAUTH_CLIENT_ID", "")
    ords_oauth_client_secret = os.getenv("ORDS_OAUTH_CLIENT_SECRET", "")
    google_client_id = os.getenv("GOOGLE_CLIENT_ID", "").strip()
    google_allowed_emails = {x.strip().lower() for x in os.getenv("GOOGLE_ALLOWED_EMAILS", "").split(",") if x.strip()}
    session_secret = os.getenv("SESSION_SECRET", "")
    session_cookie_secure = os.getenv("SESSION_COOKIE_SECURE", "true").lower() == "true"
settings = Settings()
app = FastAPI(title="Queue management", docs_url=None, redoc_url=None)
frontend_dir = Path(__file__).resolve().parents[1] / "frontend"
cookie_name = "queue_management_session"
actions = {"move-up", "move-down", "move-first", "move-last", "hold", "resume", "remove"}
ords_access_token_value = ""
ords_access_token_expires_at = 0.0
ords_token_lock = asyncio.Lock()

class GoogleLogin(BaseModel): id_token: str
def fail(http_status: int, code: str, message: str, headers: dict[str, str] | None = None): raise HTTPException(http_status, {"error_code": code, "message": message}, headers=headers)
def b64(value: bytes) -> str: return base64.urlsafe_b64encode(value).decode().rstrip("=")
def sign(value: str) -> str:
    if not settings.session_secret: fail(500, "CONFIG_ERROR", "SESSION_SECRET is not configured")
    return b64(hmac.new(settings.session_secret.encode(), value.encode(), hashlib.sha256).digest())
def make_session(email: str, expiry: int) -> str:
    payload = b64(json.dumps({"email": email, "exp": expiry}, separators=(",", ":")).encode())
    return f"{payload}.{sign(payload)}"
def session_email(request: Request) -> str:
    token = request.cookies.get(cookie_name, "")
    if "." not in token: fail(401, "UNAUTHENTICATED", "Google sign-in is required")
    payload_b64, signature = token.split(".", 1)
    if not hmac.compare_digest(signature, sign(payload_b64)): fail(401, "UNAUTHENTICATED", "Google sign-in is required")
    try:
        payload = json.loads(base64.urlsafe_b64decode(payload_b64 + "=" * (-len(payload_b64) % 4)))
        if int(payload["exp"]) <= int(time.time()) or not isinstance(payload["email"], str): raise ValueError
        return payload["email"]
    except (KeyError, TypeError, ValueError, json.JSONDecodeError): fail(401, "UNAUTHENTICATED", "Google sign-in is required")

async def get_ords_access_token() -> str:
    global ords_access_token_value, ords_access_token_expires_at
    if not all((settings.ords_base_url, settings.ords_oauth_client_id, settings.ords_oauth_client_secret)):
        fail(500, "CONFIG_ERROR", "ORDS OAuth connection is not configured")
    if ords_access_token_value and time.time() < ords_access_token_expires_at:
        return ords_access_token_value
    async with ords_token_lock:
        if ords_access_token_value and time.time() < ords_access_token_expires_at:
            return ords_access_token_value
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.post(
                    f"{settings.ords_base_url}/oauth/token",
                    auth=(settings.ords_oauth_client_id, settings.ords_oauth_client_secret),
                    data={"grant_type": "client_credentials"},
                )
        except httpx.RequestError:
            fail(502, "ORDS_UNREACHABLE", "ORDS is unavailable")
        if response.status_code >= 400:
            fail(502, "ORDS_OAUTH_FAILED", "ORDS OAuth token request failed")
        try:
            token_response = response.json()
            token = str(token_response["access_token"])
            expires_in = int(token_response["expires_in"])
        except (KeyError, TypeError, ValueError):
            fail(502, "ORDS_OAUTH_INVALID_RESPONSE", "ORDS OAuth token response is invalid")
        if not token or expires_in <= 60:
            fail(502, "ORDS_OAUTH_INVALID_RESPONSE", "ORDS OAuth token response is invalid")
        ords_access_token_value = token
        ords_access_token_expires_at = time.time() + expires_in - 60
        return ords_access_token_value

async def ords(method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
    global ords_access_token_value, ords_access_token_expires_at
    for attempt in range(2):
        token = await get_ords_access_token()
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                response = await client.request(
                    method,
                    f"{settings.ords_base_url}/{path}",
                    headers={"Authorization": f"Bearer {token}"},
                    json=payload if method == "POST" else None,
                )
        except httpx.RequestError:
            fail(502, "ORDS_UNREACHABLE", "ORDS is unavailable")
        if response.status_code != 401 or attempt == 1:
            break
        ords_access_token_value = ""
        ords_access_token_expires_at = 0.0
    if response.status_code == 429:
        retry_after = response.headers.get("Retry-After"); fail(429, "ORDS_RATE_LIMITED", "ORDS rate limit", {"Retry-After": retry_after} if retry_after else None)
    if response.status_code >= 400:
        try: detail = response.json()
        except ValueError: detail = {"error_code": "ORDS_ERROR", "message": response.text[:500]}
        raise HTTPException(response.status_code, detail)
    if response.status_code == 204: return None
    try: return response.json()
    except ValueError: fail(502, "ORDS_INVALID_JSON", "ORDS returned invalid JSON")

async def google_profile(id_token: str) -> dict[str, Any]:
    if not settings.google_client_id or not settings.google_allowed_emails: fail(500, "CONFIG_ERROR", "Google sign-in is not configured")
    try:
        async with httpx.AsyncClient(timeout=20) as client: response = await client.get("https://oauth2.googleapis.com/tokeninfo", params={"id_token": id_token})
    except httpx.RequestError: fail(502, "GOOGLE_UNREACHABLE", "Google is unavailable")
    if response.status_code >= 400: fail(401, "INVALID_GOOGLE_TOKEN", "Invalid Google sign-in")
    profile = response.json(); email = str(profile.get("email", "")).strip().lower()
    if profile.get("aud") != settings.google_client_id or profile.get("email_verified") != "true": fail(401, "INVALID_GOOGLE_TOKEN", "Invalid Google sign-in")
    if email not in settings.google_allowed_emails: fail(403, "EMAIL_NOT_ALLOWED", "This Google account is not allowed")
    return profile

@app.get("/api/auth/google/config")
async def auth_config(): return {"enabled": bool(settings.google_client_id and settings.google_allowed_emails), "client_id": settings.google_client_id or None}
@app.post("/api/auth/google")
async def auth_google(body: GoogleLogin, response: Response):
    profile = await google_profile(body.id_token); email = str(profile["email"]).strip().lower(); expiry = int(profile.get("exp", int(time.time()) + 3600))
    response.set_cookie(cookie_name, make_session(email, expiry), httponly=True, secure=settings.session_cookie_secure, samesite="lax", path="/")
    return {"email": email}
@app.get("/api/auth/session")
async def auth_session(request: Request):
    try: return {"authenticated": True, "email": session_email(request)}
    except HTTPException as error:
        if error.status_code == 401: return {"authenticated": False}
        raise
@app.post("/api/auth/logout")
async def auth_logout(response: Response): response.delete_cookie(cookie_name, path="/", secure=settings.session_cookie_secure, samesite="lax"); return {"ok": True}
@app.get("/api/admin/queue")
async def admin_queue(request: Request): session_email(request); return await ords("GET", "admin/queue")
@app.get("/api/admin/jobs/{job_id}")
async def admin_job(job_id: int, request: Request): session_email(request); return await ords("GET", f"admin/jobs/{job_id}")
@app.post("/api/admin/jobs/{job_id}/{action}")
async def admin_action(job_id: int, action: str, request: Request):
    if action not in actions: fail(404, "NOT_FOUND", "Unknown action")
    return await ords("POST", f"admin/jobs/{job_id}/{action}", {"actor_id": session_email(request)})
@app.get("/")
async def index(): return FileResponse(frontend_dir / "index.html", headers={"Cache-Control": "no-cache"})
@app.get("/{asset_path:path}")
async def asset(asset_path: str):
    candidate = (frontend_dir / asset_path).resolve()
    if frontend_dir not in candidate.parents or not candidate.is_file(): fail(404, "NOT_FOUND", "Not found")
    return FileResponse(candidate)

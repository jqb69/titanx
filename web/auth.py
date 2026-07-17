# web/auth.py
import os
import re
import secrets
from datetime import datetime, timedelta
import jwt
import redis
import pyotp
import config
from twilio.rest import Client
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from typing import Optional, Tuple

# Redis client
r = redis.from_url(config.REDIS_URL, decode_responses=True)

SECRET_KEY = config.SECRET_KEY
ALGORITHM = "HS256"


def _normalize_phone(phone: str) -> str:
    phone = (phone or "").strip()
    if not re.match(r"^\+[0-9]{7,15}$", phone):
        raise ValueError("Invalid phone format (E.164 expected: +1234567890)")
    return phone


def _new_token(username: str) -> str:
    expire = datetime.utcnow() + timedelta(days=7)
    to_encode = {"sub": username, "exp": expire}
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def verify_token(token: str) -> Optional[str]:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload.get("sub")
    except Exception:
        return None


def create_access_token(username: str):
    return _new_token(username)


def register_user(username: str, password: str, email: str = "", phone: str = ""):
    username = (username or "").strip()
    user_key = f"user:{username.lower()}"

    if r.exists(user_key):
        return False, "Username exists"

    totp_secret = pyotp.random_base32()

    phone_norm = ""
    if phone:
        phone_norm = _normalize_phone(phone)

    r.hset(
        user_key,
        mapping={
            "username": username,
            "password": password,
            "email": email or "",
            "phone": phone_norm,
            "totp_secret": totp_secret,
            "created_at": datetime.utcnow().isoformat(),
            "known_ips": "",
        },
    )
    return True, totp_secret


def get_user_phone(username: str) -> str | None:
    stored = r.hgetall(f"user:{(username or '').strip().lower()}")
    return stored.get("phone") if stored else None


def send_otp(phone: str):
    if not (config.TWILIO_SID and config.TWILIO_AUTH_TOKEN and config.TWILIO_PHONE):
        raise RuntimeError("Missing Twilio credentials in config")

    phone_norm = _normalize_phone(phone)

    otp = str(secrets.randbelow(900000) + 100000)
    r.setex(f"otp:{phone_norm}", 300, otp)

    client = Client(config.TWILIO_SID, config.TWILIO_AUTH_TOKEN)
    client.messages.create(
        to=phone_norm,
        from_=config.TWILIO_PHONE,
        body=f"Your MIKIE OTP: {otp} (expires in 5 minutes)",
    )
    return True


def verify_otp(phone: str, code: str) -> bool:
    phone_norm = _normalize_phone(phone)
    expected = r.get(f"otp:{phone_norm}")
    if expected and expected.decode() == code:
        r.delete(f"otp:{phone_norm}")
        return True
    return False


def login_user(
    username: str,
    password: str,
    current_ip: str,
    totp_code: str = None,
    phone_otp: str = None,
):
    username = (username or "").strip()
    user_key = f"user:{username.lower()}"

    stored = r.hgetall(user_key)
    if not stored:
        return None, "Invalid credentials"

    if stored.get("password") != password:
        return None, "Invalid credentials"

    known_ips_raw = stored.get("known_ips", "")
    known_ips = [ip for ip in known_ips_raw.split(",") if ip]

    current_ip = (current_ip or "").strip()
    is_abnormal_ip = bool(known_ips) and current_ip and (current_ip not in known_ips)

    if is_abnormal_ip:
        if not totp_code and not phone_otp:
            return "2FA_REQUIRED", "Unusual IP detected. Choose Phone OTP or Google Authenticator."

        if totp_code:
            totp_secret = stored.get("totp_secret")
            if not totp_secret:
                return None, "Google Authenticator not set up for this account"
            totp = pyotp.TOTP(totp_secret)
            if not totp.verify(str(totp_code), valid_window=1):
                return None, "Invalid Google Authenticator code"
        else:
            phone = stored.get("phone", "") or ""
            if not phone:
                return None, "No phone number set on this account"
            if not verify_otp(phone, phone_otp):
                return None, "Invalid or expired phone OTP"

    # Update known IPs
    if current_ip and current_ip not in known_ips:
        new_ips = ",".join([ip for ip in known_ips if ip] + [current_ip])
        r.hset(user_key, "known_ips", new_ips)

    token = create_access_token(username)
    return token, "Login successful"


def get_totp_uri(username: str):
    stored = r.hgetall(f"user:{(username or '').strip().lower()}")
    if stored and "totp_secret" in stored and stored["totp_secret"]:
        return pyotp.TOTP(stored["totp_secret"]).provisioning_uri(
            name=username,
            issuer_name="MIKIE",
        )
    return None


def google_login(google_token: str) -> Tuple[Optional[str], str]:
    try:
        if not config.GOOGLE_CLIENT_ID:
            return None, "Missing GOOGLE_CLIENT_ID in config"

        idinfo = id_token.verify_oauth2_token(
            google_token,
            google_requests.Request(),
            config.GOOGLE_CLIENT_ID,
        )

        email = idinfo.get("email")
        if not email:
            return None, "Invalid Google token"

        username = email.split("@")[0].strip()
        if not username:
            return None, "Invalid Google token (no username)"

        user_key = f"user:{username.lower()}"

        if not r.exists(user_key):
            r.hset(
                user_key,
                mapping={
                    "username": username,
                    "email": email,
                    "auth": "google",
                    "created_at": datetime.utcnow().isoformat(),
                    "known_ips": "",
                },
            )

        token = create_access_token(username)
        return token, f"Welcome {username} (Google)"

    except ValueError as e:
        return None, f"Google token invalid: {e}"
    except Exception as e:
        return None, f"Google login failed: {e}"
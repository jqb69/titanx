# web/login_ui.py
import streamlit as st
import requests
import qrcode
from io import BytesIO

import auth

def get_client_ip():
    try:
        return requests.get('https://api.ipify.org', timeout=3).text.strip()
    except Exception:
        return "unknown"

def sanitize_input(text: str) -> str:
    return str(text).strip()[:100] if text else ""

def logout():
    for key in list(st.session_state.keys()):
        if key not in ["_is_running", "_stcore"]:
            del st.session_state[key]
    st.switch_page("app.py")


def login_tab():
    username = sanitize_input(st.text_input("Username"))
    password = sanitize_input(st.text_input("Password", type="password"))

    if st.button("Login"):
        ip = get_client_ip()
        result, msg = auth.login_user(username, password, ip)

        if result == "2FA_REQUIRED":
            st.session_state.twofa_stage = "required"
            st.session_state.pending_username = username
            st.session_state.pending_password = password
            st.session_state.pending_ip = ip
            st.warning(msg)
            st.rerun()
        elif result and result not in (None, "2FA_REQUIRED"):
            st.session_state.token = result
            st.session_state.username = username
            st.switch_page("app.py")
        else:
            st.error(msg)


def twofa_choice():
    if st.session_state.get("twofa_stage") != "required":
        return

    st.subheader("Unusual IP — Verify Identity")
    phone = auth.get_user_phone(st.session_state.pending_username)

    col1, col2 = st.columns(2)
    with col1:
        totp = st.text_input("Google Authenticator Code", max_chars=6)
        if st.button("Verify with Google Authenticator"):
            if not totp.strip():
                st.error("Enter your Google Authenticator code.")
            else:
                result, msg = auth.login_user(
                    st.session_state.pending_username,
                    st.session_state.pending_password,
                    st.session_state.pending_ip,
                    totp_code=totp
                )
                if result not in (None, "2FA_REQUIRED"):
                    st.session_state.token = result
                    st.session_state.username = st.session_state.pending_username
                    for key in ["twofa_stage", "pending_username", "pending_password", "pending_ip"]:
                        st.session_state.pop(key, None)
                    st.switch_page("app.py")
                else:
                    st.error(msg)

    with col2:
        if phone:
            if st.button(f"Send OTP to {phone}"):
                auth.send_otp(phone)
                st.success("OTP sent")
            phone_otp = st.text_input("Phone OTP", max_chars=6)
            if st.button("Verify Phone OTP"):
                if not phone_otp.strip():
                    st.error("Enter the phone OTP.")
                else:
                    result, msg = auth.login_user(
                        st.session_state.pending_username,
                        st.session_state.pending_password,
                        st.session_state.pending_ip,
                        phone_otp=phone_otp
                    )
                    if result not in (None, "2FA_REQUIRED"):
                        st.session_state.token = result
                        st.session_state.username = st.session_state.pending_username
                        for key in ["twofa_stage", "pending_username", "pending_password", "pending_ip"]:
                            st.session_state.pop(key, None)
                        st.switch_page("app.py")
                    else:
                        st.error(msg)
        else:
            st.error("No phone number registered.")


def google_tab():
    st.write("### Sign in with Google")
    if st.button("Continue with Google", use_container_width=True, type="primary"):
        st.session_state.google_auth_flow = True
        st.rerun()

    if st.session_state.get("google_auth_flow"):
        st.subheader("Choose an account")
        if st.button("Use current Google account"):
            token, msg = auth.google_login("simulated_google_token")
            if token:
                st.session_state.token = token
                st.success(msg)
                st.switch_page("app.py")
            else:
                st.error(msg)
        if st.button("Use another account"):
            st.session_state.google_auth_flow = False
            st.rerun()


def register_tab():
    new_user = sanitize_input(st.text_input("New Username"))
    new_pass = sanitize_input(st.text_input("New Password", type="password"))
    confirm_pass = sanitize_input(st.text_input("Confirm Password", type="password"))
    email = sanitize_input(st.text_input("Email"))
    phone = sanitize_input(st.text_input("Phone (optional)"))

    if new_pass and confirm_pass and new_pass != confirm_pass:
        st.error("Passwords do not match")

    if st.button("Create Account"):
        if new_pass != confirm_pass:
            st.error("Passwords do not match")
        else:
            success, secret = auth.register_user(new_user, new_pass, email, phone)
            if success:
                st.success("Account created!")
                uri = auth.get_totp_uri(new_user)
                if uri:
                    img = qrcode.make(uri)
                    buf = BytesIO()
                    img.save(buf, format="PNG")
                    st.image(buf.getvalue(), caption="Scan with Google Authenticator")
            else:
                st.error(secret)


def render_login_page():
    st.title("🔐 MIKIE Secure Login")

    if "token" in st.session_state:
        if st.button("🚪 Logout"):
            logout()
        return

    login_tab()
    google_tab()
    register_tab()
    twofa_choice()

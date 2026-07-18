# web/login_ui.py — Clean, safe, modular login UI

import streamlit as st
import requests  # for IP detection
import qrcode
from io import BytesIO

import auth

def get_client_ip():
    try:
        import requests
        return requests.get('https://api.ipify.org', timeout=3).text.strip()
    except Exception:
        return "unknown"

def sanitize_input(text: str) -> str:
    return str(text).strip()[:100] if text else ""

def logout():
    """Clear session and redirect to login"""
    for key in list(st.session_state.keys()):
        if key not in ["_is_running", "_stcore"]:  # preserve Streamlit internals
            del st.session_state[key]
    st.switch_page("app.py")

def render_login_page():
    st.title("🔐 MIKIE Secure Login")

    tab1, tab2, tab3 = st.tabs(["Login", "Google", "Register"])

    with tab1:
        username = sanitize_input(st.text_input("Username"))
        password = sanitize_input(st.text_input("Password", type="password"))

        if st.button("Login"):
            ip = get_client_ip()
            from auth import login_user
            result, msg = login_user(username, password, ip)

            if result == "2FA_REQUIRED":
                st.session_state.twofa_stage = "required"
                st.session_state.pending_username = username
                st.session_state.pending_password = password
                st.session_state.pending_ip = ip
                st.warning(msg)
                st.rerun()  # Only here as fallback, but we can avoid it
            elif result:
                st.session_state.token = result
                st.session_state.username = username
                st.switch_page("app.py")  # Modern way
            else:
                st.error(msg)

        # 2FA choice (same as before, but cleaner)
        if st.session_state.get("twofa_stage") == "required":
            st.subheader("Unusual IP — Choose verification")
            phone = auth.get_user_phone(st.session_state.pending_username)  # lazy import

            col1, col2 = st.columns(2)
            with col1:
                totp = st.text_input("Google Authenticator Code", max_chars=6)
                if st.button("Verify Google"):
                    from auth import login_user
                    result, msg = login_user(
                        st.session_state.pending_username,
                        st.session_state.pending_password,
                        st.session_state.pending_ip,
                        totp_code=totp
                    )
                    if result:
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
                        from auth import send_otp
                        send_otp(phone)
                        st.success("OTP sent")
                    phone_otp = st.text_input("Phone OTP", max_chars=6)
                    if st.button("Verify Phone OTP"):
                        from auth import login_user
                        result, msg = login_user(
                            st.session_state.pending_username,
                            st.session_state.pending_password,
                            st.session_state.pending_ip,
                            phone_otp=phone_otp
                        )
                        if result:
                            st.session_state.token = result
                            st.session_state.username = st.session_state.pending_username
                            for key in ["twofa_stage", "pending_username", "pending_password", "pending_ip"]:
                                st.session_state.pop(key, None)
                            st.switch_page("app.py")
                        else:
                            st.error(msg)
                else:
                    st.error("No phone number registered.")

    with tab2:
        st.write("### Google Login")
        google_token = st.text_input("Google ID Token")
        if st.button("Login with Google"):
            from auth import google_login
            token, msg = google_login(google_token)
            if token:
                st.session_state.token = token
                st.switch_page("app.py")
            else:
                st.error(msg)

    with tab3:
        new_user = sanitize_input(st.text_input("New Username"))
        new_pass = sanitize_input(st.text_input("New Password", type="password"))
        email = sanitize_input(st.text_input("Email"))
        phone = sanitize_input(st.text_input("Phone"))
        if st.button("Register"):
            from auth import register_user, get_totp_uri
            success, secret = register_user(new_user, new_pass, email, phone)
            if success:
                st.success("Registered!")
                uri = get_totp_uri(new_user)
                if uri:
                    try:
                        import qrcode
                        from io import BytesIO
                        img = qrcode.make(uri)
                        buf = BytesIO()
                        img.save(buf, format="PNG")
                        st.image(buf.getvalue())
                    except Exception:
                        st.info(f"Secret for Google Authenticator: {secret}")
            else:
                st.error(secret)

    # Logout button (if somehow logged in)
    if "token" in st.session_state:
        if st.button("🚪 Logout"):
             logout()


# Add logout button in sidebar when logged in (call from app.py)
def add_logout_button():
    if "token" in st.session_state:
        if st.button("🚪 Logout"):
            logout()

# web/login_ui.py
import streamlit as st
import requests
import qrcode
from io import BytesIO
import config
# Optional: set activity timestamp
import time
import auth
import json
import re

def get_client_ip():
    try:
        return requests.get('https://api.ipify.org', timeout=3).text.strip()
    except Exception:
        return "unknown"

def sanitize_input(text: str) -> str:
    return str(text).strip()[:100] if text else ""
  
def initialize_login_state(username: str, token: str):
    """
    Call after every successful login.
    Cleans old flags and sets a clean session.
    """
    # Clear logout / idle related flags
    for key in [
        "logout_started_at", "do_logout", "logout_confirm_started",
        "idle_prompt_started", "twofa_stage", "pending_username",
        "pending_password", "pending_ip", "show_forgot", "page"
    ]:
        st.session_state.pop(key, None)

    # Set the real login state (matches existing app.py checks)
    st.session_state.token = token
    st.session_state.username = username

    # Activity timestamp for idle timeout
    st.session_state.last_activity = time.time()

def logout():
    """Two-phase logout with 30s timeout"""
    #import time

    if "token" not in st.session_state:
        return

    # Phase 2 — actually log out
    if st.session_state.get("do_logout") is True:
        for key in list(st.session_state.keys()):
            if not key.startswith("_"):
                del st.session_state[key]
        st.rerun()

    # Phase 1 — show confirmation
    if "logout_started_at" not in st.session_state:
        st.session_state.logout_started_at = time.time()

    elapsed = time.time() - st.session_state.logout_started_at
    remaining = max(0, 3 - int(elapsed))

    st.warning(f"⚠️ Are you sure you want to logout? ({remaining}s)")

    col1, col2 = st.columns(2)
    with col1:
        if st.button("Yes, Logout", type="primary", key="logout_yes"):
            st.session_state.do_logout = True
            st.rerun()
    with col2:
        if st.button("Cancel", key="logout_cancel"):
            st.session_state.pop("logout_started_at", None)
            st.session_state.pop("do_logout", None)
            st.rerun()

    if remaining <= 0:
        st.session_state.do_logout = True
        st.rerun()

def forgot_password_section(prefill_email: str = ""):
    """Reusable Forgot Password UI (used by both tab and after failed login)"""
    st.write("### Forgot Password")

    email = sanitize_input(st.text_input(
        "Your registered email",
        value=prefill_email,
        key=f"forgot_email_{prefill_email or 'tab'}"
    ))

    if st.button("Send Reset Code", key=f"send_code_{prefill_email or 'tab'}"):
        success, msg = auth.send_password_reset_email(email)
        if success:
            st.success(msg)
            st.session_state.reset_code_sent = True
            st.session_state.reset_email = email
        else:
            st.error(msg)

    if st.session_state.get("reset_code_sent"):
        code = sanitize_input(st.text_input("Reset Code (6 digits)", max_chars=6, key="forgot_reset_code"))
        new_pass = sanitize_input(st.text_input("New Password", type="password", key="forgot_new_pass"))
        confirm = sanitize_input(st.text_input("Confirm New Password", type="password", key="forgot_confirm_pass"))

        if st.button("Reset Password"):
            if new_pass != confirm:
                st.error("Passwords do not match")
            else:
                success, msg = auth.reset_password(
                    st.session_state.get("reset_email", email),
                    code,
                    new_pass
                )
                if success:
                    st.success(msg)
                    st.session_state.reset_code_sent = False
                    st.session_state.show_forgot = False
                else:
                    st.error(msg)

def forgot_password_tab():
    """Dedicated tab version – just calls the same modular function"""
    forgot_password_section()

def login_tab():
    username = sanitize_input(st.text_input("Username / Email", key="login_username"))
    password = sanitize_input(st.text_input("Password", type="password", key="login_password"))

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
            initialize_login_state(username, result)
            st.switch_page("app.py")
        else:
            st.error(msg)
            st.session_state.show_forgot = True
            st.session_state.forgot_email = username

    # Show Forgot Password only after wrong password
    if st.session_state.get("show_forgot"):
        st.divider()
        forgot_password_section(prefill_email=st.session_state.get("forgot_email", ""))

def twofa_choice():
    if st.session_state.get("twofa_stage") != "required":
        return

    st.subheader("Unusual IP — Verify Identity")
    phone = auth.get_user_phone(st.session_state.pending_username)

    col1, col2 = st.columns(2)
    with col1:
        totp = st.text_input("Google Authenticator Code", max_chars=6, key="totp_code")
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
                    initialize_login_state(st.session_state.pending_username, result)
                    st.switch_page("app.py")
                else:
                    st.error(msg)

    with col2:
        if phone:
            if st.button(f"Send OTP to {phone}"):
                auth.send_otp(phone)
                st.success("OTP sent")
            phone_otp = st.text_input("Phone OTP", max_chars=6, key="phone_otp_code")
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
                        initialize_login_state(st.session_state.pending_username, result)
                        st.switch_page("app.py")
                    else:
                        st.error(msg)
        else:
            st.error("No phone number registered.")

def google_tab():
    st.write("### Sign in with Google")
    st.markdown("Click the button below. Google will handle account selection.")

    google_client_id = getattr(config, "GOOGLE_CLIENT_ID", "")
    if not google_client_id:
        st.error("GOOGLE_CLIENT_ID is missing in config / hermes.env")
        return

    import streamlit.components.v1 as components

    google_html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <script src="https://accounts.google.com/gsi/client" async defer></script>
    </head>
    <body style="margin:0; padding:10px; background:transparent;">
        <div id="g_id_onload"
             data-client_id="{google_client_id}"
             data-callback="onGoogleCredentialResponse"
             data-auto_prompt="false">
        </div>

        <div class="g_id_signin"
             data-type="standard"
             data-size="large"
             data-theme="outline"
             data-text="continue_with"
             data-shape="rectangular"
             data-logo_alignment="left">
        </div>

        <script>
        function onGoogleCredentialResponse(response) {{
            const cred = response.credential;
            const currentUrl = window.location.href.split('?')[0].split('#')[0];
            window.top.location.href = currentUrl + '?google_cred=' + encodeURIComponent(cred);
        }}
        </script>
    </body>
    </html>
    """
    
    components.html(google_html, height=70)

    # Handle the returned credential
    google_cred = st.query_params.get("google_cred")
    if google_cred:
        st.query_params.clear()

        if isinstance(google_cred, list):
            google_cred = google_cred[0] if google_cred else None

        if not google_cred or str(google_cred).count(".") < 2:
            st.error("Invalid Google credential received.")
            return

        token, msg = auth.google_login(str(google_cred))
        if token:
            username = "google_user"
            if "Welcome" in msg:
                parts = msg.replace("(", "").replace(")", "").split()
                if len(parts) >= 2:
                    username = parts[1]

            initialize_login_state(username, token)
            st.success(msg)
            st.rerun()
        else:
            st.error(msg)

def register_tab():
    new_user = sanitize_input(st.text_input("New Username", key="register_username"))
    new_pass = sanitize_input(st.text_input("New Password", type="password", key="register_password"))
    confirm_pass = sanitize_input(st.text_input("Confirm Password", type="password", key="register_confirm"))
    email = sanitize_input(st.text_input("Email", key="register_email"))
    phone = sanitize_input(st.text_input("Phone (optional)", key="register_phone"))

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

    tab1, tab2, tab3, tab4 = st.tabs(["Login", "Google", "Register", "Forgot Password"])

    with tab1:
        login_tab()
        twofa_choice()
    with tab2:
        google_tab()
    with tab3:
        register_tab()
    with tab4:
        forgot_password_tab()

def add_logout_button():
    if "token" in st.session_state:
        if st.button("🚪 Logout"):
            logout()

def handle_idle_timeout() -> bool:
    """
    Returns True if main UI should stop (logged out or showing prompt).
    """
    from session import check_idle_timeout, update_last_activity

    status = check_idle_timeout()

    if status == "logout":
        logout()
        return True

    if status == "prompt":
        st.warning("⏰ You have been idle for a long time.")
        col1, col2 = st.columns(2)
        with col1:
            if st.button("Stay Logged In", type="primary"):
                update_last_activity()
                st.session_state.pop("idle_prompt_started", None)
                st.rerun()
        with col2:
            if st.button("Logout Now"):
                logout()
        st.info("Auto-logout in 60 seconds if no response…")
        return True

    update_last_activity()
    return False

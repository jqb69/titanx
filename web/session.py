# web/session.py
import time
import streamlit as st

IDLE_TIMEOUT = 180 * 60      # 180 minutes
CONFIRM_TIMEOUT = 60         # 60 seconds

def update_last_activity():
    st.session_state.last_activity = time.time()

def check_idle_timeout() -> str | None:
    now = time.time()
    last = st.session_state.get("last_activity", now)

    if "last_activity" not in st.session_state:
        st.session_state.last_activity = now
        return None

    idle_seconds = now - last

    if st.session_state.get("idle_prompt_started"):
        if now - st.session_state.idle_prompt_started > CONFIRM_TIMEOUT:
            return "logout"
        return "prompt"

    if idle_seconds > IDLE_TIMEOUT:
        st.session_state.idle_prompt_started = now
        return "prompt"

    return None
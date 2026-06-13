# web/state.py
import os
import json
import streamlit as st
from typing import List, Dict, Optional

WORKSPACE_MEM_PATH = "/workspace/mikie_memory.json"


def save_persistent_memory() -> None:
    """Save chat messages to the workspace memory file if possible."""
    if not os.path.exists("/workspace"):
        return

    try:
        messages = st.session_state.get("messages", [])
        with open(WORKSPACE_MEM_PATH, "w", encoding="utf-8") as f:
            json.dump(messages, f, indent=2)
    except Exception:
        pass


def load_persistent_memory() -> None:
    """Load chat messages from disk if Streamlit has not initialized them yet."""
    if "messages" in st.session_state:
        return

    if os.path.exists(WORKSPACE_MEM_PATH):
        try:
            with open(WORKSPACE_MEM_PATH, "r", encoding="utf-8") as f:
                st.session_state.messages = json.load(f)
        except Exception:
            st.session_state.messages = []
    else:
        st.session_state.messages = []


def init_session() -> None:
    load_persistent_memory()
    if "messages" not in st.session_state:
        st.session_state.messages = []
    if "stop_generation" not in st.session_state:
        st.session_state.stop_generation = False


def get_messages() -> List[Dict[str, str]]:
    return st.session_state.messages


def append_message(role: str, content: str) -> None:
    if "messages" not in st.session_state:
        st.session_state.messages = []

    st.session_state.messages.append({"role": role, "content": content})
    save_persistent_memory()


def set_stop_flag(value: bool) -> None:
    st.session_state.stop_generation = value


def is_stopped() -> bool:
    return st.session_state.get("stop_generation", False)


def read_workspace_file(uploaded_file) -> Optional[str]:
    """Safe read — no Streamlit calls here."""
    if uploaded_file is None:
        return None

    try:
        return uploaded_file.read().decode("utf-8")
    except Exception as e:
        return f"FILE_READ_ERROR: {e}"

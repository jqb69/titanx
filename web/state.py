# web/state.py
import os
import json
import streamlit as st
from typing import List, Dict, Optional

import threads

WORKSPACE_MEM_PATH = "/workspace/mikie_memory.json"


def _username() -> str:
    return (st.session_state.get("username") or "anonymous").lower()


def init_session() -> None:
    if "stop_generation" not in st.session_state:
        st.session_state.stop_generation = False
    if "active_topic_id" not in st.session_state:
        st.session_state.active_topic_id = None  # None = all threads
    if "active_thread_id" not in st.session_state:
        st.session_state.active_thread_id = None

    # Ensure user has at least one thread; migrate old flat memory once
    user = _username()
    existing = threads.list_threads(user)
    if not existing:
        msgs = []
        if os.path.exists(WORKSPACE_MEM_PATH):
            try:
                with open(WORKSPACE_MEM_PATH, "r", encoding="utf-8") as f:
                    msgs = json.load(f) or []
            except Exception:
                msgs = []
        tid = threads.create_thread(user, title="Previous chat" if msgs else "New chat")
        if msgs:
            threads.save_messages(tid, msgs)
        st.session_state.active_thread_id = tid
    elif not st.session_state.active_thread_id:
        st.session_state.active_thread_id = existing[0]["id"]

    # Mirror active thread messages into session for fast UI
    _sync_session_from_thread()


def _sync_session_from_thread() -> None:
    tid = st.session_state.get("active_thread_id")
    if not tid:
        st.session_state.messages = []
        return
    st.session_state.messages = threads.load_messages(tid)


def get_active_thread_id() -> Optional[str]:
    return st.session_state.get("active_thread_id")


def set_active_thread(thread_id: str) -> None:
    st.session_state.active_thread_id = thread_id
    _sync_session_from_thread()


def new_thread(topic_id: str = "", title: str = "New chat") -> str:
    tid = threads.create_thread(_username(), title=title, topic_id=topic_id or "")
    set_active_thread(tid)
    return tid


def get_messages() -> List[Dict[str, str]]:
    if "messages" not in st.session_state:
        st.session_state.messages = []
    return st.session_state.messages


def append_message(role: str, content: str) -> None:
    tid = get_active_thread_id()
    if not tid:
        tid = new_thread()
    msgs = threads.append_message(tid, role, content)
    st.session_state.messages = msgs


def set_stop_flag(value: bool) -> None:
    st.session_state["stop_generation"] = value


def is_stopped() -> bool:
    return bool(st.session_state.get("stop_generation", False))


def read_workspace_file(uploaded_file) -> Optional[str]:
    if uploaded_file is None:
        return None
    try:
        return uploaded_file.read().decode("utf-8")
    except Exception as e:
        return f"FILE_READ_ERROR: {e}"

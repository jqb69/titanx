# web/ui.py — Updated for multi-file vault support
# Changes from original: import file_ui, call render_file_manager(),
#                        render_attachment_bar(), get_attached_for_message(),
#                        render_message_file_chips(),add_logout_button()
# All other functions remain IDENTICAL to preserve core functionality.

import streamlit as st
import time
import config
import state
import client
import files            # NEW: file storage backend (new module)
import file_ui          # NEW: file UI components (new module)
from typing import Optional
import topics
import threads

def inject_global_styles() -> None:
    st.markdown(config.CUSTOM_CSS, unsafe_allow_html=True)

def logout():
    import login_ui
    login_ui.logout()
  
def add_logout_button():
    if "token" in st.session_state:
        if st.button("🚪 Logout", use_container_width=True):
            logout()
  
def render_header() -> None:
    col1, col2 = st.columns([0.88, 0.12])
    
    with col1:
        st.title("⚡ MIKIE")
        st.caption("Modular Integrated Kinetic Intelligence Engine — TitanX")
    
    with col2:
        # 3-dot menu (top right)
        with st.popover("⋮"):
            username = st.session_state.get("username", "User")
            st.write(f"👤 **{username}**")
            st.markdown("---")
            if st.button("Account ", use_container_width=True):
                st.session_state.page = "account"
                st.rerun()
            st.divider()
            add_logout_button()

# web/ui.py  (topics/threads section only)

def _topic_filter_value(current) -> str:
    if current is None:
        return "__all__"
    if current == "":
        return "__none__"
    return current
  
def clear_view_keep_thread() -> None:
    st.session_state.messages = []


def _apply_topic_filter(chosen_id: str):
    prev = st.session_state.get("active_topic_id", "__unset__")

    if chosen_id == "__all__":
        new_filter = None
    elif chosen_id == "__none__":
        new_filter = ""
    else:
        new_filter = chosen_id

    st.session_state.active_topic_id = new_filter

    # Topic (or All/Untagged) changed → clear visible messages
    if prev != "__unset__" and prev != new_filter:
        clear_view_keep_thread()
        # Start a fresh chat in this filter so user isn't on a hidden thread
        state.new_thread(topic_id=new_filter or "", title="New chat")
        # new_thread already sets active + empty messages

    return new_filter


def _render_topic_filter(username: str, tlist: list) -> Optional[str]:
    # (id, display_label) — disambiguate duplicate titles
    options = [("__all__", "All chats"), ("__none__", "Untagged")]
    seen = {}
    for t in tlist:
        title = t.get("title") or "Topic"
        n = seen.get(title, 0)
        seen[title] = n + 1
        label = title if n == 0 else f"{title} ({t['id'][:4]})"
        options.append((t["id"], f"📂 {label}"))

    ids = [o[0] for o in options]
    labels = [o[1] for o in options]
    id_by_label = dict(zip(labels, ids))

    cur = _topic_filter_value(st.session_state.get("active_topic_id"))
    idx = ids.index(cur) if cur in ids else 0

    choice = st.selectbox("Filter", labels, index=idx, key="topic_filter_select")
    return _apply_topic_filter(id_by_label[choice])

def _render_topic_create(username: str) -> None:
    name = st.text_input("New topic name", key="new_topic_name", placeholder="e.g. TitanX deploy")
    if st.button("＋ Topic", use_container_width=True) and name.strip():
        topics.create_topic(username, name.strip())
        st.rerun()

def _render_topic_manage(username: str, filter_topic: Optional[str]) -> None:
    """Rename/delete only when filter is a real topic id."""
    if not filter_topic:
        return

    meta_title = next(
        (t["title"] for t in topics.list_topics(username) if t["id"] == filter_topic),
        "Topic",
    )

    with st.expander(f"Manage topic: {meta_title}", expanded=False):
        new_name = st.text_input(
            "Rename to",
            value=meta_title,
            key=f"rename_topic_{filter_topic}",
        )
        c1, c2 = st.columns(2)
        with c1:
            if st.button("Save name", key=f"save_topic_{filter_topic}", use_container_width=True):
                if new_name.strip():
                    topics.rename_topic(filter_topic, new_name.strip(), username)
                    st.rerun()
        with c2:
            if st.button("Delete topic", key=f"del_topic_{filter_topic}", use_container_width=True):
                topics.delete_topic(filter_topic, username)
                st.session_state.active_topic_id = None
                st.rerun()


def _render_thread_list(username: str, filter_topic: Optional[str]) -> list:
    if st.button("＋ New chat", use_container_width=True, type="primary"):
        state.new_thread(topic_id=filter_topic or "")
        st.rerun()

    thread_list = threads.list_threads(username, topic_id=filter_topic)
    active = state.get_active_thread_id()

    for th in thread_list:
        label = f"{'▶ ' if th['id'] == active else ''}{th['title']}"
        c1, c2 = st.columns([0.75, 0.25])
        with c1:
            if st.button(label, key=f"th_{th['id']}", use_container_width=True):
                state.set_active_thread(th["id"])
                st.rerun()
        with c2:
            if st.button("🗑", key=f"del_{th['id']}"):
                was_active = th["id"] == active
                threads.delete_thread(th["id"], username)
                if was_active:
                    state.new_thread(topic_id=filter_topic or "")
                st.rerun()
    return thread_list


def _disambiguate_topic_labels(tlist: list) -> tuple:
    """Returns (display_labels, topic_ids) with id suffix on duplicate titles."""
    opts = [("— Untagged —", "")] + [(t["title"], t["id"]) for t in tlist]
    seen = {}
    display, vals = [], []
    for label, vid in opts:
        n = seen.get(label, 0)
        seen[label] = n + 1
        display.append(label if n == 0 else f"{label} ({vid[:4]})")
        vals.append(vid)
    return display, vals

def _render_bulk_move(username: str, tlist: list, thread_list: list) -> None:
    if not thread_list:
        return

    st.caption("Move chats")
    id_by_label = {f"{th['title']} ({th['id'][:4]})": th["id"] for th in thread_list}
    selected_labels = st.multiselect(
        "Select chats",
        options=list(id_by_label.keys()),
        key="bulk_move_threads",
    )
    display, vals = _disambiguate_topic_labels(tlist)
    pick = st.selectbox("To topic", display, key="bulk_move_topic")
    target_id = vals[display.index(pick)]

    if st.button("Move selected", use_container_width=True) and selected_labels:
        for lab in selected_labels:
            tid = id_by_label[lab]
            threads.set_thread_topic(tid, target_id, username)
        st.rerun()


def _render_move_active(username: str, tlist: list, thread_list: list) -> None:
    active = state.get_active_thread_id()
    if not active or active not in {th["id"] for th in thread_list}:
        return

    meta = threads.get_thread(active) or {}
    current_topic = meta.get("topic_id") or ""

    st.caption("Move this chat")
    display, vals = _disambiguate_topic_labels(tlist)
    try:
        idx = vals.index(current_topic)
    except ValueError:
        idx = 0  # Untagged

    pick = st.selectbox("Topic", display, index=idx, key="move_topic_select")
    if st.button("Move here", use_container_width=True):
        new_tid = vals[display.index(pick)]
        if new_tid != current_topic:
            threads.set_thread_topic(active, new_tid, username)
            st.rerun()


def _render_rename_active_chat() -> None:
    active = state.get_active_thread_id()
    if not active:
        return
    meta = threads.get_thread(active) or {}
    rt = st.text_input("Rename chat", value=meta.get("title") or "", key="rename_chat_input")
    if st.button("Save chat title") and rt.strip():
        threads.rename_thread(active, rt.strip())
        try:
            r = __import__("redis").from_url(config.REDIS_URL, decode_responses=True)
            r.hset(f"thread:{active}", "title_locked", "1")
        except Exception:
            pass
        st.rerun()
      
def _render_topics_and_threads(username: str) -> None:
    st.subheader("📁 Topics")
    tlist = topics.list_topics(username)
    filter_topic = _render_topic_filter(username, tlist)
    _render_topic_create(username)
    _render_topic_manage(username, filter_topic)

    st.subheader("💬 Chats")
    thread_list = _render_thread_list(username, filter_topic)
    _render_move_active(username, tlist, thread_list)  # ← add username
    _render_bulk_move(username, tlist, thread_list)
    _render_rename_active_chat()
  
def render_sidebar_controls() -> Optional[str]:
    with st.sidebar:
        username = st.session_state.get("username", "User")
        st.markdown(f"### 👤 {username}")

        col1, col2 = st.columns(2)
        with col1:
            if st.button("Account", use_container_width=True):
                st.session_state.page = "account"
                st.rerun()
        with col2:
            if st.button("Logout", use_container_width=True):
                logout()

        st.markdown("---")
        _render_topics_and_threads(username)
        st.markdown("---")

        st.header("⚙️ System Status")
        if not client.check_hermes_health():
            st.error("⚠️ Hermes Endpoint: Offline")
        else:
            st.success("🟢 Hermes Endpoint: Online")
        s = client.check_ollama_health()
        if s["ok"] and s["has_model"]:
            st.success(client.ollama_status_line())
        elif s["ok"]:
            st.warning(client.ollama_status_line())
        else:
            st.error(client.ollama_status_line())

        st.markdown("---")
        file_ui.render_file_manager()

    return file_ui.get_attached_for_message()


def _display_content(content: str) -> str:
    if not content:
        return ""
    if "--- LOCAL WORKSPACE FILE ATTACHED ---" not in content:
        return content
    if "User Message:" in content:
        return content.split("User Message:")[-1].strip()
    # strip marker block; show whatever is left
    before, _, after = content.partition("--- LOCAL WORKSPACE FILE ATTACHED ---")
    text = (before or after or "").strip()
    return text or "_(message with attachment)_"


def render_chat_history() -> None:
    for msg in state.get_messages():
        if msg.get("role") == "system":
            continue
        content = msg.get("content") or ""
        with st.chat_message(msg["role"]):
            st.markdown(_display_content(content))
            file_ui.render_message_file_chips(content)

def render_generation_sequence(prompt: str, file_context: Optional[str]) -> None:
    # file_context now comes from file_ui.get_attached_for_message() and may
    # contain MULTIPLE files, not just a single string.
    user_payload = files.format_message_with_files(prompt, file_context) \
        if file_context else prompt
    # ^^^ NEW: uses files.format_message_with_files() which produces the same
    #     "--- LOCAL WORKSPACE FILE ATTACHED ---" marker that client.format_messages()
    #     already knows how to strip. Zero client.py changes required.

    state.append_message("user", user_payload)

    with st.chat_message("user"):
        st.markdown(prompt)
        # NEW: show which files were attached to this outgoing message
        if file_context:
            file_ui.render_message_file_chips(user_payload)
            
    state.set_stop_flag(False)
    with st.chat_message("assistant"):
        placeholder = st.empty()
        placeholder.markdown("Thinking...")

        stop_slot = st.empty()
        if stop_slot.button("🛑 Stop Generation", key="stop_generation_btn", type="primary"):
            state.set_stop_flag(True)

        final_response = client.run_routing_pipeline(state.get_messages(), placeholder)

        stop_slot.empty()

        thinking, clean_answer = client.extract_thinking_and_answer(final_response or "")
        if thinking:
            with st.expander("🤔 Thinking Process", expanded=False):
                html = (
                    "<div style='font-size:0.9em; color:#aaaaaa; "
                    "background:#1a1a1a; padding:12px; border-radius:8px; "
                    "white-space:pre-wrap;'>"
                    f"{thinking}</div>"
                )
                st.markdown(html, unsafe_allow_html=True)

        placeholder.markdown(clean_answer or final_response or "_(empty)_")

        if final_response:
            state.append_message("assistant", clean_answer or final_response)

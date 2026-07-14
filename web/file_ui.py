# web/file_ui.py — Streamlit UI components for file upload & attachment
# New module: imported by ui.py; zero modifications to existing layout logic.

import os
import streamlit as st
from typing import List, Optional, Dict

import files
import config

# ---------------------------------------------------------------------------
# Session-state helpers (isolated to this module)
# ---------------------------------------------------------------------------
_ATTACH_KEY = "mikie_attached_uids"
_UPLOAD_KEY = "mikie_file_uploader"
UPLOAD_DIR = getattr(config, "UPLOAD_DIR", "/workspace/uploaded")

def _get_attached() -> List[str]:
    return st.session_state.get(_ATTACH_KEY, [])


def _set_attached(uids: List[str]) -> None:
    st.session_state[_ATTACH_KEY] = uids


def _toggle_attach(uid: str) -> None:
    current = _get_attached()
    if uid in current:
        current.remove(uid)
    else:
        current.append(uid)
    _set_attached(current)


# ---------------------------------------------------------------------------
# Icon map for file types
# ---------------------------------------------------------------------------
_TYPE_ICON = {
    ".py": "🐍", ".js": "📜", ".ts": "📘", ".html": "🌐", ".css": "🎨",
    ".json": "📋", ".yml": "⚙️", ".yaml": "⚙️", ".md": "📝", ".txt": "📄",
    ".sh": "🖥️", ".go": "🔵", ".rs": "🦀", ".java": "☕", ".c": "🔧",
    ".cpp": "🔧", ".h": "📑", ".sql": "🗃️", ".csv": "📊",
    ".pdf": "📕", ".doc": "📘", ".docx": "📘",
    ".png": "🖼️", ".jpg": "🖼️", ".jpeg": "🖼️", ".gif": "🎞️", ".webp": "🖼️", ".svg": "✏️",
    ".zip": "🗜️", ".tar": "🗜️", ".gz": "🗜️",
}


def _icon_for(ext: str) -> str:
    return _TYPE_ICON.get(ext.lower(), "📎")

def _fmt_size(b: int) -> str:
    if b < 1024: return f"{b} B"
    if b < 1024 * 1024: return f"{b / 1024:.1f} KB"
    return f"{b / (1024 * 1024):.1f} MB"

# ---------------------------------------------------------------------------
# 1. Sidebar file manager (upload + list + actions)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# 1. Sidebar File Manager
# ---------------------------------------------------------------------------
def render_file_manager() -> None:
    st.subheader("📁 File Vault")
    st.caption(f"Storing to: `{UPLOAD_DIR}`")
    st.markdown("---")

    uploaded_files = st.file_uploader(
        "Upload files", accept_multiple_files=True,
        key=_UPLOAD_KEY, label_visibility="collapsed"
    )

    if uploaded_files:
        with st.spinner("Processing uploads..."):
            for uploaded in uploaded_files:
                content = uploaded.read()
                meta, err = files.store_uploaded_file(uploaded.name, content)
                if err:
                    st.error(f"❌ {uploaded.name}: {err}")
                else:
                    st.success(f"✅ {_icon_for(meta.ext)} {meta.name} ({_fmt_size(meta.size_bytes)})")
                    if meta.uid not in _get_attached():
                        _toggle_attach(meta.uid)
    

    st.markdown("---")

    stored = files.list_stored_files()
    if not stored:
        st.info("No files stored yet. Upload above to get started.")
        return

    total = files.total_storage_used()
    if total > 500 * 1024 * 1024:
        st.warning(f"⚠️ High storage usage: {_fmt_size(total)}")

    st.markdown(f"**{len(stored)} file(s) stored** — {_fmt_size(total)} total")
    st.markdown("---")

    attached = _get_attached()
    for meta in stored:
        cols = st.columns([0.08, 0.52, 0.2, 0.2])

        is_attached = meta.uid in attached
        with cols[0]:
            new_state = st.checkbox("", value=is_attached, key=f"attach_{meta.uid}", label_visibility="collapsed")
            if new_state != is_attached:
                _toggle_attach(meta.uid)
                st.rerun()

        with cols[1]:
            icon = _icon_for(meta.ext)
            label = f"{icon} {meta.name}"
            with st.expander(label, expanded=False):
                text, err = files.extract_text_for_llm(meta)
                if err:
                    st.warning(err)
                elif text:
                    preview = text[:2000] + ("..." if len(text) > 2000 else "")
                    st.code(preview, language="")
                else:
                    st.info("No text content extracted.")

        with cols[2]:
            st.caption(_fmt_size(meta.size_bytes))
            st.caption(f"`{meta.ext or 'unknown'}`")

        with cols[3]:
            if st.button("🗑️", key=f"del_{meta.uid}", help="Remove file"):
                files.delete_file(meta.uid)
                if meta.uid in _get_attached():
                    _toggle_attach(meta.uid)
                #st.rerun()

    st.markdown("---")
    c1, c2 = st.columns(2)
    with c1:
        if st.button("📎 Attach All", use_container_width=True):
            _set_attached([m.uid for m in stored])
            st.rerun()
    with c2:
        if st.button("❌ Detach All", use_container_width=True):
            _set_attached([])
            st.rerun()


# ---------------------------------------------------------------------------
# 2. Attachment bar (rendered above chat input)
# ---------------------------------------------------------------------------

def render_attachment_bar() -> None:
    """Show compact chips of currently-attached files above the chat input.
    Call this from ui.py right before st.chat_input()."""
    attached = _get_attached()
    if not attached:
        return

    stored = files.list_stored_files()
    stored_map = {m.uid: m for m in stored}

    chips = []
    for uid in attached:
        meta = stored_map.get(uid)
        if meta:
            chips.append(f"{_icon_for(meta.ext)} {meta.name}")

    if chips:
        st.markdown(
            "<div style='margin-bottom:4px; font-size:0.85em; color:#888;'>📎 Attached: "
            + " &nbsp;|&nbsp; ".join(chips)
            + "</div>",
            unsafe_allow_html=True,
        )


def get_attached_for_message() -> str:
    """Build the file context string for the current message.
    Call this from ui.render_generation_sequence() in place of the old file_context logic."""
    attached = _get_attached()
    if not attached:
        return ""

    context, _ = files.build_context_from_attached(attached)
    return context


# ---------------------------------------------------------------------------
# 3. Message file chips (rendered with chat messages)
# ---------------------------------------------------------------------------

def render_message_file_chips(message_content: str) -> None:
    """If a chat message contains file attachment markers, render them as chips.
    Call this from ui.render_chat_history() per message."""
    import re

    if "--- LOCAL WORKSPACE FILE ATTACHED ---" not in message_content:
        return

    # Extract file headers from the raw message to show what files were attached
    file_headers = re.findall(r"=== FILE: (.+?) ===", message_content)
    if not file_headers:
        return

    cols = st.columns(min(len(file_headers), 6))
    for i, fname in enumerate(file_headers):
        ext = os.path.splitext(fname)[1]
        icon = _icon_for(ext)
        with cols[i % len(cols)]:
            st.markdown(
                f"<span style='background:#1a1a2e; color:#a0c4ff; padding:2px 8px; "
                f"border-radius:10px; font-size:0.75em; border:1px solid #2a2a4e;'>"
                f"{icon} {fname}</span>",
                unsafe_allow_html=True,
            )

# web/ui.py — Updated for multi-file vault support
# Changes from original: import file_ui, call render_file_manager(),
#                        render_attachment_bar(), get_attached_for_message(),
#                        render_message_file_chips().
# All other functions remain IDENTICAL to preserve core functionality.

import streamlit as st
import time
import config
import state
import client
import files            # NEW: file storage backend (new module)
import file_ui          # NEW: file UI components (new module)
from typing import Optional


def inject_global_styles() -> None:
    st.markdown(config.CUSTOM_CSS, unsafe_allow_html=True)


def render_header() -> None:
    st.title("⚡ MIKIE")
    st.caption("Modular Integrated Kinetic AI Engine — TitanX")


def render_sidebar_controls() -> Optional[str]:
    with st.sidebar:
        st.header("⚙️ System Status")
        if not client.check_hermes_health():
            st.error("⚠️ Hermes Endpoint: Offline")
        else:
            st.success("🟢 Hermes Endpoint: Online")

        st.markdown("---")

        # REPLACED: single-file uploader → full file vault manager
        file_ui.render_file_manager()

    # Return file context from attached files ( NEW: multi-file context )
    return file_ui.get_attached_for_message()


def render_chat_history() -> None:
    for msg in state.get_messages():
        if msg["role"] == "system" or "--- LOCAL WORKSPACE FILE ATTACHED" in msg["content"]:
            continue
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])
            # NEW: show file chips if this message had attachments
            file_ui.render_message_file_chips(msg["content"])


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

    with st.chat_message("assistant"):
        placeholder = st.empty()
        placeholder.markdown("Thinking...")

        stop_slot = st.empty()
        if stop_slot.button("🛑 Stop Generation", key=f"stop_{int(time.time()*1000)}", type="primary"):
            state.set_stop_flag(True)

        final_response = client.run_routing_pipeline(state.get_messages(), placeholder)

        stop_slot.empty()

        thinking, clean_answer = client.extract_thinking_and_answer(final_response)
        if thinking:
            with st.expander("🤔 Thinking Process", expanded=False):
                st.markdown(
                    f"<div style='font-size:0.9em; color:#aaaaaa; background:#1a1a1a; padding:12px; border-radius:8px; white-space:pre-wrap;'>{thinking}</div>",
                    unsafe_allow_html=True,
                )

        placeholder.markdown(clean_answer)
        state.append_message("assistant", final_response)

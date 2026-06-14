# web/ui.py
import streamlit as st
import time
import config
import state
import client
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
        st.subheader("📁 Workspace Context")
        uploaded_file = st.file_uploader(
            "Inject repository metadata", 
            type=["txt", "md", "py", "json", "yml", "yaml", "sh"]
        )
        
        if uploaded_file:
            st.markdown(f"<div class='file-box'>✅ Context: <b>{uploaded_file.name}</b></div>", unsafe_allow_html=True)
            content = state.read_workspace_file(uploaded_file)
            if isinstance(content, str) and content.startswith("FILE_READ_ERROR"):
                st.error(content)
                return None
            return content
    return None

def render_chat_history() -> None:
    for msg in state.get_messages():
        if msg["role"] == "system" or "--- LOCAL WORKSPACE FILE ATTACHED" in msg["content"]:
            continue
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

def render_generation_sequence(prompt: str, file_context: Optional[str]) -> None:
    user_payload = prompt
    if file_context:
        user_payload = f"--- LOCAL WORKSPACE FILE ATTACHED ---\n{file_context}\n\nUser Message: {prompt}"

    state.append_message("user", user_payload)
    
    with st.chat_message("user"):
        st.markdown(prompt)

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
                    unsafe_allow_html=True
                )
        
        placeholder.markdown(clean_answer)
        state.append_message("assistant", final_response)
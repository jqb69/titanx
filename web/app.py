# web/app.py
import streamlit as st

try:
    import state
    import ui
    import client
    import config
except Exception as e:
    st.error(f"🚨 Critical module load error: {e}")
    st.stop()

def main():
    ui.inject_global_styles()
    state.init_session()
    
    file_content_matrix = ui.render_sidebar_controls()
    ui.render_header()
    ui.render_chat_history()

    if user_input_prompt := st.chat_input("Ask MIKIE anything..."):
        state.set_stop_flag(False)
        ui.render_generation_sequence(user_input_prompt, file_content_matrix)

if __name__ == "__main__":
    main()
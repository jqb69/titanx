# web/app.py
import streamlit as st

try:
    import state
    import ui
    import client
    import config
    import file_ui
    import files 
    import login_ui
except Exception as e:
    st.error(f"🚨 Critical module load error: {e}")
    st.stop()

def main():

    if "logout_confirm_started" not in st.session_state:
        st.session_state.logout_confirm_started = None
      
    if login_ui.handle_idle_timeout():
        return
  
    if "token" not in st.session_state:
        login_ui.render_login_page()
        st.stop()
    # Simple page switch
    if st.session_state.get("page") == "account":
        import account
        account.account_page()
        return
    #st.sidebar.success(f"👤 {st.session_state.get('username', 'User')}")

    # Logout button
    #login_ui.add_logout_button()
    ui.inject_global_styles()
    state.init_session()
    
    file_content_matrix = ui.render_sidebar_controls()
    ui.render_header()
    ui.render_chat_history()
    file_ui.render_attachment_bar()

    if user_input_prompt := st.chat_input("Ask MIKIE anything..."):
        state.set_stop_flag(False)
        ui.render_generation_sequence(user_input_prompt, file_content_matrix)

if __name__ == "__main__":
    main()

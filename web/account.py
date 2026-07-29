# web/account.py
import streamlit as st
import re
import auth

def is_valid_email(email: str) -> bool:
    return bool(re.match(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", email))

def account_page():
    st.header("👤 Account Management")

    if "username" not in st.session_state:
        st.error("Please log in first")
        return

    username = st.session_state.username
    current = auth.get_user_settings(username) or {}

    with st.form("account_form"):
        st.subheader("Update Your Information")

        email = st.text_input("Email", value=current.get("email", ""))
        phone = st.text_input("Phone", value=current.get("phone", ""), placeholder="+1234567890")
        new_password = st.text_input("New Password", type="password", help="Leave blank to keep current")
        confirm_password = st.text_input("Confirm New Password", type="password")

        if st.form_submit_button("Save Changes", type="primary"):
            updates = {}

            if email:
                if not is_valid_email(email):
                    st.error("Invalid email format")
                    return
                updates["email"] = email.strip().lower()

            if phone:
                try:
                    phone = auth._normalize_phone(phone)
                    updates["phone"] = phone
                except ValueError as e:
                    st.error(str(e))
                    return

            if new_password:
                if new_password != confirm_password:
                    st.error("Passwords do not match")
                    return
                updates["password"] = new_password

            if updates:
                success, msg = auth.save_user_settings(username, updates)
                if success:
                    st.success("Account updated")
                else:
                    st.error(msg)
            else:
                st.info("No changes made")

    if st.button("← Back to Chat"):
        st.session_state.page = "chat"
        st.rerun()

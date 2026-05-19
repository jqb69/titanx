# web/app.py
import streamlit as st
import requests
import time

st.set_page_config(page_title="MIKIE", page_icon="⚡", layout="centered")

# Black & White Clean Theme
st.markdown("""
<style>
    .stApp { background-color: #0a0a0a; color: #ffffff; }
    .stChatMessage { border-radius: 12px; padding: 14px; }
    h1 { color: #ffffff; text-align: center; font-weight: 300; }
</style>
""", unsafe_allow_html=True)

def init_session():
    if "messages" not in st.session_state:
        st.session_state.messages = []

def display_messages():
    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

def send_message(prompt):
    st.session_state.messages.append({"role": "user", "content": prompt})
    
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        placeholder = st.empty()
        full_response = ""
        try:
            with requests.post(
                "http://hermes:8642/chat", 
                json={"message": prompt}, 
                stream=True, 
                timeout=90
            ) as r:
                for chunk in r.iter_content(chunk_size=512):
                    if chunk:
                        full_response += chunk.decode('utf-8', errors='ignore')
                        placeholder.markdown(full_response + "▌")
        except Exception as e:
            full_response = f"❌ Hermes not responding: {e}"
        
        placeholder.markdown(full_response)
        st.session_state.messages.append({"role": "assistant", "content": full_response})

def main_ui():
    st.title("⚡ MIKIE")
    st.caption("Modular Integrated Kinetic AI Engine")
    display_messages()
    
    if prompt := st.chat_input("Ask MIKIE anything..."):
        send_message(prompt)

if __name__ == "__main__":
    init_session()
    main_ui()

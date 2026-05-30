# web/app.py
import streamlit as st
import requests
import time

st.set_page_config(page_title="MIKIE", page_icon="⚡", layout="centered")

st.markdown("""
<style>
    .stApp { background-color: #0a0a0a; color: #ffffff; }
    .stChatMessage { border-radius: 12px; padding: 14px; }
    h1 { color: #ffffff; text-align: center; font-weight: 300; }
</style>
""", unsafe_allow_html=True)

@st.cache_resource(show_spinner=False)
def check_hermes_health():
    try:
        r = requests.get("http://titanx-hermes:8642/health", timeout=8)
        return r.status_code == 200
    except:
        return False

def init_session():
    if "messages" not in st.session_state:
        st.session_state.messages = []

# ====================== UI FUNCTIONS ======================
def display_messages():
    for msg in st.session_state.messages:
        with st.chat_message(msg["role"]):
            st.markdown(msg["content"])

def send_message(prompt: str):
    st.session_state.messages.append({"role": "user", "content": prompt})
    
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        placeholder = st.empty()
        full_response = ""
        
        try:
            with requests.post(
                "http://titanx-hermes:8642/chat",
                json={"message": prompt},
                stream=True,
                timeout=120
            ) as r:
                for line in r.iter_lines():
                    if line:
                        chunk = line.decode('utf-8', errors='ignore')
                        full_response += chunk
                        placeholder.markdown(full_response + "▌")
        except requests.exceptions.ConnectionError:
            full_response = "❌ Cannot connect to Hermes backend."
        except requests.exceptions.Timeout:
            full_response = "⏱️ Request timed out."
        except Exception as e:
            full_response = f"❌ Error: {e}"

        placeholder.markdown(full_response)
        st.session_state.messages.append({"role": "assistant", "content": full_response})

def main_ui():
    st.title("⚡ MIKIE")
    st.caption("Modular Integrated Kinetic AI Engine")

    # Show health status
    if not check_hermes_health():
        st.warning("⚠️ Hermes backend is not responding. Chat may not work.")

    display_messages()

    if prompt := st.chat_input("Ask MIKIE anything..."):
        send_message(prompt)

# ====================== MAIN ======================
if __name__ == "__main__":
    init_session()
    main_ui()

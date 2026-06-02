# web/app.py
import streamlit as st
import requests
import time
import os

st.set_page_config(page_title="MIKIE", page_icon="⚡", layout="centered")

st.markdown("""
<style>
    .stApp { background-color: #0a0a0a; color: #ffffff; }
    .stChatMessage { border-radius: 12px; padding: 14px; }
    h1 { color: #ffffff; text-align: center; font-weight: 300; }
</style>
""", unsafe_allow_html=True)
HERMES_URL = os.getenv("HERMES_URL", "http://titanx-hermes:8642")
HERMES_API_KEY = os.getenv("HERMES_API_KEY")

@st.cache_resource(ttl=60)
def check_hermes_health():
    try:
        headers = {"Authorization": f"Bearer {HERMES_API_KEY}"} if HERMES_API_KEY else {}
        r = requests.get(f"{HERMES_URL}/health", headers=headers, timeout=8)
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
            headers = {"Authorization": f"Bearer {HERMES_API_KEY}"} if HERMES_API_KEY else {}
            with requests.post(
                f"{HERMES_URL}/chat",
                json={"message": prompt},
                headers=headers,
                stream=True,
                timeout=120
            ) as r:
                if not r.ok:
                    # Graceful display instead of raising
                    error_msg = f"❌ Hermes API Error: {r.status_code} {r.reason}"
                    if r.text:
                        error_msg += f" - {r.text[:150]}"
                    full_response = error_msg
                else:
                    for line in r.iter_lines(decode_unicode=True):
                        if not line:
                            continue
                        if line.startswith("data:"):
                            chunk = line[len("data:"):].lstrip()
                        else:
                            chunk = line
                        full_response += chunk
                        placeholder.markdown(full_response + "▌")
        except requests.exceptions.ConnectionError:
            full_response = "❌ Cannot connect to Hermes backend."
        except requests.RequestException as e:
            full_response = f"❌ Network error contacting Hermes: {e}"  
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

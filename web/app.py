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

        headers = {"Authorization": f"Bearer {HERMES_API_KEY}"} if HERMES_API_KEY else {}
        endpoints = ["/", "v1/chat/completions","/chat", "/api/chat", "/v1/chat", "/message"]

        try:
            for endpoint in endpoints:
                url = f"{HERMES_URL}/v1/chat/completions"
                with requests.post(
                    url,
                    json={
                        "model": "hermes",           # or any model name Hermes accepts
                        "messages": [{"role": "user", "content": prompt}],
                        "stream": True
                    },
                    headers=headers,
                    stream=True,
                    timeout=90
                ) as r:
                    if r.status_code == 200:
                        for line in r.iter_lines(decode_unicode=True):
                            if not line:
                                continue
                            if line.startswith("data:"):
                                if line.strip() == "data: [DONE]":
                                    break
                                try:
                                    chunk = line[len("data:"):].strip()
                                    if chunk:
                                        full_response += chunk  # You can parse delta.content for cleaner text if needed
                                except:
                                    pass
                            placeholder.markdown(full_response + "▌")
                            break  # Success - break loop idiot stop trying other endpoints

                    else:
                        # Show detailed error from first non-404 response
                        full_response = f"❌ Hermes Error {r.status_code}: {r.reason}\n{r.text[:250]}"
                        continue  # Stop on real error (not just 404)

            # If we exhausted all endpoints without success
            if not full_response:
                full_response = f"❌ Hermes returned 404 on all tested endpoints at {HERMES_URL}"

        except requests.exceptions.ConnectionError:
            full_response = f"❌ Cannot connect to Hermes at {HERMES_URL}"
        except requests.exceptions.Timeout:
            full_response = "⏱️ Request timed out."
        except Exception as e:
            full_response = f"❌ Unexpected error: {e}"

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

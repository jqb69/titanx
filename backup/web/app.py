# web/app.py
import streamlit as st
import requests
import time
import os
import json
from typing import Optional

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

 # ====================== HELPER ======================
def post_to_hermes(url, headers, prompt, placeholder):
    """Helper to post to Hermes and stream response"""
    full_response = ""

    try:
        with requests.post(
            url,
            json={
                "model": "hermes",
                "messages": [{"role": "user", "content": prompt}],
                "stream": True
            },
            headers=headers,
            stream=True,
            timeout=(5, 120)
        ) as r:
            # Catch bad endpoints immediately
            if r.status_code != 200:
                return f"❌ Hermes Error {r.status_code}: {r.reason}\n{r.text[:300]}"

            for raw in r.iter_lines(decode_unicode=True):
                if not raw or raw.strip() == "data: [DONE]":
                    continue

                if raw.startswith("data:"):
                    chunk = raw[len("data:"):].strip()
                else:
                    chunk = raw.strip()

                if not chunk:
                    continue

                try:
                    data = json.loads(chunk)
                    content = data.get("choices", [{}])[0].get("delta", {}).get("content", "")
                    if content:
                        full_response += content
                        placeholder.markdown(full_response + "▌")
                except json.JSONDecodeError:
                    continue  # Skip garbage / HTML responses
                except Exception:
                    continue  # Skip any parsing error

    except requests.exceptions.ConnectionError:
        return f"❌ Cannot connect to Hermes at {url}"
    except requests.exceptions.Timeout:
        return "⏱️ Request timed out."
    except Exception as e:
        return f"❌ Error: {e}"

    return full_response or "❌ Hermes returned no content. Check backend logs."

def send_message(prompt: str):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        placeholder = st.empty()

        headers = {"Authorization": f"Bearer {HERMES_API_KEY}"} if HERMES_API_KEY else {}
        
        # CRITICAL FIX: /v1/chat/completions is forced to the top of the hierarchy
        endpoints = ["/v1/chat/completions", "/", "/chat", "/api/chat", "/v1/chat", "/message"]
        
        full_response: Optional[str] = None
        for endpoint in endpoints:
            url = HERMES_URL.rstrip("/") + endpoint
            resp = post_to_hermes(url, headers, prompt, placeholder)
            
            # If we get a valid response that isn't an error block, lock it in and break
            if resp and not resp.startswith("❌"):
                full_response = resp
                break
            
            # Keep last error if none succeed
            full_response = resp
        
        # Final render without the cursor block
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

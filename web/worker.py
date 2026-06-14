# web/worker.py
import json
import time
import uuid
from redis import Redis
import requests
import config

def enqueue_job(payload: dict) -> dict:
    """Encapsulated Redis enqueue - called from client.py"""
    try:
        r = Redis.from_url(
            config.REDIS_URL,
            socket_connect_timeout=5,
            socket_timeout=5,
            decode_responses=True
        )
        job_id = payload.get("task_id") or str(uuid.uuid4())
        payload["task_id"] = job_id
        payload["status"] = "queued"
        payload["queued_at"] = time.time()
        
        r.rpush("hermes:jobs", json.dumps(payload))
        r.close()
        
        return {"queued": True, "job_id": job_id}
    except Exception as e:
        return {"error": str(e)}


def process_job(job: dict) -> dict:
    """Idempotent job processor"""
    job_id = job.get("task_id")
    if not job_id:
        return {"status": "failed", "error": "Missing job_id"}

    r = Redis.from_url(config.REDIS_URL, decode_responses=True, socket_connect_timeout=5)
    if r.hget("hermes:results", job_id):
        print(f"Job {job_id} already processed")
        return {"status": "completed"}  # already done

    # Mark as processing
    r.hset("hermes:results", job_id, json.dumps({"status": "processing", "job_id": job_id}))
    r.close()

    try:
        url = f"{config.HERMES_URL}/v1/chat/completions"
        headers = {"Authorization": f"Bearer {config.HERMES_API_KEY}"} if getattr(config, "HERMES_API_KEY", None) else {}

        resp = requests.post(
            url, 
            json={
                "model": job.get("model", config.OPENROUTER_MODEL),
                "messages": job.get("messages", []),
                "stream": False
            },
            headers=headers, 
            timeout=180
        )

        if resp.status_code == 200:
            content = resp.json().get("choices", [{}])[0].get("message", {}).get("content", "")
            result = {"status": "completed", "response": content, "job_id": job_id}
        else:
            result = {"status": "failed", "error": f"HTTP {resp.status_code}", "job_id": job_id}
    except Exception as e:
        result = {"status": "failed", "error": str(e), "job_id": job_id}

    # Save result
    r = Redis.from_url(config.REDIS_URL, decode_responses=True, socket_connect_timeout=5)
    r.hset("hermes:results", job_id, json.dumps(result))
    r.expire("hermes:results", 86400)
    r.close()

    return result


def run_worker():
    print("🚀 TitanX Worker started...")
    r = Redis.from_url(config.REDIS_URL, decode_responses=True)
    
    while True:
        try:
            item = r.brpop("hermes:jobs", timeout=10)
            if item:
                _, raw = item
                job = json.loads(raw)
                process_job(job)
        except Exception as e:
            print(f"Worker error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    run_worker()

# web/worker.py
import json
import time
import uuid
import logging
from redis import Redis
import requests
import config

logging.basicConfig(level=logging.INFO, format="[%(asctime)s] [WORKER] %(message)s")
logger = logging.getLogger(__name__)


def _redis():
    return Redis.from_url(
        config.REDIS_URL,
        socket_connect_timeout=5,
        socket_timeout=5,
        decode_responses=True,
    )


def enqueue_job(payload: dict) -> dict:
    """Called from client.py"""
    try:
        r = _redis()
        job_id = payload.get("task_id") or payload.get("id") or str(uuid.uuid4())
        payload["task_id"] = job_id
        payload["status"] = "queued"
        payload["queued_at"] = time.time()

        r.rpush(config.HERMES_QUEUE, json.dumps(payload))
        r.close()

        logger.info(f"Job enqueued: {job_id}")
        return {"queued": True, "job_id": job_id}
    except Exception as e:
        logger.error(f"Enqueue failed: {e}")
        return {"queued": False, "error": str(e)}


def _get_workspace_prefix(queue_name: str) -> str:
    """Return correct workspace path for the agent."""
    if queue_name == config.HERMES_QUEUE:
        return "/workspace"
    return "/workspace/avangarde"


def process_job(job: dict, hermes_url: str, queue_name: str) -> dict:
    """Process job with workspace-aware system prompt."""
    job_id = job.get("task_id") or job.get("id", "unknown")
    model = job.get("model", config.OPENROUTER_MODEL)
    workspace_path = _get_workspace_prefix(queue_name)

    # GPT-5 improved system message
    system_prompt = {
        "role": "system",
        "content": (
            f"You are operating in the workspace directory: {workspace_path}. "
            f"This is guidance for how to reference files (the worker does not enforce filesystem access). "
            f"Keep all context consistent with this path."
        ),
    }

    messages = [system_prompt] + (job.get("messages", []) or [])

    try:
        resp = requests.post(
            f"{hermes_url}/v1/chat/completions",
            json={
                "model": model,
                "messages": messages,
                "stream": False,
            },
            headers={"Authorization": f"Bearer {config.HERMES_API_KEY}"} if getattr(config, "HERMES_API_KEY", None) else {},
            timeout=180,
        )
        resp.raise_for_status()

        content = resp.json().get("choices", [{}])[0].get("message", {}).get("content", "")

        return {
            "job_id": job_id,
            "status": "completed",
            "content": content,
            "response": content,
            "workspace": workspace_path,
        }

    except Exception as e:
        logger.error(f"Job {job_id} failed on {hermes_url}: {e}")
        return {"job_id": job_id, "status": "failed", "error": str(e)}


def run_worker():
    r = _redis()
    logger.info("🚀 Dual-Agent Worker started with intelligent workspace routing")

    results_hash = getattr(config, "RESULTS_HASH", "hermes:results")

    while True:
        try:
            item = r.brpop([config.HERMES_QUEUE, config.AVANGARDE_QUEUE], timeout=10)
            if not item:
                continue

            queue_name, raw = item
            job = json.loads(raw)
            job_id = job.get("task_id") or job.get("id") or "unknown"

            # Idempotency check
            if r.hget(results_hash, job_id):
                logger.info(f"Job {job_id} already processed - skipping")
                continue

            hermes_url = config.HERMES_URL if queue_name == config.HERMES_QUEUE else config.AVANGARDE_URL

            result = process_job(job, hermes_url, queue_name)

            r.hset(results_hash, job_id, json.dumps(result))
            r.expire(results_hash, 86400)
            r.lpush(config.RESULTS_QUEUE, job_id)

            logger.info(f"Processed job {job_id} → {queue_name} (workspace: {result.get('workspace')})")

        except Exception as e:
            logger.error(f"Worker loop error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    run_worker()

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

DEFAULT_RESULT_TTL_SECONDS = 86400


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


def process_job(job: dict, hermes_url: str) -> dict:
    job_id = job.get("task_id") or job.get("id", "unknown")
    model = job.get("model", config.OPENROUTER_MODEL)

    try:
        resp = requests.post(
            f"{hermes_url}/v1/chat/completions",
            json={
                "model": model,
                "messages": job.get("messages", []),
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
            "response": content
        }
    except Exception as e:
        logger.error(f"Job {job_id} failed on {hermes_url}: {e}")
        return {"job_id": job_id, "status": "failed", "error": str(e)}


def run_worker():
    r = _redis()
    logger.info("🚀 Dual Worker started - Listening on hermes + avangarde queues")

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

            result = process_job(job, hermes_url)

            r.hset(results_hash, job_id, json.dumps(result))
            r.expire(results_hash, DEFAULT_RESULT_TTL_SECONDS)
            r.lpush(config.RESULTS_QUEUE, job_id)

        except Exception as e:
            logger.error(f"Worker loop error: {e}")
            time.sleep(1)


if __name__ == "__main__":
    run_worker()
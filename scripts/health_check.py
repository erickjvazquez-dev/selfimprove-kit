#!/usr/bin/env python3
"""Generic health check — reads CCF config, hits CCF_LIVE_URL + CCF_HEALTH_PATH."""
import os
import sys
import json
import time
import urllib.request
import urllib.error
from pathlib import Path


def load_env(project_dir: str) -> dict:
    env = {}
    env_file = Path(project_dir) / ".ccf" / "project.env"
    if not env_file.exists():
        return env
    for line in env_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, _, v = line.partition("=")
            env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def check(url: str, timeout: int = 8) -> tuple[int, dict | str]:
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "ccf-health/1.0"})
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read().decode()
            try:
                return resp.status, json.loads(body)
            except json.JSONDecodeError:
                return resp.status, body
    except urllib.error.HTTPError as e:
        return e.code, str(e)
    except Exception as e:
        return 0, str(e)


def main():
    project_dir = os.environ.get("CCF_PROJECT_DIR", os.getcwd())
    cfg = load_env(project_dir)

    # CLI overrides
    live_url = os.environ.get("CCF_LIVE_URL", cfg.get("CCF_LIVE_URL", ""))
    health_path = os.environ.get("CCF_HEALTH_PATH", cfg.get("CCF_HEALTH_PATH", "/health"))
    project_name = cfg.get("CCF_PROJECT_NAME", Path(project_dir).name)

    if not live_url:
        print("CCF_LIVE_URL not set — skipping live health check")
        sys.exit(0)

    url = live_url.rstrip("/") + health_path
    print(f"[{project_name}] health → {url}")

    start = time.time()
    status, body = check(url)
    elapsed = round((time.time() - start) * 1000)

    if status == 200:
        if isinstance(body, dict):
            svc_status = body.get("status", "?")
            version = body.get("version", "?")
            uptime = int(body.get("uptime_seconds", 0) // 60)
            print(f"  OK {status} — {svc_status} v{version} uptime:{uptime}min ({elapsed}ms)")
        else:
            print(f"  OK {status} ({elapsed}ms)")
        sys.exit(0)
    else:
        print(f"  FAIL {status} — {str(body)[:120]} ({elapsed}ms)")
        sys.exit(1)


if __name__ == "__main__":
    main()

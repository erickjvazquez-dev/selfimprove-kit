#!/usr/bin/env python3
"""
Generic Computer Use QA — Claude controls Chrome to test a live web app.
Reads CCF config from .ccf/project.env or environment variables.

Usage:
    python3 scripts/qa_computer_use.py
    CCF_LIVE_URL=https://myapp.com python3 scripts/qa_computer_use.py
"""
import base64
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path


def load_ccf_env(project_dir: str = None) -> dict:
    search = [project_dir or os.getcwd(), os.getcwd()]
    for d in search:
        p = Path(d) / ".ccf" / "project.env"
        if p.exists():
            env = {}
            for line in p.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, _, v = line.partition("=")
                env[k.strip()] = v.strip().strip('"').strip("'")
            return env
    return {}


CFG = load_ccf_env()
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", CFG.get("ANTHROPIC_API_KEY", ""))
BASE_URL = os.environ.get("CCF_LIVE_URL", CFG.get("CCF_LIVE_URL", "http://localhost:8000"))
PROJECT_NAME = CFG.get("CCF_PROJECT_NAME", "project")

# Computer Use tool type for claude-sonnet-4-6 (Claude 4 models use 2025 version)
COMPUTER_TOOL_TYPE = "computer_20250124"
SCREENSHOT_DIR = Path(os.environ.get("CCF_SCREENSHOT_DIR", "/tmp/ccf_cu_screenshots"))


@dataclass
class CUResult:
    name: str
    status: str = "PASS"   # PASS | FAIL | SKIP
    severity: str = "P2"
    evidence: str = ""
    screenshot: str = ""


@dataclass
class CUReport:
    status: str = "PASS"
    results: list = field(default_factory=list)

    def add(self, r: CUResult):
        self.results.append(r)
        if r.status == "FAIL" and r.severity in ("P0", "P1"):
            self.status = "FAIL"


def _check_screen_permission() -> bool:
    """Check macOS screen recording permission via screencapture."""
    try:
        result = subprocess.run(
            ["screencapture", "-x", "-t", "png", "/tmp/ccf_perm_test.png"],
            capture_output=True, timeout=5
        )
        if result.returncode == 0 and Path("/tmp/ccf_perm_test.png").exists():
            Path("/tmp/ccf_perm_test.png").unlink(missing_ok=True)
            return True
        return False
    except Exception:
        return False


def _take_screenshot() -> str | None:
    """Take a screenshot and return base64-encoded PNG."""
    path = f"/tmp/ccf_cu_{int(time.time())}.png"
    try:
        result = subprocess.run(
            ["screencapture", "-x", "-t", "png", path],
            capture_output=True, timeout=10
        )
        if result.returncode == 0 and Path(path).exists():
            data = base64.standard_b64encode(Path(path).read_bytes()).decode()
            return data
    except Exception:
        pass
    return None


def _run_computer_use_task(task_prompt: str, max_iterations: int = 8) -> tuple[str, str]:
    """
    Run a Computer Use task with Claude. Returns (status, evidence).
    status: 'PASS' | 'FAIL' | 'SKIP'
    """
    if not ANTHROPIC_API_KEY:
        return "SKIP", "ANTHROPIC_API_KEY not set"

    try:
        import urllib.request

        screenshot_b64 = _take_screenshot()
        if not screenshot_b64:
            return "SKIP", "Could not capture screen — check Screen Recording permission"

        messages = [{
            "role": "user",
            "content": [
                {
                    "type": "image",
                    "source": {"type": "base64", "media_type": "image/png", "data": screenshot_b64}
                },
                {"type": "text", "text": task_prompt}
            ]
        }]

        tools = [{
            "type": COMPUTER_TOOL_TYPE,
            "name": "computer",
            "display_width_px": 1280,
            "display_height_px": 800,
        }]

        for _ in range(max_iterations):
            payload = json.dumps({
                "model": "claude-sonnet-4-6",
                "max_tokens": 1024,
                "tools": tools,
                "messages": messages,
            }).encode()

            req = urllib.request.Request(
                "https://api.anthropic.com/v1/messages",
                data=payload,
                headers={
                    "x-api-key": ANTHROPIC_API_KEY,
                    "anthropic-version": "2023-06-01",
                    "anthropic-beta": "computer-use-2025-01-24",
                    "content-type": "application/json",
                }
            )

            with urllib.request.urlopen(req, timeout=30) as resp:
                response = json.loads(resp.read())

            stop_reason = response.get("stop_reason")
            content = response.get("content", [])

            messages.append({"role": "assistant", "content": content})

            if stop_reason == "end_turn":
                last_text = next(
                    (b["text"] for b in reversed(content) if b.get("type") == "text"), ""
                )
                verdict = "PASS" if any(w in last_text.upper() for w in ("PASS", "SUCCESS", "FOUND", "VISIBLE", "OK", "CONFIRMED")) else "FAIL"
                return verdict, last_text[:200]

            if stop_reason != "tool_use":
                break

            tool_results = []
            for block in content:
                if block.get("type") != "tool_use":
                    continue
                tool_name = block.get("name")
                tool_input = block.get("input", {})
                tool_id = block.get("id")

                if tool_name == "computer":
                    action = tool_input.get("action", "")
                    if action in ("screenshot", "key", "type", "mouse_move", "left_click",
                                  "right_click", "double_click", "scroll"):
                        if action != "screenshot":
                            _execute_action(action, tool_input)
                        time.sleep(0.5)
                        new_ss = _take_screenshot()
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": tool_id,
                            "content": [{
                                "type": "image",
                                "source": {"type": "base64", "media_type": "image/png",
                                           "data": new_ss or screenshot_b64}
                            }]
                        })
                    else:
                        tool_results.append({
                            "type": "tool_result",
                            "tool_use_id": tool_id,
                            "content": "Action not supported in this context"
                        })

            if tool_results:
                messages.append({"role": "user", "content": tool_results})

        return "SKIP", "Max iterations reached without conclusion"

    except Exception as e:
        return "FAIL", f"Computer Use API error: {e}"


def _execute_action(action: str, tool_input: dict):
    """Execute a Computer Use action via AppleScript / cliclick."""
    try:
        if action == "key":
            key = tool_input.get("text", "")
            subprocess.run(["osascript", "-e", f'tell application "System Events" to keystroke "{key}"'],
                           capture_output=True, timeout=5)
        elif action == "type":
            text = tool_input.get("text", "").replace('"', '\\"')
            subprocess.run(["osascript", "-e", f'tell application "System Events" to keystroke "{text}"'],
                           capture_output=True, timeout=5)
        elif action in ("mouse_move", "left_click", "right_click", "double_click"):
            x = tool_input.get("coordinate", [0, 0])[0]
            y = tool_input.get("coordinate", [0, 0])[1]
            click_map = {"left_click": "c", "right_click": "rc", "double_click": "dc", "mouse_move": "m"}
            flag = click_map.get(action, "c")
            subprocess.run(["cliclick", f"{flag}:{x},{y}"], capture_output=True, timeout=5)
        elif action == "scroll":
            x = tool_input.get("coordinate", [0, 0])[0]
            y = tool_input.get("coordinate", [0, 0])[1]
            direction = tool_input.get("direction", "down")
            amount = tool_input.get("amount", 3)
            flag = "u" if direction == "up" else "d"
            subprocess.run(["cliclick", f"s{flag}:{x},{y}", str(amount * 100)],
                           capture_output=True, timeout=5)
    except Exception:
        pass


def main():
    report = CUReport()
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)

    # Check screen recording permission
    if not _check_screen_permission():
        print("SKIP: Screen Recording permission not granted for Terminal.")
        print("Grant it in: System Preferences → Privacy & Security → Screen Recording")
        print("Then re-run this script.")
        sys.exit(0)

    if not ANTHROPIC_API_KEY:
        print("SKIP: ANTHROPIC_API_KEY not set. Set it in .ccf/project.env or as an environment variable.")
        sys.exit(0)

    print(f"Computer Use QA — {PROJECT_NAME}")
    print(f"Target: {BASE_URL}")
    print("─" * 50)

    # Task 1: Homepage loads
    status, evidence = _run_computer_use_task(
        f"Navigate to {BASE_URL} in Chrome. Confirm the page loads successfully "
        f"with visible content. Reply PASS if the page loaded correctly, FAIL if blank or error."
    )
    report.add(CUResult("homepage_loads", status, "P0" if status == "FAIL" else "P3", evidence))
    print(f"  [{status}] homepage_loads: {evidence[:80]}")

    # Task 2: Health endpoint
    status, evidence = _run_computer_use_task(
        f"Open Chrome devtools or address bar and navigate to {BASE_URL.rstrip('/')}/health. "
        f"Confirm you see JSON with 'status' field. Reply PASS if visible, FAIL if error."
    )
    report.add(CUResult("health_endpoint", status, "P1" if status == "FAIL" else "P3", evidence))
    print(f"  [{status}] health_endpoint: {evidence[:80]}")

    # Task 3: App/main feature page
    app_url = BASE_URL.rstrip("/") + "/app"
    status, evidence = _run_computer_use_task(
        f"Navigate to {app_url} in Chrome. Verify the page has a visible upload/input area "
        f"and is not blank or showing an error. Reply PASS or FAIL."
    )
    report.add(CUResult("app_page_loads", status, "P0" if status == "FAIL" else "P3", evidence))
    print(f"  [{status}] app_page_loads: {evidence[:80]}")

    print(f"\nOverall: {report.status}")
    print(f"Results: {sum(1 for r in report.results if r.status == 'PASS')} PASS, "
          f"{sum(1 for r in report.results if r.status == 'FAIL')} FAIL, "
          f"{sum(1 for r in report.results if r.status == 'SKIP')} SKIP")

    sys.exit(0 if report.status in ("PASS", "SKIP") else 1)


if __name__ == "__main__":
    main()

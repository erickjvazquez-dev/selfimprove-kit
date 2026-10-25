#!/usr/bin/env python3
"""
Generic browser QA via Playwright + optional Claude Vision grading.
Reads CCF_LIVE_URL from .ccf/project.env or environment.

Usage:
    python3 scripts/qa_browser.py [--headless] [--site app|landing|signup]
    CCF_LIVE_URL=https://myapp.com python3 scripts/qa_browser.py --headless
"""
import argparse
import base64
import json
import os
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

# ── Config ────────────────────────────────────────────────────────────────────

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
BASE_URL = os.environ.get("CCF_LIVE_URL", CFG.get("CCF_LIVE_URL", "http://localhost:8000"))
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", CFG.get("ANTHROPIC_API_KEY", ""))
PROJECT_NAME = CFG.get("CCF_PROJECT_NAME", "project")

SCREENSHOT_DIR = Path(os.environ.get("CCF_SCREENSHOT_DIR", "/tmp/ccf_qa_screenshots"))

# ── Data types ────────────────────────────────────────────────────────────────

@dataclass
class TestResult:
    name: str
    status: str = "PASS"   # PASS | FAIL | SKIP
    severity: str = "P2"
    evidence: str = ""
    screenshot: str = ""


@dataclass
class SiteReport:
    site: str
    status: str = "PASS"
    results: list = field(default_factory=list)

    def fail(self, name: str, evidence: str, severity: str = "P1", screenshot: str = ""):
        self.status = "FAIL"
        self.results.append(TestResult(name, "FAIL", severity, evidence, screenshot))

    def ok(self, name: str, evidence: str = ""):
        self.results.append(TestResult(name, "PASS", "P3", evidence))

    def skip(self, name: str, reason: str = ""):
        self.results.append(TestResult(name, "SKIP", "P3", reason))


# ── Vision grader ─────────────────────────────────────────────────────────────

def grade_screenshot(screenshot_path: str, question: str) -> str:
    """Ask Claude to grade a screenshot. Returns 'PASS', 'FAIL', or 'SKIP'."""
    if not ANTHROPIC_API_KEY or not Path(screenshot_path).exists():
        return "SKIP"
    try:
        import urllib.request
        img_data = base64.standard_b64encode(Path(screenshot_path).read_bytes()).decode()
        payload = json.dumps({
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 64,
            "messages": [{
                "role": "user",
                "content": [
                    {"type": "image", "source": {"type": "base64", "media_type": "image/png", "data": img_data}},
                    {"type": "text", "text": f"{question}\nReply with exactly one word: PASS or FAIL."}
                ]
            }]
        }).encode()
        req = urllib.request.Request(
            "https://api.anthropic.com/v1/messages",
            data=payload,
            headers={
                "x-api-key": ANTHROPIC_API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            }
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = json.loads(resp.read())
            answer = body["content"][0]["text"].strip().upper()
            return "PASS" if "PASS" in answer else "FAIL"
    except Exception as e:
        return f"SKIP ({e})"


# ── Playwright runner ──────────────────────────────────────────────────────────

def run_site_tests(site: str, headless: bool) -> SiteReport:
    report = SiteReport(site)
    SCREENSHOT_DIR.mkdir(parents=True, exist_ok=True)

    try:
        from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
    except ImportError:
        report.skip(f"{site}_playwright", "playwright not installed — run: pip install playwright && playwright install chromium")
        return report

    url_map = {
        "app":     BASE_URL.rstrip("/") + "/app",
        "landing": BASE_URL.rstrip("/") + "/",
        "signup":  BASE_URL.rstrip("/") + "/signup",
        "health":  BASE_URL.rstrip("/") + "/health",
    }
    url = url_map.get(site, BASE_URL.rstrip("/") + f"/{site}")

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=headless)
        ctx = browser.new_context(viewport={"width": 1280, "height": 800})
        page = ctx.new_page()

        ts = time.strftime("%H%M%S")
        ss_path = str(SCREENSHOT_DIR / f"{PROJECT_NAME}_{site}_{ts}.png")

        try:
            resp = page.goto(url, timeout=15000, wait_until="domcontentloaded")
            if resp and resp.status >= 400:
                report.fail(f"{site}_load", f"HTTP {resp.status}", "P0")
                return report
            report.ok(f"{site}_load", f"HTTP {resp.status if resp else '?'}")

            # Desktop screenshot
            page.screenshot(path=ss_path)
            report.results[-1].screenshot = ss_path

            # Vision grade: page loaded with content
            grade = grade_screenshot(ss_path, f"Does this web page look fully loaded with visible content (not blank/error)?")
            if grade == "FAIL":
                report.fail(f"{site}_content_visible", "Vision: page appears blank or broken", "P1", ss_path)
            elif grade == "PASS":
                report.ok(f"{site}_content_visible", "Vision: content visible")

            # Mobile viewport
            ctx2 = browser.new_context(viewport={"width": 375, "height": 812})
            page2 = ctx2.new_page()
            page2.goto(url, timeout=15000, wait_until="domcontentloaded")
            ss_mobile = str(SCREENSHOT_DIR / f"{PROJECT_NAME}_{site}_mobile_{ts}.png")
            page2.screenshot(path=ss_mobile)
            grade_m = grade_screenshot(ss_mobile, "Does this mobile layout look correct (no horizontal overflow, no overlapping elements)?")
            if grade_m == "FAIL":
                report.fail(f"{site}_mobile", "Vision: mobile layout broken", "P2", ss_mobile)
            elif grade_m == "PASS":
                report.ok(f"{site}_mobile", "Vision: mobile layout OK")
            ctx2.close()

        except PWTimeout:
            report.fail(f"{site}_load", f"Timeout loading {url}", "P0")
        except Exception as e:
            report.fail(f"{site}_error", str(e), "P1")
        finally:
            browser.close()

    return report


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--site", default="app", help="Site to test: app|landing|signup (or path)")
    parser.add_argument("--headless", action="store_true", default=True)
    parser.add_argument("--no-headless", dest="headless", action="store_false")
    parser.add_argument("--all-sites", action="store_true", help="Test app + landing + signup")
    args = parser.parse_args()

    sites = ["app", "landing", "signup"] if args.all_sites else [args.site]
    overall = "PASS"
    all_reports = []

    for site in sites:
        r = run_site_tests(site, args.headless)
        all_reports.append(r)
        if r.status == "FAIL":
            overall = "FAIL"

    print(f"\nBROWSER QA — {overall}")
    print(f"Base URL: {BASE_URL}")
    print("─" * 50)
    for r in all_reports:
        print(f"  [{r.status}] {r.site}")
        for t in r.results:
            icon = "✓" if t.status == "PASS" else ("✗" if t.status == "FAIL" else "~")
            line = f"    {icon} {t.name}"
            if t.evidence:
                line += f": {t.evidence}"
            if t.screenshot:
                line += f" [{t.screenshot}]"
            print(line)

    sys.exit(0 if overall == "PASS" else 1)


if __name__ == "__main__":
    main()

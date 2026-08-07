#!/usr/bin/env python3
"""Screenshot a Visualize.js (or any) page with headless Chrome.

Renders a URL in headless Chrome and waits for the page's #status div to report
"RENDERED OK" / "ERROR" before screenshotting -- used to verify the JRS
Visualize.js cross-origin embedding recipe (serve the embed page outside the
webapp; see plugins/jasper-deploy/skills/jasper-deploy/references/jrs-rest-api.md) actually
renders, not just loads.

Usage:
    python tools/viz_shot.py [URL] [OUT_PNG]
Defaults: http://localhost:8000/index.html -> out/viz_rendered.png

Requires Playwright with the installed Chrome channel:
    python -m pip install playwright   # uses channel="chrome", no chromium download
"""
import os
import sys

from playwright.sync_api import sync_playwright

URL = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000/index.html"
OUT = sys.argv[2] if len(sys.argv) > 2 else os.path.join("out", "viz_rendered.png")

os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)

with sync_playwright() as pw:
    # reuse the installed Chrome (channel='chrome') -- no chromium download
    browser = pw.chromium.launch(channel="chrome", headless=True)
    page = browser.new_page(viewport={"width": 1280, "height": 900})
    page.goto(URL, wait_until="networkidle", timeout=60000)
    # wait for our page's status div to report success
    try:
        page.wait_for_function(
            "document.getElementById('status') && /RENDERED OK|ERROR/.test(document.getElementById('status').textContent)",
            timeout=45000,
        )
    except Exception as e:
        print("wait timed out:", e)
    status = page.eval_on_selector("#status", "el => el.textContent")
    print("STATUS:", status)
    page.wait_for_timeout(1500)  # let the table paint
    page.screenshot(path=OUT, full_page=True)
    print("screenshot:", OUT)
    browser.close()

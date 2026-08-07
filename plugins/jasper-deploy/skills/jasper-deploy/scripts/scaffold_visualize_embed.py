#!/usr/bin/env python3
"""Scaffold a ready-to-open Visualize.js embed page for a deployed resource.

Generates the minimal verified host page from references/visualize-embedding.md:
loads visualize.js anonymously from the running server, authenticates
cross-origin via the auth block, and renders a report or dashboard into a div.
Serve the file from OUTSIDE the JRS webapp (e.g. `python -m http.server 8000`
in its directory) -- a page inside .../jasperserver-pro/ just 302s to login.

Security: the generated page embeds credentials IN CLEAR TEXT (that is how the
Visualize.js auth block works), so the password defaults to the placeholder
CHANGE_ME rather than any real secret -- pass --password only for throwaway
demo pages, and never commit a page holding a real credential.

Server/user default from the skill's jrs.config.json when present (the
password intentionally does NOT).

Usage:
  python scaffold_visualize_embed.py --uri /reports/geocoder/county_summary --out embed.html
  python scaffold_visualize_embed.py --uri /reports/foodmart/dash --type dashboard --out d.html
"""
import argparse
import json
import os
import sys

CFG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "jrs.config.json")

PAGE = """<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>{title}</title>
  <!-- served anonymously by JRS; do NOT add an Authorization header -->
  <script src="{server}/client/visualize.js"></script>
  <style>
    body {{ font-family: sans-serif; margin: 16px; }}
    #container {{ width: {width}px; height: {height}px; border: 1px solid #ddd; }}
    #status {{ color: #666; font-size: 12px; margin-top: 6px; }}
  </style>
</head>
<body>
  <h2>{title}</h2>
  <div id="container"></div>
  <div id="status">loading...</div>
  <script>
    // success flag for headless verification (Playwright wait_for_function --
    // see references/visualize-embedding.md; a bare --screenshot fires too early)
    window.__embedOk = false;
    visualize({{
      server: "{server}",
      auth:   {{ name: "{user}", password: "{password}" }}
    }}, function (v) {{
      v.{entry}({{
        resource:  "{uri}",
        container: "#container",
        success:   function () {{
          window.__embedOk = true;
          document.getElementById("status").textContent = "rendered {uri}";
        }},
        error:     function (e) {{
          document.getElementById("status").textContent = "error: " + (e.message || e);
          console.error(e);
        }}
      }});
    }}, function (err) {{
      document.getElementById("status").textContent = "auth failed: " + (err.message || err);
      console.error(err);
    }});
  </script>
</body>
</html>
"""

ENTRY = {"report": "report", "dashboard": "dashboard"}


def main():
    ap = argparse.ArgumentParser(description="Scaffold a Visualize.js embed page.")
    ap.add_argument("--uri", required=True, help="repository URI of the deployed resource")
    ap.add_argument("--type", choices=sorted(ENTRY), default="report",
                    help="resource kind (default report); dashboard uses v.dashboard")
    ap.add_argument("--server", help="JRS base URL (default: serverUrl from jrs.config.json)")
    ap.add_argument("--user", help="JRS user for the auth block (default: user from jrs.config.json)")
    ap.add_argument("--password", default="CHANGE_ME",
                    help="password baked into the page IN CLEAR TEXT; defaults to the "
                         "CHANGE_ME placeholder on purpose -- see the module docstring")
    ap.add_argument("--title", help="page title (default: the URI leaf)")
    ap.add_argument("--width", type=int, default=900)
    ap.add_argument("--height", type=int, default=600)
    ap.add_argument("--out", required=True, help="output .html path")
    args = ap.parse_args()

    cfg = {}
    if os.path.exists(CFG):
        try:
            with open(CFG, encoding="utf-8") as f:
                cfg = json.load(f)
        except (OSError, ValueError):
            pass
    server = (args.server or cfg.get("serverUrl") or "http://localhost:8081/jasperserver-pro").rstrip("/")
    user = args.user or cfg.get("user") or "joeuser"
    uri = args.uri if args.uri.startswith("/") else "/" + args.uri
    title = args.title or uri.rsplit("/", 1)[-1]

    html = PAGE.format(server=server, user=user, password=args.password,
                       uri=uri, entry=ENTRY[args.type], title=title,
                       width=args.width, height=args.height)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(html)
    print(f"OK: scaffolded {args.out} ({args.type} {uri} on {server}, user {user})")
    if args.password == "CHANGE_ME":
        print("NOTE: password is the CHANGE_ME placeholder -- edit the auth block "
              "(or re-run with --password) before opening the page.")
    print(f"Serve it from OUTSIDE the JRS webapp, e.g.:  python -m http.server 8000  "
          f"(then open http://localhost:8000/{os.path.basename(args.out)})")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Build a JRS input-control chain by hand: listOfValues -> inputControl -> reportUnit.

A worked example of wiring a single-select input control to a report parameter
purely over REST: create a standalone listOfValues resource, create an
inputControl (its name must equal the report's $P{param}) that references the
LOV, then patch the report unit to reference the control. This is the long-hand
of what `deploy_report.ps1 -Control "family:select:..."` now does for you -- kept
as a reference for bespoke control shapes the wrapper doesn't cover.

Assumptions (edit the constants below for another report):
  * the report unit already exists at RU, and its descriptor JSON is saved at
    --ru-json (default out/ru.json, e.g. from a prior GET) -- the script patches
    that copy's inputControls and PUTs it back.
  * credentials/host are the local JRS dev defaults (superuser on :8081).

Usage: python tools/mk_chain.py [RU_JSON]
"""
import json
import subprocess
import sys
import tempfile

U = "superuser:superuser"
B = "http://localhost:8081/jasperserver-pro/rest_v2"
RU = "/reports/foodmart/param_cat"
FILES = "/reports/foodmart/controls"      # a normal folder, not the _files companion
RU_JSON = sys.argv[1] if len(sys.argv) > 1 else "out/ru.json"


def put(uri, ctype, obj, q="?createFolders=true&overwrite=true"):
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(obj, f)
        p = f.name
    out = subprocess.run(["curl.exe", "-s", "-u", U, "-X", "PUT",
        "-H", f"Content-Type: {ctype}", "-H", "Accept: application/json",
        "--data-binary", f"@{p}", f"{B}/resources{uri}{q}", "-w", "\n%{http_code}"],
        capture_output=True, text=True).stdout
    code = out.rsplit("\n", 1)[-1]
    return code, out.rsplit("\n", 1)[0]


# 1. listOfValues resource
code, body = put(f"{FILES}/family_lov", "application/repository.listOfValues+json",
    {"label": "Family values", "items": [
        {"label": "Food", "value": "Food"},
        {"label": "Drink", "value": "Drink"},
        {"label": "Non-Consumable", "value": "Non-Consumable"}]})
print("LOV  ", code)

# 2. inputControl resource (name 'family' == report parameter); single-select list
code, body = put(f"{FILES}/family", "application/repository.inputControl+json",
    {"label": "Product Family", "mandatory": False, "readOnly": False, "visible": True,
     "type": 3, "listOfValues": {"listOfValuesReference": {"uri": f"{FILES}/family_lov", "version": 0}}})
print("IC   ", code, "" if code.startswith("2") else body[:300])

# 3. reference it from the report unit
ru = json.load(open(RU_JSON, encoding="utf-8-sig"))
ru.pop("inputControls", None)
ru["inputControls"] = [{"inputControlReference": {"uri": f"{FILES}/family"}}]
ru["controlsLayout"] = "popupScreen"
code, body = put(RU, "application/repository.reportUnit+json", ru, "?overwrite=true")
print("RUref", code, "" if code.startswith("2") else body[:300])

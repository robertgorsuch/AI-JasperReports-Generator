"""Jaspersoft Copilot - shared preflight module (Python).

Python mirror of ``Entitlement.psm1`` for the scaffolder scripts
(``scaffold_jrxml.py``, ``scaffold_domain_schema.py``, ``gen_dashboard.py``, ...).
Same four concerns, same feature map, same on-disk config/usage/audit layout, so
a PowerShell deploy step and a Python scaffold step bill and audit consistently.

STATUS: STUB. ``get_entitlement`` (signature verification), the secret vault, and
the metering transport are intentionally ``NotImplementedError``. Config
resolution, dry-run, and local NDJSON buffering are real.

Typical use at the top of a scaffolder::

    from copilot.preflight import entitlement as ent
    ent.assert_entitlement("report.scaffold")
    ...
    ent.write_usage("report.deployed", target_uri)   # if the scaffolder also deploys
"""

from __future__ import annotations

import hashlib
import json
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

# Tier -> capabilities. Keep in sync with $CopilotFeatureMap in Entitlement.psm1.
FEATURE_MAP: dict[str, list[str]] = {
    "starter": ["report.scaffold", "report.compile", "report.deploy", "report.verify"],
    "pro": ["domain.create", "dashboard.publish", "theme.deploy", "control.create",
            "job.schedule", "alert.create"],
    "enterprise": ["resource.promote", "admin.users", "admin.roles", "admin.orgs",
                   "dataplane.load", "dataplane.sql.write", "resource.delete"],
}

# Only these event names may be metered (mirrors the PS ValidateSet).
BILLABLE_EVENTS = {
    "report.deployed", "dashboard.published", "domain.created",
    "job.scheduled", "alert.created", "data.loaded",
}


@dataclass
class CopilotConfig:
    home: Path
    license_token: str | None
    active_profile: str | None
    profiles: list[dict[str, Any]]
    dry_run: bool
    usage_log: Path
    audit_log: Path


_config: CopilotConfig | None = None


def get_config() -> CopilotConfig:
    """Resolve config once: env CLAUDE_COPILOT_HOME, else ~/.jaspersoft-copilot."""
    global _config
    if _config is not None:
        return _config

    home = Path(os.environ.get("CLAUDE_COPILOT_HOME")
                or (Path.home() / ".jaspersoft-copilot"))
    home.mkdir(parents=True, exist_ok=True)
    cfg_path = home / "config.json"
    raw = json.loads(cfg_path.read_text()) if cfg_path.exists() else {}

    _config = CopilotConfig(
        home=home,
        # env overrides file, matching the PowerShell module
        license_token=os.environ.get("CLAUDE_COPILOT_LICENSE") or raw.get("licenseToken"),
        active_profile=os.environ.get("CLAUDE_COPILOT_PROFILE") or raw.get("activeProfile"),
        profiles=raw.get("profiles", []),
        dry_run=os.environ.get("CLAUDE_COPILOT_DRYRUN", "").lower() in ("1", "true"),
        usage_log=home / "usage.ndjson",
        audit_log=home / "audit.ndjson",
    )
    return _config


# --------------------------------------------------------------------------
# 1. Entitlement
# --------------------------------------------------------------------------
@dataclass
class Entitlement:
    account: str
    tier: str
    features: list[str] = field(default_factory=list)
    env_quota: int = 1
    seat: str | None = None
    exp: int | None = None


def get_entitlement() -> Entitlement:
    """Decode + verify the license token into claims.

    TODO(P0): verify Ed25519/JWT signature against the bundled public key, check
    ``exp`` and revocation. For now this is unimplemented so callers fail loud
    rather than trusting an unverified token.
    """
    cfg = get_config()
    if not cfg.license_token:
        raise RuntimeError(
            "Jaspersoft Copilot: no license token. "
            "Set CLAUDE_COPILOT_LICENSE or run 'copilot login'.")
    raise NotImplementedError(
        "License verification not implemented. Stub: wire signature check here (scope WS1).")


def test_feature(feature: str) -> bool:
    """True if the active tier grants *feature*. Stub mode allows everything."""
    try:
        return feature in get_entitlement().features
    except NotImplementedError:
        # STUB MODE: don't block development. Remove once get_entitlement is real.
        return True


def assert_entitlement(feature: str) -> None:
    """The preflight gate. Every mutating script calls this first."""
    if not test_feature(feature):
        raise PermissionError(
            f"Jaspersoft Copilot: your plan does not include '{feature}'. Upgrade to enable it.")


# --------------------------------------------------------------------------
# 2. Profiles & secrets
# --------------------------------------------------------------------------
def get_profile(name: str | None = None) -> dict[str, Any]:
    """Resolve a named connection profile (JRS URL/creds + DB)."""
    cfg = get_config()
    target = name or cfg.active_profile
    if not target:
        raise RuntimeError("Jaspersoft Copilot: no profile selected.")
    for p in cfg.profiles:
        if p.get("name") == target:
            return p
    raise RuntimeError(f"Jaspersoft Copilot: profile '{target}' not found.")


def resolve_secret(ref: str) -> str:
    """Resolve a secret ref to plaintext at call time (never written to work dir)."""
    if ref.startswith("env:"):
        return os.environ.get(ref[4:], "")
    if ref.startswith("vault:"):
        raise NotImplementedError("Vault backend: scope WS2 (P1).")
    if ref.startswith("keychain:"):
        raise NotImplementedError("OS keychain backend: scope WS2 (P1).")
    raise ValueError(f"Unrecognized secret ref '{ref}'. Use env:/vault:/keychain:.")


# --------------------------------------------------------------------------
# 3. Metering
# --------------------------------------------------------------------------
def _idempotency_key(event: str, uri: str, day: str) -> str:
    return hashlib.sha256(f"{event}|{uri}|{day}".encode()).hexdigest()[:32]


def write_usage(event: str, resource_uri: str, properties: dict | None = None) -> None:
    """Emit one billable usage event. Idempotent per (uri, event, day)."""
    if event not in BILLABLE_EVENTS:
        raise ValueError(f"Not a billable event: {event!r}")
    cfg = get_config()
    now = datetime.now(timezone.utc)
    if cfg.dry_run:
        return
    rec = {
        "idempotencyKey": _idempotency_key(event, resource_uri, now.strftime("%Y-%m-%d")),
        "event": event, "resourceUri": resource_uri,
        "ts": now.isoformat(), "properties": properties or {},
        "account": "<stub>", "seat": "<stub>", "env": cfg.active_profile,
    }
    with cfg.usage_log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
    # TODO(P1): buffered, batched, retried POST to the metering endpoint.


# --------------------------------------------------------------------------
# 4. Guardrails
# --------------------------------------------------------------------------
def write_audit(action: str, resource_uri: str, result: str = "ok") -> None:
    """Append-only audit record, separate from billing telemetry."""
    cfg = get_config()
    rec = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "action": action, "resourceUri": resource_uri, "result": result,
        "actor": os.environ.get("USERNAME") or os.environ.get("USER"),
        "profile": cfg.active_profile,
    }
    with cfg.audit_log.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")


def is_dry_run() -> bool:
    return get_config().dry_run

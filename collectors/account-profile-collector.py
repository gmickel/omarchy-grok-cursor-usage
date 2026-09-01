#!/usr/bin/env python3
"""Adapt one Claude or Codex profile into an independent Omarchy record."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys


PREFIX = "omarchy-agent-usage-"
SUPPORTED = {"claude": "CLAUDE_CONFIG_DIR", "codex": "CODEX_HOME"}


def fail(message: str) -> int:
    print(f"account-profile-collector: {message}", file=sys.stderr)
    return 2


def expand(value: str) -> str:
    return os.path.abspath(os.path.expandvars(os.path.expanduser(value)))


def main() -> int:
    invoked = Path(sys.argv[0]).name
    if not invoked.startswith(PREFIX):
        return fail(f"invoke through an {PREFIX}<id> link")
    account_id = invoked[len(PREFIX) :]

    config_path = Path(
        os.environ.get(
            "OMARCHY_AGENT_ACCOUNTS_FILE",
            "~/.config/omarchy/agents/accounts.json",
        )
    ).expanduser()
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
        account = config["accounts"][account_id]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        return fail(f"cannot load account {account_id!r} from {config_path}: {exc}")

    provider = str(account.get("provider", ""))
    if provider not in SUPPORTED:
        return fail(f"unsupported provider for {account_id}: {provider!r}")

    config_dir = str(account.get("configDir", "")).strip()
    if not config_dir:
        return fail(f"missing configDir for {account_id}")
    config_dir = expand(config_dir)
    if not Path(config_dir).is_dir():
        return fail(f"configDir does not exist for {account_id}: {config_dir}")

    collector_value = str(account.get("collector", "")).strip()
    collector = (
        Path(expand(collector_value))
        if collector_value
        else Path("/usr/bin") / f"omarchy-agent-usage-{provider}"
    )
    if not collector.is_file():
        return fail(f"base collector not found for {account_id}: {collector}")

    env = os.environ.copy()
    env[SUPPORTED[provider]] = config_dir
    completed = subprocess.run(
        [str(collector), *sys.argv[1:]],
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    if completed.returncode != 0:
        if completed.stderr:
            print(completed.stderr.rstrip(), file=sys.stderr)
        return completed.returncode

    try:
        record = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        return fail(f"base collector returned invalid JSON for {account_id}: {exc}")
    if not isinstance(record, dict):
        return fail(f"base collector returned a non-object for {account_id}")

    record["id"] = account_id
    record["name"] = str(account.get("name") or account_id)
    record["shortName"] = str(account.get("shortName") or record["name"])
    record["accountAlias"] = str(account.get("alias") or account_id)
    record["providerFamily"] = provider
    login_hint = str(account.get("loginHint") or "").strip()
    if login_hint and record.get("ready") is not True:
        record["authHelpText"] = login_hint

    json.dump(record, sys.stdout, separators=(",", ":"), ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

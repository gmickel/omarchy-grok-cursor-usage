#!/usr/bin/env python3
"""Adapt one Claude or Codex profile into an independent Omarchy record."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Any


SUPPORTED = {"claude": "CLAUDE_CONFIG_DIR", "codex": "CODEX_HOME"}
ACCOUNT_ID_CHARS = frozenset("abcdefghijklmnopqrstuvwxyz0123456789._-")
ACCOUNT_ID_START = frozenset("abcdefghijklmnopqrstuvwxyz0123456789")


def fail(message: str) -> int:
    print(f"account-profile-collector: {message}", file=sys.stderr)
    return 2


def expand(value: str, base_dir: Path) -> Path:
    path = Path(os.path.expandvars(os.path.expanduser(value)))
    return path if path.is_absolute() else (base_dir / path).resolve()


def load_accounts(config_path: Path) -> dict[str, dict[str, Any]]:
    if not config_path.exists():
        return {}
    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"cannot load {config_path}: {exc}") from exc
    if not isinstance(config, dict):
        raise ValueError(f"{config_path} must contain a JSON object")
    schema_version = config.get("schemaVersion", 1)
    if schema_version != 1:
        raise ValueError(f"unsupported schemaVersion in {config_path}: {schema_version!r}")
    accounts = config.get("accounts", {})
    if not isinstance(accounts, dict):
        raise ValueError(f"accounts in {config_path} must be a JSON object")

    result: dict[str, dict[str, Any]] = {}
    for account_id, account in accounts.items():
        if not isinstance(account_id, str) or not account_id:
            raise ValueError("account ids must be non-empty strings")
        if account_id == "update" or account_id[0] not in ACCOUNT_ID_START or any(
            char not in ACCOUNT_ID_CHARS for char in account_id
        ):
            raise ValueError(
                f"invalid account id {account_id!r}; use lowercase letters, digits, '.', '_', or '-'"
            )
        if not isinstance(account, dict):
            raise ValueError(f"account {account_id!r} must be a JSON object")
        provider = account.get("provider")
        if provider not in SUPPORTED:
            raise ValueError(f"unsupported provider for {account_id}: {provider!r}")
        config_dir = account.get("configDir")
        if not isinstance(config_dir, str) or not config_dir.strip():
            raise ValueError(f"missing configDir for {account_id}")
        result[account_id] = account
    return result


def resolve_collector(account: dict[str, Any], provider: str, config_path: Path) -> Path:
    explicit = str(account.get("collector") or "").strip()
    if explicit:
        candidates = [expand(explicit, config_path.parent)]
    else:
        config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
        omarchy_path = Path(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"))
        name = f"omarchy-agent-usage-{provider}"
        candidates = [
            config_home / "omarchy" / "agents" / name,
            omarchy_path / "bin" / name,
            Path("/usr/bin") / name,
        ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


def main() -> int:
    config_home = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    config_path = Path(
        os.environ.get(
            "OMARCHY_AGENT_ACCOUNTS_FILE",
            config_home / "omarchy" / "agents" / "accounts.json",
        )
    ).expanduser().resolve()
    try:
        accounts = load_accounts(config_path)
    except ValueError as exc:
        return fail(str(exc))

    if sys.argv[1:] == ["--list"]:
        json.dump(
            [{"id": account_id, "provider": account["provider"]} for account_id, account in accounts.items()],
            sys.stdout,
            separators=(",", ":"),
        )
        sys.stdout.write("\n")
        return 0

    if len(sys.argv) < 3 or sys.argv[1] != "--account":
        return fail("usage: account-profile-collector.py --list | --account <id> [collector flags]")
    account_id = sys.argv[2]
    try:
        account = accounts[account_id]
    except KeyError:
        return fail(f"account {account_id!r} is not configured in {config_path}")

    provider = str(account["provider"])

    config_dir = str(account.get("configDir", "")).strip()
    if not config_dir:
        return fail(f"missing configDir for {account_id}")
    config_dir_path = expand(config_dir, config_path.parent)
    if not config_dir_path.is_dir():
        return fail(f"configDir does not exist for {account_id}: {config_dir}")

    collector = resolve_collector(account, provider, config_path)
    if not collector.is_file() or not os.access(collector, os.X_OK):
        return fail(f"base collector not found for {account_id}: {collector}")

    env = os.environ.copy()
    env[SUPPORTED[provider]] = str(config_dir_path)
    cache_home = Path(env.get("XDG_CACHE_HOME", Path.home() / ".cache")).expanduser()
    env["XDG_CACHE_HOME"] = str(cache_home / "omarchy" / "agent-profile-cache" / account_id)
    try:
        completed = subprocess.run(
            [str(collector), *sys.argv[3:]],
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            check=False,
        )
    except OSError as exc:
        return fail(f"cannot run base collector for {account_id}: {exc}")
    if completed.returncode != 0:
        return completed.returncode

    try:
        record = json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        return fail(f"base collector returned invalid JSON for {account_id}: {exc}")
    if not isinstance(record, dict):
        return fail(f"base collector returned a non-object for {account_id}")

    record["id"] = account_id
    record["name"] = str(account.get("name") or account_id)
    record["providerFamily"] = provider
    login_hint = str(account.get("loginHint") or "").strip()
    if login_hint and record.get("ready") is not True:
        record["authHelpText"] = login_hint

    json.dump(record, sys.stdout, separators=(",", ":"), ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

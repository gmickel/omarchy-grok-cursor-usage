# Multiple account profiles

Claude Code and Codex support separate configuration directories. The account
profile adapter turns each directory into an independent usage record, so the
panel can show several subscriptions at once.

## Configure accounts

Copy the installed example:

```bash
cp ~/.config/omarchy/agents/accounts.example.json \
  ~/.config/omarchy/agents/accounts.json
```

Then edit `accounts.json`:

```json
{
  "schemaVersion": 1,
  "accounts": {
    "claude-personal": {
      "provider": "claude",
      "name": "Claude personal",
      "configDir": "~/.claude",
      "loginHint": "Run Claude Code with this profile, then use /login."
    },
    "claude-work": {
      "provider": "claude",
      "name": "Claude work",
      "configDir": "~/.claude-work"
    },
    "codex-work": {
      "provider": "codex",
      "name": "Codex work",
      "configDir": "~/.codex-work"
    }
  }
}
```

Run a refresh:

```bash
~/.config/omarchy/agents/run-usage-update --force
```

The next panel refresh discovers the generated records automatically.

## Schema

The root object accepts:

| Field | Required | Meaning |
|---|---:|---|
| `schemaVersion` | no | Configuration schema. Omitted means version 1. |
| `accounts` | yes | Object keyed by the panel record id. |

Each account accepts:

| Field | Required | Meaning |
|---|---:|---|
| `provider` | yes | `claude` or `codex`. |
| `name` | no | Human-readable panel label. Defaults to the account id. |
| `configDir` | yes | Claude `CLAUDE_CONFIG_DIR` or Codex `CODEX_HOME`. |
| `loginHint` | no | Authentication guidance shown when the collector is not ready. |
| `collector` | no | Explicit base collector path. Normally omit this. |

Account ids start with a lowercase letter or digit, then use lowercase
letters, digits, `.`, `_`, and `-`. `update` is reserved. The id becomes both
the JSON record id and its filename under
`~/.local/state/omarchy/agents/usage/`.

`~`, environment variables, and absolute paths are supported. Relative
`configDir` and `collector` values resolve from the directory containing
`accounts.json`, not from the shell or Quickshell working directory.

Set `OMARCHY_AGENT_ACCOUNTS_FILE` to use another configuration file.

## Collector resolution

Unless an account sets `collector`, the adapter selects the first executable
collector from:

1. `$XDG_CONFIG_HOME/omarchy/agents/omarchy-agent-usage-<provider>`
2. `${OMARCHY_PATH:-/usr/share/omarchy}/bin/omarchy-agent-usage-<provider>`
3. `/usr/bin/omarchy-agent-usage-<provider>`

This preserves user overrides, then follows Omarchy's installation path, with
`/usr/bin` as a compatibility fallback.

## Update behavior

`run-usage-update` discovers configured accounts before ordinary user
collectors. It supports the same selection grammar for both:

```bash
run-usage-update --force
run-usage-update --limits-only
run-usage-update claude-work
run-usage-update --except claude-personal
```

Unknown options fail instead of silently skipping every collector. If a
configured account id matches a user collector filename, the explicit account
configuration wins. Configuring one or more accounts for a provider suppresses
the packaged aggregate card for that provider. Include the default profile in
`accounts.json` if you still want it displayed.

Each account receives a separate `XDG_CACHE_HOME` below
`~/.cache/omarchy/agent-profile-cache/<account-id>/`. This matters for Claude:
the packaged collector otherwise caches its most recent limits in one shared
file for several seconds, allowing sequential profiles to show the wrong
subscription's quota.

## Local-statistics limitation

Rate limits, plan labels, and login state are profile-specific. Native Claude
and Codex transcript directories are also profile-specific.

The packaged collectors additionally merge machine-global Pi/OMP and OpenCode
sessions. Those sources do not identify which Claude or Codex subscription was
used, so their token and prompt totals may appear in more than one account
record. Do not sum local-statistics totals across profile cards. This does not
affect rate-limit percentages or reset times.

## Security boundary

`accounts.json` contains labels and local paths only. Do not add tokens,
cookies, OAuth payloads, session files, or copied credential data. The adapter
passes the selected profile directory to the existing collector, which reads
that profile's machine-local login in place.

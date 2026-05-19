# plugin-test-container

Clean throwaway container for testing Claude Code plugins from an operator's perspective — no prior state, no host contamination.

## Why this exists

Plugin installation needs to be tested from a fresh, empty environment to catch assumptions about pre-installed state, existing auth, or host-side configuration. This image gives you that environment in one `docker run`.

It is intentionally generic — it knows nothing about any specific plugin. Build the image once, run it per test.

## What's included (base)

- Ubuntu Noble (24.04)
- Claude Code via the native installer, at `/home/tester/.local/bin/claude`. Version is whatever the installer pulls at image build time — rebuild to refresh.
- `bun` at `/home/tester/.bun/bin/bun`. PATH is set in both `.bashrc` (interactive shells) and the Dockerfile `ENV` so Claude-spawned MCP subprocesses inherit it too.
- `git`, `curl`, `jq`, `unzip`
- Non-root user `tester`

Image size: ~506MB.

> **Why `tester` and not `operator`?** Ubuntu Noble ships with a pre-existing system `operator` group, so `useradd operator` fails with exit 9. `tester` is the workaround. Don't rename without checking host-side groups.

## What's NOT included

- Any plugin (operator installs via `/plugin` after launching `claude`)
- Auth (operator authenticates on first `claude` launch — `~/.claude/` is empty by design)
- Host bind mounts (closed-world environment by design)
- `d2`, or any other plugin-specific binary — those live in variants (see below)

## Two ways to run it

### Throwaway (one-shot test)

```bash
docker run -it --rm plugin-test-container
```

Container disappears the instant you exit. Use this for "does the plugin install cleanly" checks.

### Persistent (iteration)

```bash
docker run -d --name plugin-test-live plugin-test-container tail -f /dev/null
docker exec -it plugin-test-live bash
```

Use this when you want to attach, run things, detach, come back. The `tail -f /dev/null` keeps the container alive with no work. Teardown explicitly when done:

```bash
docker stop plugin-test-live && docker rm plugin-test-live
```

## Workflow

1. Build the image (once, or whenever you want to refresh Claude Code)
2. Spin up the container (throwaway or persistent)
3. Launch `claude`, authenticate
4. `/plugin marketplace add <repo>`
5. `/plugin install <plugin>@<marketplace>`
6. Exercise the plugin; capture findings
7. Exit / teardown → state evaporates

## Reaching plugin web servers from the host

OrbStack assigns every container an auto-domain at `<container-name>.orb.local`, reachable from the host on **any port** the container listens on. No `-p` flags needed — as long as the plugin's server binds to a non-loopback interface inside the container.

If the container is named `plugin-test-live` and the plugin opens a server on `:54321`, open `http://plugin-test-live.orb.local:54321/` in your Mac browser.

### Gotcha: `127.0.0.1` binds are not reachable from the host

A plugin server bound to `127.0.0.1` inside the container is **invisible** from the host — including via `<name>.orb.local`. The container's loopback is its own, not the host's.

Two workarounds:

1. **Right fix (plugin side):** make the plugin's bind interface configurable, set it to `0.0.0.0` for container runs. This is what plugin authors should do.
2. **Patch fix (container side):** install `socat` and bridge from the container's bridge IP to the plugin's loopback port:
   ```bash
   docker exec -u root plugin-test-live apt-get install -y socat
   docker exec -d plugin-test-live bash -c \
     'CIP=$(hostname -i); socat TCP-LISTEN:<port>,fork,reuseaddr,bind=$CIP TCP:127.0.0.1:<port>'
   ```
   **Bind socat to the bridge IP**, not to `0.0.0.0` — on Linux, `0.0.0.0:<port>` conflicts with the plugin's existing `127.0.0.1:<port>` bind unless both set `SO_REUSEPORT` (Bun doesn't, and most servers don't). Using the bridge IP is a different interface, so no conflict.

### Gotcha: Claude Code userConfig is NOT injected as env vars (verified 2.1.144)

If a plugin's `userConfig` options need to reach the plugin's MCP subprocess, **env vars are not the mechanism**. Empirically verified by inspecting `/proc/<pid>/environ` of a running bun MCP server after `/plugin` config save + `/reload-plugins`: the saved options are present in `~/.claude/settings.json` under `pluginConfigs`, but the subprocess sees only:

- `CLAUDE_CODE_ENTRYPOINT`
- `CLAUDE_PLUGIN_DATA`
- `CLAUDE_PLUGIN_ROOT`
- `CLAUDE_PROJECT_DIR`

No `CLAUDE_PLUGIN_OPTION_*` of any form. Plugins that want their userConfig must read `~/.claude/settings.json` directly (HOME-relative), or use whatever MCP-side query mechanism Claude Code exposes (TBD as of 2.1.144).

This is the most common cause of "I saved my userConfig and `/reload-plugins`'d but my plugin still acts on defaults." `/reload-plugins` does respawn the MCP subprocess (verified via PID change) — the issue is that the new subprocess also receives no env vars.

## Runtime model

Plain OCI container on the host's container runtime. OrbStack is the recommended pairing on Mac (~200MB RAM idle, doesn't cook the laptop).

Docker Sandboxes (microVM, hypervisor-isolated) exist as a separate Docker product, but they require Docker Desktop 4.58+, inherit its 2–4GB always-on VM overhead, hardcode microVMs to 4GB, and don't meaningfully improve plugin-install testing over a regular container. Stay on OrbStack.

## Variants

Plugin-specific runtime dependencies live in variant Dockerfiles that build `FROM plugin-test-container`. The base stays minimal; each variant carries its own extras.

**Doctrine:** binaries needed by exactly one plugin go in a variant. Binaries needed by *most* MCP plugins (e.g. `bun`) go in the base. When in doubt, variant.

### `:visualize` — for testing nf-visualize

Adds `d2` (visualize's `assertD2Installed` hard requirement). The d2 installer needs `make`, so the variant pulls that in too.

```bash
docker build -t plugin-test-container:visualize -f Dockerfile.visualize .
docker run -it --rm plugin-test-container:visualize
```

Image size: ~619MB.

### Adding a new variant

1. Create `Dockerfile.<plugin>` with `FROM plugin-test-container:latest`
2. `USER root` → install what the plugin needs → `USER tester`
3. Tag the build with `:<plugin>` (e.g. `plugin-test-container:somecanvas`)
4. Document it above

Do not move plugin-specific binaries into the base Dockerfile. The base stays generic on purpose.

## Quick runbook

```bash
# Build everything
docker build -t plugin-test-container .
docker build -t plugin-test-container:visualize -f Dockerfile.visualize .

# Persistent test container
docker run -d --name plugin-test-live plugin-test-container:visualize tail -f /dev/null
docker exec -it plugin-test-live bash

# What's listening inside the container (no `ss` in base — use /proc/net/tcp)
docker exec plugin-test-live bash -c '
  while read line; do
    addr=$(echo "$line" | awk "{print \$2}"); state=$(echo "$line" | awk "{print \$4}")
    [ "$state" = "0A" ] || continue
    hex_port="${addr##*:}"; port=$((16#$hex_port))
    hex_ip="${addr%:*}"
    echo "$hex_ip : $port  (00000000=0.0.0.0, 0100007F=127.0.0.1)"
  done < <(tail -n +2 /proc/net/tcp)
'

# Teardown
docker stop plugin-test-live && docker rm plugin-test-live
```

# plugin-test-container

Clean throwaway container for testing Claude Code plugins from an operator's perspective — no prior state, no host contamination.

## Why this exists

Plugin installation needs to be tested from a fresh, empty environment to catch assumptions about pre-installed state, existing auth, or host-side configuration. This image gives you that environment in one `docker run`.

It is intentionally generic — it knows nothing about any specific plugin. Build the image once, run it per test.

## What's included

- Ubuntu Noble (24.04) base
- Claude Code (pre-installed via the native installer, PATH configured)
- `bun` (common runtime for MCP-server plugins; on PATH for both interactive shells and Claude-spawned subprocesses)
- `git`, `curl`, `jq`
- Non-root `tester` user

## What's NOT included

- Any plugin (operator installs via `/plugin` after launching `claude`)
- Auth (operator authenticates on first `claude` launch)
- Host bind mounts (the image is a closed-world environment by design)

## Usage

**Build:**
```bash
docker build -t plugin-test-container .
```

**Run:**
```bash
docker run -it --rm plugin-test-container
```

The `--rm` flag throws the container away on exit — that's the point. Fresh state every time.

## Workflow

1. Build the image (once, or whenever you want to refresh the base)
2. Run the container
3. Launch `claude`, authenticate
4. Run `/plugin marketplace add <repo>` to add the marketplace under test
5. Run `/plugin install <plugin>@<marketplace>` to install the plugin under test
6. Exercise the plugin; capture anything noteworthy
7. Exit → container is destroyed → next test starts from scratch

## Runtime model

This is a plain OCI container running on whatever container runtime the operator uses (OrbStack on Mac is the recommended pairing — it idles at ~200MB RAM and doesn't cook the laptop).

For full microVM-grade isolation, Docker Sandboxes exist but currently require Docker Desktop on macOS and don't add value over a regular container for plugin installation testing.

## Variants

Plugin-specific runtime dependencies live in variant Dockerfiles that build `FROM plugin-test-container`. Keep the base minimal; let each variant carry its own extras.

### `:visualize` — for testing nf-visualize

Adds `d2` (hard dependency of the visualize plugin). Build:

```bash
docker build -t plugin-test-container:visualize -f Dockerfile.visualize .
```

Run:

```bash
docker run -it --rm plugin-test-container:visualize
```

### Adding a new variant

1. Create `Dockerfile.<plugin>` in this repo with `FROM plugin-test-container:latest`
2. Switch to `USER root`, install whatever the plugin needs, switch back to `USER tester`
3. Tag the build with `:<plugin>` (e.g. `plugin-test-container:somecanvas`)
4. Document it under "Variants" above

Do not move plugin-specific binaries (d2, language toolchains, plugin-only services) into the base Dockerfile. The base stays generic.

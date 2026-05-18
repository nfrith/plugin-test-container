# plugin-test-container

Clean throwaway container for testing Claude Code plugins from an operator's perspective — no prior state, no host contamination.

## Why this exists

Plugin installation needs to be tested from a fresh, empty environment to catch assumptions about pre-installed state, existing auth, or host-side configuration. This image gives you that environment in one `docker run`.

It is intentionally generic — it knows nothing about any specific plugin. Build the image once, run it per test.

## What's included

- Ubuntu Noble (24.04) base
- Claude Code (pre-installed via the native installer, PATH configured)
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

If a specific plugin needs a heavier base (Node, Python, etc.), fork this image and add the toolchain on top of the existing layers. Do not bake plugin-specific tooling into this image — it's meant to stay minimal.

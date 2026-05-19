FROM ubuntu:noble

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash curl git ca-certificates jq unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Non-root user for running claude. Named `tester` to avoid colliding
# with Ubuntu Noble's pre-existing system `operator` group.
RUN useradd -m -s /bin/bash tester

USER tester

# Claude Code via native installer (Anthropic's recommended path since
# Oct 2025 — replaces the deprecated `npm install -g` route).
RUN curl -fsSL https://claude.ai/install.sh | bash

# bun — common runtime for MCP-server plugins. Subprocesses spawned by
# Claude Code inherit PATH from ENV below, not .bashrc, so we set both.
RUN curl -fsSL https://bun.sh/install | bash

ENV PATH="/home/tester/.local/bin:/home/tester/.bun/bin:${PATH}"

WORKDIR /home/tester
CMD ["bash", "-l"]

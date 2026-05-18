FROM ubuntu:noble

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash curl git ca-certificates jq && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Non-root user for running claude. Named `tester` to avoid colliding
# with Ubuntu Noble's pre-existing system `operator` group.
RUN useradd -m -s /bin/bash tester

# Install Claude Code via native installer (Anthropic's recommended path
# since Oct 2025 — replaces the deprecated `npm install -g` route).
USER tester
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

WORKDIR /home/tester
CMD ["bash", "-l"]

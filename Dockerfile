FROM ubuntu:noble

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash curl git ca-certificates jq && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Non-root operator user
RUN useradd -m -s /bin/bash operator

# Install Claude Code via native installer (Anthropic's recommended path
# since Oct 2025 — replaces the deprecated `npm install -g` route).
USER operator
RUN curl -fsSL https://claude.ai/install.sh | bash && \
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

WORKDIR /home/operator
CMD ["bash", "-l"]

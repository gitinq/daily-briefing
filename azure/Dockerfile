FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code

# Non-root user required: --dangerously-skip-permissions is blocked for root
RUN useradd -m -s /bin/bash briefing

COPY azure/entrypoint.sh /scripts/entrypoint.sh
RUN chmod +x /scripts/entrypoint.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]

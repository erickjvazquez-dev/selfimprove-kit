FROM mcr.microsoft.com/playwright/python:v1.44.0-jammy

WORKDIR /workspace

# System deps
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git jq \
    && rm -rf /var/lib/apt/lists/*

# Python deps
COPY docker/requirements.txt docker/requirements.txt
RUN pip install --no-cache-dir -r docker/requirements.txt

# Install Playwright browsers
RUN playwright install chromium

# Claude Code CLI (native binary — base image has no Node). Lets tests/run.sh
# run `claude plugin validate` instead of skipping, and enables interactive
# sessions via `docker compose run framework` (inject ANTHROPIC_API_KEY at runtime).
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/root/.local/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1

# Full framework: commands, agents, hooks, core, scaffold, scripts, tests,
# setup.sh, plugin manifests. .dockerignore keeps .git and .ccf (secrets) out —
# runtime config is injected via env_file / -e, never baked into a layer.
COPY . .

CMD ["python3", "scripts/health_check.py"]

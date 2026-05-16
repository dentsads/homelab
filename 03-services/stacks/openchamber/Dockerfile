# syntax=docker/dockerfile:1

# Stage 1: Clone the openchamber repo at a pinned tag
FROM alpine/git AS repo
WORKDIR /src
RUN git clone --depth 1 --branch v1.10.4 https://github.com/openchamber/openchamber.git .

# Stage 2: Patch the lockfile (upstream bun.lock is out of date with package.json)
FROM oven/bun:1 AS deps
WORKDIR /app
COPY --from=repo /src/package.json /src/bun.lock ./
COPY --from=repo /src/packages/ui/package.json ./packages/ui/
COPY --from=repo /src/packages/web/package.json ./packages/web/
COPY --from=repo /src/packages/desktop/package.json ./packages/desktop/
COPY --from=repo /src/packages/vscode/package.json ./packages/vscode/
# NOTE: --frozen-lockfile removed because upstream lockfile is stale
RUN bun install --ignore-scripts

# Stage 3: Build the web app
FROM deps AS builder
WORKDIR /app
COPY --from=repo /src .
RUN bun run build:web

# Stage 4: Runtime
FROM oven/bun:1 AS runtime
WORKDIR /home/openchamber

RUN apt-get update && apt-get install -y --no-install-recommends \
  bash \
  ca-certificates \
  git \
  less \
  nodejs \
  npm \
  openssh-client \
  python3 \
  && rm -rf /var/lib/apt/lists/*

RUN userdel bun \
  && groupadd -g 1000 openchamber \
  && useradd -u 1000 -g 1000 -m -s /bin/bash openchamber \
  && mkdir -p /home/openchamber/.config/openchamber /home/openchamber/.local/share/opencode /home/openchamber/.local/state/opencode /home/openchamber/.config/opencode /home/openchamber/.ssh /home/openchamber/workspaces \
  && chown -R openchamber:openchamber /home/openchamber

USER openchamber

ENV NPM_CONFIG_PREFIX=/home/openchamber/.npm-global
ENV PATH=${NPM_CONFIG_PREFIX}/bin:${PATH}

RUN npm config set prefix /home/openchamber/.npm-global && mkdir -p /home/openchamber/.npm-global && \
  mkdir -p /home/openchamber/.local /home/openchamber/.config /home/openchamber/.ssh && \
  npm install -g opencode-ai

COPY --from=cloudflare/cloudflared@sha256:6b599ca3e974349ead3286d178da61d291961182ec3fe9c505e1dd02c8ac31b0 /usr/local/bin/cloudflared /usr/local/bin/cloudflared

ENV NODE_ENV=production

COPY --from=repo /src/scripts/docker-entrypoint.sh /home/openchamber/openchamber-entrypoint.sh

COPY --from=deps /app/node_modules ./node_modules
COPY --from=deps /app/packages/web/node_modules ./packages/web/node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/packages/web/package.json ./packages/web/package.json
COPY --from=builder /app/packages/web/bin ./packages/web/bin
COPY --from=builder /app/packages/web/server ./packages/web/server
COPY --from=builder /app/packages/web/dist ./packages/web/dist

# Fix ownership after all COPY commands (files from builder stages are root-owned)
USER root
RUN chown -R openchamber:openchamber /home/openchamber
USER openchamber

EXPOSE 3000

ENTRYPOINT ["sh", "/home/openchamber/openchamber-entrypoint.sh"]

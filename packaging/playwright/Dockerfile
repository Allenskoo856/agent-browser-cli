FROM rust:1.93-bookworm AS rust-builder

WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY assets ./assets
RUN cargo build --release --locked --bin agent-browser-cli

FROM mcr.microsoft.com/playwright:v1.62.0-noble

WORKDIR /opt/agent-browser-cli
COPY package.json package-lock.json ./
COPY npm ./npm
COPY assets ./assets
COPY runtime ./runtime
COPY skills ./skills
COPY docs ./docs
COPY README.md README_EN.md LICENSE ./
RUN npm ci --omit=optional --ignore-scripts \
    && npm cache clean --force

COPY --from=rust-builder /src/target/release/agent-browser-cli ./bin/agent-browser-cli

ENV AGENT_BROWSER_CLI_BIN=/opt/agent-browser-cli/bin/agent-browser-cli
ENV AGENT_BROWSER_PLAYWRIGHT_RUNTIME=/opt/agent-browser-cli/runtime/playwright/src/runtime.mjs
ENV AGENT_BROWSER_PLAYWRIGHT_NODE=/usr/bin/node
ENV HOME=/home/pwuser

RUN mkdir -p /home/pwuser/.agent-browser-cli /data/artifacts \
    && chown -R pwuser:pwuser /home/pwuser /data

USER pwuser
ENTRYPOINT ["node", "npm/bin/agent-browser-cli.js"]
CMD ["pw", "doctor"]

FROM node:23.3.0-slim AS builder

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ffmpeg \
    g++ \
    git \
    make \
    python3 \
    unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g turbo@2.3.3

RUN ln -s /usr/bin/python3 /usr/bin/python

COPY package.json turbo.json tsconfig.json lerna.json renovate.json .npmrc ./
COPY scripts ./scripts
COPY packages ./packages

# Install ca-certificates for SSL verification and clone the .cursor submodule
RUN apt-get update && \
    apt-get install -y ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p .cursor && \
    (git clone https://github.com/elizaOS/.cursor.git .cursor || \
    echo "Warning: Failed to clone .cursor repository, continuing without it")

# Modify the init-submodules script to handle missing .git directory
RUN sed -i 's/git submodule update --init --recursive/if [ -d ".git" ]; then git submodule update --init --recursive; else echo "No .git directory found, skipping submodule initialization"; fi/' scripts/init-submodules.sh

# Set environment variables for build compatibility
ENV TURBO_TELEMETRY_DISABLED=1
ENV CI=true
ENV NODE_ENV=development

# Install dependencies using npm instead of bun to avoid binary compatibility issues
RUN npm config set ignore-scripts true && \
    npm install --legacy-peer-deps && \
    npm config set ignore-scripts false

# Clear any cached builds and force a clean build
RUN npm run clean || true

# Use npm for the build process instead of bun
RUN npm run build

FROM node:23.3.0-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ffmpeg \
    git \
    python3 \
    unzip && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g turbo@2.3.3

COPY --from=builder /app/package.json ./
COPY --from=builder /app/turbo.json ./
COPY --from=builder /app/tsconfig.json ./
COPY --from=builder /app/lerna.json ./
COPY --from=builder /app/renovate.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/packages ./packages
COPY --from=builder /app/scripts ./scripts

ENV NODE_ENV=production

EXPOSE 3000
EXPOSE 50000-50100/udp

CMD ["npm", "run", "start"]

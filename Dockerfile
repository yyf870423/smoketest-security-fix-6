# ============================================================
# Stage 1: builder
# Install dependencies (reserved for future npm deps)
# ============================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files first to leverage build cache
COPY package.json ./

# This project has no external dependencies, but we run install
# so the pattern is ready when dependencies are added later.
RUN npm install --omit=dev 2>/dev/null || true

# Copy source code
COPY src/ ./src/

# ============================================================
# Stage 2: production
# Minimal runtime image
# ============================================================
FROM node:20-alpine AS production

# Install wget for health check (alpine ships with it, but be explicit)
RUN apk add --no-cache wget

WORKDIR /app

# Use built-in non-root 'node' user (uid=1000)
RUN chown -R node:node /app
USER node

# Copy only what is needed from builder
COPY --from=builder --chown=node:node /app/package.json ./
COPY --from=builder --chown=node:node /app/src ./src/

# Expose default port
EXPOSE 3000

# Health check: verify /count endpoint responds
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/count || exit 1

# Start application
CMD ["node", "src/index.js"]

# Build stage
FROM node:24-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./
COPY tsconfig.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY src ./src
COPY server.ts ./

# Build TypeScript
RUN npm run build

# Prune dev dependencies
RUN npm prune --omit=dev

# Production stage
FROM node:24-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S -D -H -u 1001 -h /app -s /sbin/nologin -G nodejs -g nodejs apiuser

# Copy built application
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

# Set ownership
RUN chown -R apiuser:nodejs /app

USER apiuser

EXPOSE 3000

CMD ["node", "dist/server.js"]

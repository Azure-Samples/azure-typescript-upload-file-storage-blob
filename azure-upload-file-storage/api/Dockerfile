# Build stage
FROM node:24-alpine AS builder

WORKDIR /app

# Copy package files from api directory
COPY azure-upload-file-storage/api/package*.json ./
COPY azure-upload-file-storage/api/tsconfig.json ./

# Install dependencies
RUN --mount=type=cache,target=/root/.npm \
    npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm install

# Copy source code from api directory
COPY azure-upload-file-storage/api/ .

# Build TypeScript
RUN npm run build

# Prune dev dependencies
RUN npm prune --omit=dev


#----------------------------------------------------------------
# Production stage
FROM node:24-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Copy built application
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist

EXPOSE 3000

CMD ["node", "dist/server.js"]

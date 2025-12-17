# Build stage
FROM node:24-alpine AS builder

WORKDIR /app

# Copy package files from app directory
COPY package*.json ./

# Install dependencies
RUN --mount=type=cache,target=/root/.npm \
    npm config set fetch-retries 5 && \
    npm config set fetch-retry-mintimeout 20000 && \
    npm config set fetch-retry-maxtimeout 120000 && \
    npm install

# Copy source code from app directory
COPY . .

# Build the React app
RUN npm run build

# Prune dev dependencies
RUN npm prune --omit=dev
#-----------------------------------------------------------------
# Production stage with nginx
FROM node:24-alpine

# Install nginx
RUN apk add --no-cache nginx

# Copy custom nginx config from app directory
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN echo "app"

# Copy built static files
COPY --from=builder /app/dist /usr/share/nginx/html

# Create required directories and set permissions for nginx user
RUN mkdir -p /var/cache/nginx /var/log/nginx /var/run && \
    chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 8080

# HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
#   CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

CMD ["nginx", "-g", "daemon off;"]

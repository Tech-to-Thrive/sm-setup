FROM node:18-alpine AS frontend-builder

# Build React frontend
WORKDIR /frontend

# Copy package files first for better caching
COPY frontend/package*.json ./
RUN npm ci --legacy-peer-deps

# Copy shared directory for validators
COPY shared/ ../shared/

# Copy only necessary frontend files
COPY frontend/index.html ./
COPY frontend/vite.config.js ./
COPY frontend/public/ ./public/
COPY frontend/src/ ./src/

# Build the frontend
RUN npm run build

# Production stage
FROM node:18-alpine

# Install required system dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    docker-cli \
    docker-compose

WORKDIR /app

# Copy backend package files and install dependencies
COPY backend/package*.json ./
RUN npm ci --only=production && \
    npm cache clean --force

# Copy shared directory for validators
COPY shared/ ./shared/

# Copy only necessary backend files (excluding test files, tools, etc.)
COPY backend/*.js ./
COPY backend/middleware/ ./middleware/
COPY backend/utils/ ./utils/
COPY backend/welcome.html ./

# Copy React build from frontend stage
COPY --from=frontend-builder /frontend/dist ./frontend/dist

# Create a non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

# Create necessary directories and set permissions
RUN mkdir -p /app/data /project && \
    chown -R nodejs:nodejs /app && \
    chown -R nodejs:nodejs /project

# Create a startup script
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'cd /app' >> /start.sh && \
    echo 'node server-integrated.js' >> /start.sh && \
    chmod +x /start.sh

USER nodejs

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

CMD ["/start.sh"]
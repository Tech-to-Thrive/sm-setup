FROM node:18-alpine AS frontend-builder

# Build React frontend
WORKDIR /frontend
COPY frontend/package*.json ./
RUN npm ci --legacy-peer-deps
# Copy shared directory for validators
COPY shared/ ../shared/
COPY frontend/ ./
RUN npm run build

FROM node:18-alpine

# Install required system dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    docker-cli \
    docker-compose

WORKDIR /app

# Copy backend package files and install
COPY backend/package*.json ./
RUN npm ci --only=production

# Copy shared directory for validators
COPY shared/ ./shared/

# Copy backend application files
COPY backend/ ./

# Copy React build from frontend stage
COPY --from=frontend-builder /frontend/dist ./frontend/dist

# Create a startup script
RUN echo '#!/bin/sh' > /start.sh && \
    echo 'cd /app' >> /start.sh && \
    echo 'node server-integrated.js' >> /start.sh && \
    chmod +x /start.sh

EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

CMD ["/start.sh"]
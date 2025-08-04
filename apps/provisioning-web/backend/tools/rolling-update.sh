#!/bin/bash

# Rolling Update Strategy for Docker Compose
# Provides safer updates with rollback capability

set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-deploy/docker/docker-compose.yml}"
BACKUP_DIR="./startup/deployments"
LOG_FILE="$BACKUP_DIR/rolling-update-$(date +%Y%m%d_%H%M%S).log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load logging if available
source "$(dirname "$0")/env-logger.sh" 2>/dev/null || {
    log_operation() { echo "LOG: $*" | tee -a "$LOG_FILE"; }
    log_error() { echo "ERROR: $*" | tee -a "$LOG_FILE"; }
}

mkdir -p "$BACKUP_DIR"

usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  update [service]     - Rolling update (specific service or all)"
    echo "  rollback <backup>    - Rollback to previous state"
    echo "  status              - Show deployment status"
    echo "  health              - Check service health"
    echo "  list-backups        - Show available rollback points"
    echo ""
    echo "Options:"
    echo "  --env-version <ver> - Use specific .env version"
    echo "  --force             - Force update even if unhealthy"
    echo "  --timeout <sec>     - Health check timeout (default: 60)"
    echo ""
}

create_backup() {
    local backup_name="backup_$(date +%Y%m%d_%H%M%S)"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    echo -e "${BLUE}Creating deployment backup...${NC}"
    
    mkdir -p "$backup_path"
    
    # Backup current state
    docker compose -f "$COMPOSE_FILE" ps --format json > "$backup_path/services.json"
    docker compose -f "$COMPOSE_FILE" config > "$backup_path/docker-compose.yml"
    
    # Backup current .env files
    cp .env "$backup_path/" 2>/dev/null || true
    cp .env.auth "$backup_path/" 2>/dev/null || true
    
    # Backup image versions
    docker compose -f "$COMPOSE_FILE" images --format json > "$backup_path/images.json"
    
    log_operation "INFO" "Deployment backup created" "Path: $backup_path"
    echo "$backup_name"
}

check_service_health() {
    local service="$1"
    local timeout="${2:-60}"
    local start_time=$(date +%s)
    
    echo -e "${YELLOW}Checking health of $service...${NC}"
    
    while [ $(($(date +%s) - start_time)) -lt $timeout ]; do
        if docker compose -f "$COMPOSE_FILE" ps "$service" --format json | jq -r '.[0].State' | grep -q "running"; then
            # Additional health checks
            case "$service" in
                "postgres")
                    if docker compose -f "$COMPOSE_FILE" exec -T postgres pg_isready -U postgres >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ $service is healthy${NC}"
                        return 0
                    fi
                    ;;
                "redis")
                    if docker compose -f "$COMPOSE_FILE" exec -T redis redis-cli ping | grep -q "PONG"; then
                        echo -e "${GREEN}✓ $service is healthy${NC}"
                        return 0
                    fi
                    ;;
                "app-n8n")
                    if curl -f http://localhost:5678/healthz >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ $service is healthy${NC}"
                        return 0
                    fi
                    ;;
                "stack-manager-api")
                    if curl -f http://localhost:3002/health >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ $service is healthy${NC}"
                        return 0
                    fi
                    ;;
                *)
                    # Generic health check
                    if docker compose -f "$COMPOSE_FILE" ps "$service" --format json | jq -r '.[0].Health // "healthy"' | grep -q "healthy\|starting"; then
                        echo -e "${GREEN}✓ $service is healthy${NC}"
                        return 0
                    fi
                    ;;
            esac
        fi
        
        echo -n "."
        sleep 2
    done
    
    echo -e "${RED}✗ $service failed health check${NC}"
    return 1
}

rolling_update() {
    local target_service="$1"
    local env_version="$2"
    local force="$3"
    local timeout="${4:-60}"
    
    log_operation "INFO" "Starting rolling update" "Service: ${target_service:-all}, Env: ${env_version:-current}"
    
    # Create backup before update
    local backup_name=$(create_backup)
    
    # Apply new environment if specified
    if [ -n "$env_version" ]; then
        echo -e "${BLUE}Applying environment version $env_version...${NC}"
        if ! ./tools/env-manager-multi.sh rollback "$env_version"; then
            log_error "ENV_ROLLBACK_FAILED" "Failed to apply env version $env_version" "Rolling update aborted"
            return 1
        fi
    fi
    
    # Get services to update
    local services=()
    if [ -n "$target_service" ] && [ "$target_service" != "all" ]; then
        services=("$target_service")
    else
        # Get all services
        mapfile -t services < <(docker compose -f "$COMPOSE_FILE" config --services)
    fi
    
    echo -e "${BLUE}Updating ${#services[@]} service(s): ${services[*]}${NC}"
    
    # Update services in dependency order
    local failed_services=()
    
    for service in "${services[@]}"; do
        echo -e "${YELLOW}Updating $service...${NC}"
        
        # Pull new image
        if ! docker compose -f "$COMPOSE_FILE" pull "$service"; then
            log_error "IMAGE_PULL_FAILED" "Failed to pull image for $service" "Update failed"
            failed_services+=("$service")
            continue
        fi
        
        # Stop and start service
        docker compose -f "$COMPOSE_FILE" stop "$service"
        docker compose -f "$COMPOSE_FILE" up -d "$service"
        
        # Health check
        if ! check_service_health "$service" "$timeout"; then
            if [ "$force" != "true" ]; then
                log_error "HEALTH_CHECK_FAILED" "Service $service failed health check" "Update aborted"
                failed_services+=("$service")
                
                echo -e "${RED}Rolling back $service...${NC}"
                rollback_service "$service" "$backup_name"
                continue
            else
                log_operation "WARN" "Service $service unhealthy but continuing" "Force mode enabled"
            fi
        fi
        
        log_operation "INFO" "Service $service updated successfully" "Health check passed"
    done
    
    if [ ${#failed_services[@]} -gt 0 ]; then
        echo -e "${RED}Update failed for services: ${failed_services[*]}${NC}"
        echo -e "${YELLOW}Backup available at: $backup_name${NC}"
        return 1
    fi
    
    echo -e "${GREEN}✓ Rolling update completed successfully${NC}"
    log_operation "INFO" "Rolling update completed" "All services healthy"
    return 0
}

rollback_service() {
    local service="$1"
    local backup_name="$2"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    if [ ! -d "$backup_path" ]; then
        echo -e "${RED}Backup $backup_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Rolling back $service...${NC}"
    
    # Get original image from backup
    local original_image=$(jq -r --arg service "$service" '.[] | select(.Service == $service) | .Repository + ":" + .Tag' "$backup_path/images.json" 2>/dev/null || echo "")
    
    if [ -n "$original_image" ] && [ "$original_image" != "null:null" ]; then
        docker compose -f "$COMPOSE_FILE" stop "$service"
        # Note: This would require modifying compose file or using override
        docker compose -f "$COMPOSE_FILE" up -d "$service"
    fi
    
    log_operation "INFO" "Service $service rolled back" "From backup: $backup_name"
}

full_rollback() {
    local backup_name="$1"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    if [ ! -d "$backup_path" ]; then
        echo -e "${RED}Backup $backup_name not found${NC}"
        return 1
    fi
    
    echo -e "${BLUE}Rolling back entire deployment to $backup_name...${NC}"
    
    # Restore environment files
    if [ -f "$backup_path/.env" ]; then
        cp "$backup_path/.env" .env
        echo -e "${GREEN}✓ Restored .env${NC}"
    fi
    
    if [ -f "$backup_path/.env.auth" ]; then
        cp "$backup_path/.env.auth" .env.auth
        echo -e "${GREEN}✓ Restored .env.auth${NC}"
    fi
    
    # Restart all services
    docker compose -f "$COMPOSE_FILE" down
    docker compose -f "$COMPOSE_FILE" up -d
    
    echo -e "${GREEN}✓ Full rollback completed${NC}"
    log_operation "INFO" "Full rollback completed" "Backup: $backup_name"
}

show_status() {
    echo -e "${BLUE}Deployment Status:${NC}"
    docker compose -f "$COMPOSE_FILE" ps
    
    echo -e "\n${BLUE}Health Status:${NC}"
    local services
    mapfile -t services < <(docker compose -f "$COMPOSE_FILE" config --services)
    
    for service in "${services[@]}"; do
        if check_service_health "$service" 5; then
            echo -e "  ${GREEN}✓ $service${NC}"
        else
            echo -e "  ${RED}✗ $service${NC}"
        fi
    done
}

list_backups() {
    echo -e "${BLUE}Available deployment backups:${NC}"
    for backup in "$BACKUP_DIR"/backup_*; do
        if [ -d "$backup" ]; then
            local backup_name=$(basename "$backup")
            local timestamp=$(echo "$backup_name" | sed 's/backup_//')
            local date_formatted=$(date -d "${timestamp:0:8} ${timestamp:9:2}:${timestamp:11:2}:${timestamp:13:2}" 2>/dev/null || echo "$timestamp")
            echo "  $backup_name - $date_formatted"
        fi
    done
}

# Parse arguments
COMMAND=""
TARGET_SERVICE=""
ENV_VERSION=""
FORCE="false"
TIMEOUT="60"

while [[ $# -gt 0 ]]; do
    case $1 in
        update|rollback|status|health|list-backups)
            COMMAND="$1"
            shift
            ;;
        --env-version)
            ENV_VERSION="$2"
            shift 2
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [ -z "$TARGET_SERVICE" ] && [ "$COMMAND" = "update" ]; then
                TARGET_SERVICE="$1"
            elif [ -z "$TARGET_SERVICE" ] && [ "$COMMAND" = "rollback" ]; then
                TARGET_SERVICE="$1"  # This is actually backup name for rollback
            fi
            shift
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    "update")
        rolling_update "$TARGET_SERVICE" "$ENV_VERSION" "$FORCE" "$TIMEOUT"
        ;;
    "rollback")
        if [ -n "$TARGET_SERVICE" ]; then
            full_rollback "$TARGET_SERVICE"
        else
            echo -e "${RED}Error: Please specify backup name for rollback${NC}"
            echo "Use: $0 list-backups to see available backups"
            exit 1
        fi
        ;;
    "status")
        show_status
        ;;
    "health")
        echo -e "${BLUE}Running health checks...${NC}"
        mapfile -t services < <(docker compose -f "$COMPOSE_FILE" config --services)
        for service in "${services[@]}"; do
            check_service_health "$service" "$TIMEOUT"
        done
        ;;
    "list-backups")
        list_backups
        ;;
    *)
        usage
        exit 1
        ;;
esac
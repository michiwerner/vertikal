#!/bin/bash

# E2E Image Builder Script
# This script builds the controller image for e2e testing

set -euo pipefail

# Source utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

# Configuration
CONTROLLER_IMAGE=${CONTROLLER_IMAGE:-"controller:latest"}
FORCE_REBUILD=${FORCE_REBUILD:-"false"}

show_help() {
    cat << EOF
Usage: $0 [options]

Options:
  --help, -h     Show this help message
  --force        Force rebuild even if image exists

Environment variables:
  CONTROLLER_IMAGE    Controller image tag (default: controller:latest)
  FORCE_REBUILD       Force rebuild (default: false)

Examples:
  $0                                    # Build image if not exists
  $0 --force                           # Force rebuild
  CONTROLLER_IMAGE=my:tag $0           # Build with custom tag
  FORCE_REBUILD=true $0                # Force rebuild via env var
EOF
}

check_image_needs_rebuild() {
    local image="$1"
    
    # If force rebuild is requested
    if [[ "$FORCE_REBUILD" == "true" ]]; then
        log "Force rebuild requested"
        return 0  # needs rebuild
    fi
    
    # Check if image exists
    if ! docker image inspect "$image" &> /dev/null; then
        log "Image $image does not exist locally"
        return 0  # needs rebuild
    fi
    
    # Get image creation time
    local image_time
    image_time=$(docker image inspect "$image" --format '{{.Created}}' 2>/dev/null || echo "")
    
    if [[ -z "$image_time" ]]; then
        log "Cannot determine image creation time"
        return 0  # needs rebuild
    fi
    
    # Convert image time to seconds since epoch
    local image_epoch
    image_epoch=$(date -d "$image_time" +%s 2>/dev/null || echo "0")
    
    # Find the most recent file modification in source directories
    local most_recent=0
    local source_dirs=("cmd" "api" "pkg" "go.mod" "go.sum" "Dockerfile")
    
    for dir in "${source_dirs[@]}"; do
        if [[ -e "$dir" ]]; then
            local dir_time
            dir_time=$(find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -1 || echo "0")
            dir_time=${dir_time%.*}  # Remove decimal part
            if [[ "$dir_time" -gt "$most_recent" ]]; then
                most_recent="$dir_time"
            fi
        fi
    done
    
    if [[ "$most_recent" -gt "$image_epoch" ]]; then
        log "Source code is newer than image (source: $(date -d "@$most_recent"), image: $(date -d "@$image_epoch"))"
        return 0  # needs rebuild
    fi
    
    log "Image $image is up to date"
    return 1  # no rebuild needed
}

build_image() {
    local image="$1"
    
    log "Building controller image: $image"
    
    # Ensure we're in the project root
    if [[ ! -f "Dockerfile" ]]; then
        error "Dockerfile not found. Make sure you're in the project root directory."
    fi
    
    # Get the absolute path to avoid issues with spaces in path
    local project_root
    project_root="$(pwd)"
    
    log "Project root: $project_root"
    log "Running: make docker-build IMG=\"$image\""
    
    # Use pushd/popd to handle paths with spaces correctly
    pushd "$project_root" > /dev/null || error "Failed to change to project root"
    
    # Build the image
    if make docker-build IMG="$image"; then
        log "Make command completed successfully"
    else
        popd > /dev/null
        error "Failed to build image with make"
    fi
    
    popd > /dev/null
    
    # Verify the image was built
    if docker image inspect "$image" &> /dev/null; then
        log "Image $image built successfully"
        
        # Show image info
        local image_size
        image_size=$(docker image inspect "$image" --format '{{.Size}}' | numfmt --to=iec)
        log "Image size: $image_size"
    else
        error "Failed to build image $image"
    fi
}

main() {
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --help|-h)
                show_help
                exit 0
                ;;
            --force)
                FORCE_REBUILD="true"
                shift
                ;;
            *)
                error "Unknown option: $1"
                ;;
        esac
    done
    
    log "Starting image build process..."
    log "Controller image: $CONTROLLER_IMAGE"
    log "Force rebuild: $FORCE_REBUILD"
    
    # Check if rebuild is needed
    if check_image_needs_rebuild "$CONTROLLER_IMAGE"; then
        build_image "$CONTROLLER_IMAGE"
    else
        log "Skipping build - image is up to date"
    fi
    
    log "Image build process completed"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

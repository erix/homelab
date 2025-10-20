#!/bin/bash

# Calibre-Web-Automated Book Ingest Helper
# This script helps you easily add books to your automated library

set -e

NAMESPACE="default"
CWA_POD_SELECTOR="app=calibre-web-automated"
INGEST_PATH="/cwa-book-ingest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  add <file>     Copy a book file to the ingest folder"
    echo "  status         Check CWA pod status and logs"
    echo "  logs           Show CWA logs (follow mode)"
    echo "  list           List files in ingest folder"
    echo "  clean          Remove processed files from ingest folder"
    echo "  help           Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 add ~/Downloads/book.epub"
    echo "  $0 add *.pdf"
    echo "  $0 status"
    echo "  $0 logs"
}

get_cwa_pod() {
    kubectl get pods -l "$CWA_POD_SELECTOR" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo ""
}

check_pod_ready() {
    local pod_name=$1
    if [ -z "$pod_name" ]; then
        echo -e "${RED}Error: Calibre-Web-Automated pod not found${NC}"
        echo "Make sure the deployment is running: kubectl get pods -l $CWA_POD_SELECTOR"
        exit 1
    fi
    
    local ready=$(kubectl get pod "$pod_name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    if [ "$ready" != "True" ]; then
        echo -e "${YELLOW}Warning: Pod $pod_name is not ready${NC}"
        kubectl get pod "$pod_name"
        echo ""
    fi
}

add_book() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: File '$file' does not exist${NC}"
        exit 1
    fi
    
    local pod_name=$(get_cwa_pod)
    check_pod_ready "$pod_name"
    
    local filename=$(basename "$file")
    
    echo -e "${BLUE}Adding book: $filename${NC}"
    echo "Copying to CWA ingest folder..."
    
    kubectl cp "$file" "$pod_name:$INGEST_PATH/$filename"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Book successfully added to ingest folder${NC}"
        echo "Book will be processed automatically. Check logs with: $0 logs"
    else
        echo -e "${RED}✗ Failed to copy book${NC}"
        exit 1
    fi
}

show_status() {
    echo -e "${BLUE}Calibre-Web-Automated Status${NC}"
    echo "================================"
    
    local pod_name=$(get_cwa_pod)
    if [ -z "$pod_name" ]; then
        echo -e "${RED}Pod not found${NC}"
        exit 1
    fi
    
    echo "Pod: $pod_name"
    kubectl get pod "$pod_name"
    echo ""
    
    echo -e "${BLUE}Recent logs:${NC}"
    kubectl logs "$pod_name" --tail=10
}

show_logs() {
    local pod_name=$(get_cwa_pod)
    check_pod_ready "$pod_name"
    
    echo -e "${BLUE}Following logs for $pod_name${NC}"
    echo "Press Ctrl+C to stop"
    echo ""
    
    kubectl logs -f "$pod_name"
}

list_ingest() {
    local pod_name=$(get_cwa_pod)
    check_pod_ready "$pod_name"
    
    echo -e "${BLUE}Files in ingest folder:${NC}"
    kubectl exec "$pod_name" -- ls -la "$INGEST_PATH" 2>/dev/null || {
        echo -e "${YELLOW}Cannot list ingest folder or folder is empty${NC}"
    }
}

clean_ingest() {
    local pod_name=$(get_cwa_pod)
    check_pod_ready "$pod_name"
    
    echo -e "${YELLOW}Cleaning ingest folder...${NC}"
    echo "This will remove all files from $INGEST_PATH"
    read -p "Are you sure? (y/N): " -r
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl exec "$pod_name" -- find "$INGEST_PATH" -type f -delete
        echo -e "${GREEN}✓ Ingest folder cleaned${NC}"
    else
        echo "Operation cancelled"
    fi
}

# Main script
case "${1:-help}" in
    "add")
        if [ -z "$2" ]; then
            echo -e "${RED}Error: Please specify a file to add${NC}"
            print_usage
            exit 1
        fi
        
        # Handle multiple files
        shift
        for file in "$@"; do
            add_book "$file"
        done
        ;;
    
    "status")
        show_status
        ;;
    
    "logs")
        show_logs
        ;;
    
    "list")
        list_ingest
        ;;
    
    "clean")
        clean_ingest
        ;;
    
    "help"|*)
        print_usage
        ;;
esac
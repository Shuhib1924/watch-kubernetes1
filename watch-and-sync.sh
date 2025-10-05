#!/bin/bash

# =============================================================================
# 🚀 KUBERNETES HTML AUTO-SYNC - INSTANT SAVE VERSION
# =============================================================================
# Only syncs when you SAVE the file (not on every keystroke)
# Uses a 0.5-second debounce to detect save completion
# Syncs IMMEDIATELY after save is detected
# Maintains consistent port 8080
# =============================================================================

PORT=8080
HTML_FILE="index.html"
SERVICE_NAME="nginx-service"

echo "🚀 Kubernetes HTML Auto-Sync (Instant Save)"
echo "📁 Watching: $HTML_FILE"
echo "🌐 Port: $PORT (consistent)"
echo "⚡ Syncs IMMEDIATELY when you SAVE the file"
echo ""

# Cleanup function
cleanup() {
    echo ""
    echo "🛑 Stopping auto-sync..."
    if [ ! -z "$PF_PID" ]; then
        kill $PF_PID 2>/dev/null
    fi
    exit 0
}
trap cleanup SIGINT SIGTERM

# Function to start/restart port forwarding
start_port_forward() {
    # Kill existing port forwarding if it exists
    if [ ! -z "$PF_PID" ]; then
        kill $PF_PID 2>/dev/null
    fi

    echo "🌐 [$(date '+%H:%M:%S')] Starting port forwarding..."
    kubectl port-forward service/$SERVICE_NAME $PORT:80 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
    echo "✅ [$(date '+%H:%M:%S')] Port forwarding active on http://localhost:$PORT"
}

# Function to sync HTML to Kubernetes
sync_html() {
    echo "🔄 [$(date '+%H:%M:%S')] Syncing to Kubernetes..."

    # Update ConfigMap
    kubectl create configmap nginx-html --from-file=index.html=./$HTML_FILE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1

    # Restart pod
    kubectl delete pod nginx >/dev/null 2>&1
    kubectl apply -f nginx.yaml >/dev/null 2>&1

    # Wait for readiness
    kubectl wait --for=condition=Ready pod/nginx --timeout=30s >/dev/null 2>&1

    # Wait a bit more for the pod to fully start serving content
    sleep 2

    # Restart port forwarding since pod restarted
    start_port_forward

    # Give port forwarding time to stabilize
    sleep 2

    echo "✅ [$(date '+%H:%M:%S')] Changes synced and pod ready"
    echo "🌐 [$(date '+%H:%M:%S')] Port forwarding stable - browser will detect changes"
    echo ""
}

# Start initial port forwarding
start_port_forward
echo ""

# Initial sync
sync_html

echo "👀 Ready! Save your HTML file for instant sync..."
echo "🔄 Press Ctrl+C to stop"
echo ""

# File watching with instant sync after save detection
last_modified=$(stat -c %Y "$HTML_FILE" 2>/dev/null || stat -f %m "$HTML_FILE" 2>/dev/null)
pending_change=false
change_time=0

while true; do
    sleep 0.2  # Check more frequently for faster detection

    # Get current modification time
    current_modified=$(stat -c %Y "$HTML_FILE" 2>/dev/null || stat -f %m "$HTML_FILE" 2>/dev/null)

    # If file changed, start debounce timer
    if [ "$current_modified" != "$last_modified" ]; then
        if [ "$pending_change" = false ]; then
            echo "📝 [$(date '+%H:%M:%S')] File change detected..."
        fi
        pending_change=true
        change_time=$(date +%s)
        last_modified=$current_modified
    fi

    # If enough time passed since last change (very short delay), sync immediately
    if [ "$pending_change" = true ]; then
        current_time=$(date +%s)
        # Only 0.5 second delay to detect save completion, then sync immediately
        if [ $((current_time - change_time)) -ge 1 ]; then
            echo "💾 [$(date '+%H:%M:%S')] File saved! Syncing immediately..."
            sync_html
            pending_change=false
        fi
    fi
done
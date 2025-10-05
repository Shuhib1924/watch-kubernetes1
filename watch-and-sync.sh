#!/bin/bash

PORT=8080
HTML_FILE="index.html"
SERVICE_NAME="nginx-service"

echo "🚀 Auto-Sync: $HTML_FILE → Kubernetes"
echo "🌐 Port: $PORT"

cleanup() {
    [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

start_port_forward() {
    [ ! -z "$PF_PID" ] && kill $PF_PID 2>/dev/null
    kubectl port-forward service/$SERVICE_NAME $PORT:80 >/dev/null 2>&1 &
    PF_PID=$!
    sleep 2
}

sync_html() {
    local start_time=$(date +%s)
    echo ""
    echo "🔄 [$(date '+%H:%M:%S')] Starting sync process..."

    # Stage 1: Update ConfigMap
    local stage_start=$(date +%s)
    echo "  📝 Stage 1: Updating ConfigMap..."
    kubectl create configmap nginx-html --from-file=index.html=./$HTML_FILE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    local stage_end=$(date +%s)
    echo "     ✅ ConfigMap updated ($((stage_end - stage_start))s)"

    # Stage 2: Delete old pod
    stage_start=$(date +%s)
    echo "  🗑️  Stage 2: Deleting old pod..."
    kubectl delete pod nginx >/dev/null 2>&1
    stage_end=$(date +%s)
    echo "     ✅ Pod deleted ($((stage_end - stage_start))s)"

    # Stage 3: Create new pod
    stage_start=$(date +%s)
    echo "  🚀 Stage 3: Creating new pod..."
    kubectl apply -f nginx.yaml >/dev/null 2>&1
    stage_end=$(date +%s)
    echo "     ✅ Pod created ($((stage_end - stage_start))s)"

    # Stage 4: Wait for pod ready
    stage_start=$(date +%s)
    echo "  ⏳ Stage 4: Waiting for pod ready..."
    kubectl wait --for=condition=Ready pod/nginx --timeout=30s >/dev/null 2>&1
    stage_end=$(date +%s)
    echo "     ✅ Pod ready ($((stage_end - stage_start))s)"

    # Stage 5: Stabilization wait
    stage_start=$(date +%s)
    echo "  ⌛ Stage 5: Stabilization wait..."
    sleep 2
    stage_end=$(date +%s)
    echo "     ✅ Stabilized ($((stage_end - stage_start))s)"

    # Stage 6: Restart port forwarding
    stage_start=$(date +%s)
    echo "  🌐 Stage 6: Restarting port forwarding..."
    start_port_forward
    sleep 1
    stage_end=$(date +%s)
    echo "     ✅ Port forwarding ready ($((stage_end - stage_start))s)"

    # Total duration
    local end_time=$(date +%s)
    echo "🎉 [$(date '+%H:%M:%S')] Sync complete! Total time: $((end_time - start_time))s"
    echo "   🌐 Browser should auto-reload in ~3 seconds"
    echo ""
}

start_port_forward
sync_html

last_modified=$(stat -c %Y "$HTML_FILE" 2>/dev/null || stat -f %m "$HTML_FILE" 2>/dev/null)

echo "👀 [$(date '+%H:%M:%S')] Watching for changes..."

while true; do
    sleep 0.1
    current_modified=$(stat -c %Y "$HTML_FILE" 2>/dev/null || stat -f %m "$HTML_FILE" 2>/dev/null)

    if [ "$current_modified" != "$last_modified" ]; then
        echo "📝 [$(date '+%H:%M:%S')] File change detected! Waiting for save completion..."
        sleep 1  # Wait for save to complete
        sync_html
        last_modified=$current_modified
        echo "👀 [$(date '+%H:%M:%S')] Resuming watch..."
    fi
done
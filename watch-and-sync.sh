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
    echo "🔄 Syncing..."
    kubectl create configmap nginx-html --from-file=index.html=./$HTML_FILE --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1
    kubectl delete pod nginx >/dev/null 2>&1
    kubectl apply -f nginx.yaml >/dev/null 2>&1
    kubectl wait --for=condition=Ready pod/nginx --timeout=30s >/dev/null 2>&1
    sleep 2
    start_port_forward
    sleep 1
    echo "✅ Synced"
}

start_port_forward
sync_html

last_modified=$(stat -c %Y "$HTML_FILE" 2>/dev/null || stat -f %m "$HTML_FILE" 2>/dev/null)

echo "👀 Watching for changes..."

while true; do
    sleep 0.1
    current_modified=$(stat -c %Y "$HTML_FILE" 2>/dev/null || stat -f %m "$HTML_FILE" 2>/dev/null)

    if [ "$current_modified" != "$last_modified" ]; then
        sleep 1  # Wait for save to complete
        sync_html
        last_modified=$current_modified
    fi
done
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="/opt/decard"

echo "=== Decard Deploy ==="

# Pull latest code
cd "$PROJECT_DIR"
git pull origin master

# Backend
echo "--- Backend ---"
cd "$PROJECT_DIR/back"
source .venv/bin/activate
pip install -r requirements.txt --quiet
sudo systemctl restart decard

# Frontend (web build)
echo "--- Frontend (web) ---"
cd "$PROJECT_DIR/front"
flutter build web --dart-define=API_BASE_URL=https://decard-api.eupori.dev

echo "=== Deploy complete ==="

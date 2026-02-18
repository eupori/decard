#!/usr/bin/env bash
set -euo pipefail

APP_DIR="$HOME/apps/decard"
NGINX_CONF_DIR="$HOME/apps/fridge-recipe/back/nginx/conf.d"

echo "=== Decard Deploy ==="

# 1. Pull latest code
cd "$APP_DIR"
git pull origin master

# 2. Backend: Docker build + restart
echo "--- Backend (Docker) ---"
docker compose build --no-cache
docker compose up -d
docker compose ps

# 3. Nginx config 복사 + reload
echo "--- Nginx config ---"
cp deploy/nginx-decard-api.conf "$NGINX_CONF_DIR/decard-api.conf"
cp deploy/nginx-decard-web.conf "$NGINX_CONF_DIR/decard-web.conf"
docker exec back-nginx-1 nginx -t && docker exec back-nginx-1 nginx -s reload

# 4. Frontend: Flutter web 빌드 결과물을 nginx 볼륨에 복사
echo "--- Frontend (web) ---"
docker exec back-nginx-1 mkdir -p /var/www/decard
docker cp front/build/web/. back-nginx-1:/var/www/decard/

# 5. Health check
echo "--- Health check ---"
sleep 3
curl -sf http://localhost:8001/health && echo " OK" || echo " FAIL"

echo "=== Deploy complete ==="

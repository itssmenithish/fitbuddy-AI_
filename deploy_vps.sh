#!/usr/bin/env bash
set -euo pipefail

APP_DIR="/home/fitbuddy"
APP_NAME="fitbuddy"
GIT_REPO="https://github.com/your-user/your-repo.git"
PORT="8000"
DOMAIN="yourdomain.com"

sudo apt update && sudo apt install -y python3 python3-venv python3-pip nginx git

if [ ! -d "$APP_DIR" ]; then
  sudo mkdir -p "$APP_DIR"
  sudo chown "$USER":"$USER" "$APP_DIR"
fi

cd "$APP_DIR"
if [ ! -d .git ]; then
  git clone "$GIT_REPO" .
fi

python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install -r requirements.txt

cat > .env <<'EOF'
APP_NAME=FitBuddy AI
DATABASE_URL=sqlite:///./fitbuddy.db
GOOGLE_API_KEY=
GEMINI_WORKOUT_MODEL=gemini-2.5-flash
GEMINI_TIP_MODEL=gemini-2.5-flash
ADMIN_TOKEN=fitbuddy-admin
EOF

cat > /etc/systemd/system/fitbuddy.service <<EOF
[Unit]
Description=FitBuddy AI FastAPI App
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
Environment="PATH=$APP_DIR/.venv/bin"
ExecStart=$APP_DIR/.venv/bin/gunicorn app.main:app --workers 2 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:$PORT
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable fitbuddy
sudo systemctl restart fitbuddy

sudo tee /etc/nginx/sites-available/fitbuddy.conf >/dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/fitbuddy.conf /etc/nginx/sites-enabled/fitbuddy.conf
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx

sudo ufw allow OpenSSH
sudo ufw allow 'Nginx Full'
sudo ufw --force enable

echo "Deployment complete. Open http://$DOMAIN"

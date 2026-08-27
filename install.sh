#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

VERSION="V 0.0.3"
REPO_DIR="/root/fastbrains-tproxy"
SITE_INPUT="/opt/fastbrains-site"
SITE_TARGET="/srv/fastbrains-site"
REPO_URL_B64="aHR0cHM6Ly9naXRodWIuY29tL2Zhc3RicmFpbnMxMy90ZWxlZ3JhbS13ZWItcHJveHk="

die() {
    echo
    echo "ERROR: $*" >&2
    exit 1
}

trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

valid_domain() {
    [[ "$1" =~ ^[a-z0-9.-]+$ ]] && [[ "$1" == *.* ]] && [[ "$1" != *..* ]]
}

valid_email() {
    [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

valid_secret() {
    [[ "$1" =~ ^([0-9a-f]{32}|dd[0-9a-f]{32})$ ]]
}

port_is_listening() {
    local port="$1"
    ss -lnt | grep -Eq ":${port}\b"
}

port_has_expected_process() {
    local port="$1"
    local process="$2"
    ss -lntp 2>/dev/null | grep -Eq ":${port}\b.*users:\(\(\"${process}\""
}

check_install_port() {
    local port="$1"
    local process="$2"
    if ! port_is_listening "$port"; then
        echo "      :${port} free"
        return 0
    fi
    if port_has_expected_process "$port" "$process"; then
        echo "      :${port} already used by ${process}; continuing."
        return 0
    fi
    ss -lntp | grep -E ":${port}\b" || true
    die "Port ${port} is occupied by an unexpected process."
}

clear 2>/dev/null || true
cat <<EOF
============================================================
      TELEGRAM WEB PROXY ${VERSION}
============================================================
EOF

[[ $EUID -eq 0 ]] || die "Run this installer as root."
[[ "$(uname -m)" == "x86_64" ]] || die "x86_64 architecture is required."

while true; do
    read -r -p "Домен (example: proxy.yourdomain.com): " DOMAIN
    DOMAIN="$(trim "$DOMAIN")"
    DOMAIN="${DOMAIN,,}"
    valid_domain "$DOMAIN" && break
    echo "Invalid domain."
done

while true; do
    read -r -p "ACME email (example: admin@yourdomain.com): " EMAIL
    EMAIL="$(trim "$EMAIL")"
    valid_email "$EMAIL" && break
    echo "Invalid email."
done

echo
read -r -p "Generate a secure secret automatically? [Y/n]: " MODE
MODE="$(trim "${MODE:-Y}")"

if [[ -z "$MODE" || "$MODE" =~ ^[Yy]$ ]]; then
    command -v openssl >/dev/null 2>&1 || {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq
        apt-get install -y -qq --no-install-recommends openssl
    }
    SECRET="$(openssl rand -hex 16)"
else
    while true; do
        read -r -s -p "WEB proxy secret (32 lowercase hex, optionally dd + 32 hex): " SECRET
        echo
        valid_secret "$SECRET" && break
        echo "Invalid secret."
    done
fi

echo
echo "[1/10] Checking system..."
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required."

echo
echo "[2/10] Installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git openssl dnsutils nftables \
    build-essential libssl-dev util-linux zlib1g-dev

echo
echo "[3/10] Checking ports..."
check_install_port 80 caddy
check_install_port 443 caddy
check_install_port 2398 mtproto-proxy
check_install_port 8080 tproxy-server
check_install_port 8081 tproxy-server

echo
echo "[4/10] Checking DNS..."
DNS_IP="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')"
[[ -n "$DNS_IP" ]] || die "No IPv4 A record found for $DOMAIN."

VPS_IP="$(curl -4fsS --max-time 10 https://api.ipify.org || true)"
if [[ -n "$VPS_IP" && "$DNS_IP" != "$VPS_IP" ]]; then
    echo "      DNS: $DNS_IP"
    echo "      VPS: $VPS_IP"
    die "DNS does not point to this VPS."
fi

echo
echo "[5/10] Creating FastBrains public site..."
rm -rf "$SITE_INPUT"
mkdir -p "$SITE_INPUT"

cat > "$SITE_INPUT/index.html" <<'HTMLEOF'
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Скоро открытие</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #fff;
            padding: 20px;
            text-align: center;
        }

        .container {
            max-width: 600px;
            animation: fadeIn 1s ease-out;
        }

        h1 {
            font-size: clamp(2.5rem, 8vw, 4.5rem);
            font-weight: 700;
            letter-spacing: -0.02em;
            margin-bottom: 1rem;
        }

        p {
            font-size: clamp(1rem, 2.5vw, 1.25rem);
            opacity: 0.9;
            line-height: 1.6;
            margin-bottom: 2rem;
        }

        .date {
            display: inline-block;
            padding: 0.5rem 1.5rem;
            border: 1px solid rgba(255, 255, 255, 0.3);
            border-radius: 999px;
            font-size: 0.9rem;
            letter-spacing: 0.1em;
            text-transform: uppercase;
            backdrop-filter: blur(10px);
            background: rgba(255, 255, 255, 0.05);
        }

        @keyframes fadeIn {
            from {
                opacity: 0;
                transform: translateY(20px);
            }
            to {
                opacity: 1;
                transform: translateY(0);
            }
        }
    </style>
</head>
<body>
    <main class="container">
        <h1>Скоро открытие</h1>
        <p>Мы работаем над чем-то особенным. Совсем скоро здесь появится наш новый проект.</p>
    </main>
</body>
</html>
HTMLEOF

chmod 0755 "$SITE_INPUT"
chmod 0644 "$SITE_INPUT/index.html"

echo
echo "[6/10] Installing Telegram Web Proxy components..."
if [[ ! -d "$REPO_DIR/.git" ]]; then
    rm -rf "$REPO_DIR"
    git clone --depth 1 -q https://github.com/telegramdesktop/tproxy-server.git "$REPO_DIR"
fi
cd "$REPO_DIR"

echo "      Installing Caddy..."
caddy_version="2.8.4"
caddy_archive="$(mktemp /tmp/caddy-linux-amd64.XXXXXX.tar.gz)"
caddy_directory="$(mktemp -d /tmp/caddy-linux-amd64.XXXXXX)"

curl --fail --silent --show-error --location \
    --output "$caddy_archive" \
    "https://github.com/caddyserver/caddy/releases/download/v${caddy_version}/caddy_${caddy_version}_linux_amd64.tar.gz"

tar -C "$caddy_directory" -xzf "$caddy_archive"
install -m 0755 "$caddy_directory/caddy" /usr/local/bin/caddy
rm -f "$caddy_archive"
rm -rf "$caddy_directory"

if ! id caddy >/dev/null 2>&1; then
    useradd --system --home /var/lib/caddy --shell /usr/sbin/nologin caddy
fi
install -d -o root -g caddy -m 0750 /etc/caddy
install -d -o caddy -g caddy -m 0750 /var/lib/caddy

echo "      Installing official MTProxy..."
"$REPO_DIR/deploy/install-mtproxy.sh"

if ! id tproxy >/dev/null 2>&1; then
    useradd --system --home /nonexistent --shell /usr/sbin/nologin tproxy
fi

echo "      Installing Go relay..."
go_version="1.22.5"
go_archive="$(mktemp /tmp/go-linux-amd64.XXXXXX.tar.gz)"
go_directory="$(mktemp -d /tmp/go-linux-amd64.XXXXXX)"

curl --fail --silent --show-error --location \
    --output "$go_archive" \
    "https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"

tar -C "$go_directory" -xzf "$go_archive"
mv "$go_directory/go" "/opt/go${go_version}"
rm -f "$go_archive"
rm -rf "$go_directory"
go_binary="/opt/go${go_version}/bin/go"

echo "      Building relay..."
(
    cd "$REPO_DIR"
    "$go_binary" build -trimpath -ldflags='-s -w' \
        -o /usr/local/bin/tproxy-server ./cmd/tproxy-server
)
chown root:root /usr/local/bin/tproxy-server
chmod 0755 /usr/local/bin/tproxy-server

echo "      Preparing site..."
install -d -o root -g tproxy -m 0750 "$SITE_TARGET"
rm -rf "$SITE_TARGET"/*
cp -a "$SITE_INPUT/." "$SITE_TARGET/"
chown -R root:tproxy "$SITE_TARGET"
find "$SITE_TARGET" -type d -exec chmod 0750 {} +
find "$SITE_TARGET" -type f -exec chmod 0640 {} +

echo "      Preparing configuration..."
install -d -o root -g tproxy -m 0750 /etc/tproxy-server

cat > /etc/tproxy-server/config.json <<CFGEOF
{
  "public_hostname": "$DOMAIN",
  "listen": "127.0.0.1:8080",
  "admin_listen": "127.0.0.1:8081",
  "public_dir": "/srv/fastbrains-site",
  "profiles_file": "/run/credentials/tproxy-server.service/profiles.json"
}
CFGEOF

cat > /etc/tproxy-server/profiles.json <<PROFEOF
{"profiles":[{"name":"default","secret":"$SECRET","backend":"127.0.0.1:2398"}]}
PROFEOF

chown root:tproxy /etc/tproxy-server/config.json /etc/tproxy-server/profiles.json
chmod 0640 /etc/tproxy-server/config.json
chmod 0400 /etc/tproxy-server/profiles.json

backend_secret="$SECRET"
if [[ "$backend_secret" == dd* ]] && [[ ${#backend_secret} -eq 34 ]]; then
    backend_secret="${backend_secret:2}"
fi

install -d -o root -g mtproxy -m 0750 /etc/mtproxy
cat > /etc/mtproxy/mtproxy.env <<ENVEOF
MTPROXY_SECRET=$backend_secret
MTPROXY_WORKERS=1
MTPROXY_MAX_CONNECTIONS=4096
ENVEOF
chown root:mtproxy /etc/mtproxy/mtproxy.env
chmod 0640 /etc/mtproxy/mtproxy.env

echo "      Installing service files..."
install -m 0644 "$REPO_DIR/deploy/Caddyfile" /etc/caddy/Caddyfile
install -m 0644 "$REPO_DIR/deploy/caddy.service" /etc/systemd/system/caddy.service

install -d -m 0755 /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/tproxy.conf <<SRVEOF
[Service]
Environment=TPROXY_HOSTNAME=$DOMAIN
Environment=TPROXY_SITE_ROOT=/srv/fastbrains-site
Environment=ACME_EMAIL=$EMAIL
ReadWritePaths=/etc/caddy
SRVEOF

install -m 0644 "$REPO_DIR/deploy/tproxy-server.service" /etc/systemd/system/tproxy-server.service
install -m 0644 "$REPO_DIR/deploy/mtproxy.service" /etc/systemd/system/mtproxy.service
install -m 0644 "$REPO_DIR/deploy/tproxy-firewall.service" /etc/systemd/system/tproxy-firewall.service
install -m 0644 "$REPO_DIR/deploy/refresh-mtproxy-config.service" /etc/systemd/system/refresh-mtproxy-config.service
install -m 0644 "$REPO_DIR/deploy/refresh-mtproxy-config.timer" /etc/systemd/system/refresh-mtproxy-config.timer

systemctl daemon-reload

echo "      Starting services..."
systemctl enable --now tproxy-firewall.service
systemctl enable mtproxy.service
systemctl restart mtproxy.service

for _ in $(seq 1 20); do
    systemctl is-active --quiet mtproxy && ss -lnt | grep -Eq ':(2398)\b' && break
    sleep 1
done

systemctl enable tproxy-server.service
systemctl restart tproxy-server.service

for _ in $(seq 1 30); do
    systemctl is-active --quiet tproxy-server && curl -fsS --max-time 2 http://127.0.0.1:8081/readyz >/dev/null 2>&1 && break
    sleep 1
done

systemctl enable --now refresh-mtproxy-config.timer
systemctl enable caddy.service
systemctl restart caddy.service

echo
echo "[9/10] Running health checks..."
curl -fsS --max-time 5 http://127.0.0.1:8081/healthz >/dev/null || die "tproxy-server healthz failed."

HTTPS_READY=0
for _ in $(seq 1 90); do
    curl -fsSI --max-time 5 "https://${DOMAIN}/" >/dev/null 2>&1 && HTTPS_READY=1 && break
    sleep 2
done

echo
echo "[10/10] Final verification..."
for unit in mtproxy tproxy-server caddy; do
    systemctl is-active --quiet "$unit" || die "$unit is not active."
done

TELEGRAM_SECRET="${SECRET#dd}"
REPO_URL="$(printf "%s" "$REPO_URL_B64" | base64 -d)"

echo
echo "============================================================"
echo "             TELEGRAM WEB PROXY"
echo "============================================================"
echo
echo "Domain:"
echo "  https://${DOMAIN}/"
echo
echo "Secret:"
echo "  ${SECRET}"
echo
echo "Telegram Web Proxy Link:"
echo "  https://t.me/webproxy?server=${DOMAIN}&secret=${TELEGRAM_SECRET}"
echo
echo "Repository:"
echo "  ${REPO_URL}"
echo
echo "Status:"
echo "  HTTPS          OK"
echo "  MTProxy        ACTIVE"
echo "  Relay          READY"
echo "  Firewall       ACTIVE"
echo
echo "============================================================"

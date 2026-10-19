#!/bin/bash
set -e

clear
echo "=========================================================="
echo " 🚀 Универсальный установщик Telegram Proxy"
echo "    - Telegram WEB Proxy (HTTPS/Caddy/Domain)"
echo "    - Classic MTProxy (Direct TCP/TLS Cloaking)"
echo "    - Установка обоих прокси одновременно"
echo "=========================================================="

# 1. Проверка прав root
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Ошибка: Запустите скрипт от имени root."
  exit 1
fi

# Определение внешнего IP
SERVER_IP=$(curl -s -4 https://ifconfig.me || curl -s -4 https://api.ipify.org)

# 2. Выбор режима установки
echo ""
echo "Выберите режим установки:"
echo " 1) Только Telegram WEB Proxy (нужен свой домен, порты 80 и 443)"
echo " 2) Только классический MTProxy (прямой порт, без своего домена)"
echo " 3) Установить ОБА варианта сразу"
echo ""
read -p "Введите цифру [1-3] (по умолчанию 3): " MODE_CHOICE
MODE_CHOICE=${MODE_CHOICE:-3}

INSTALL_WEB=false
INSTALL_CLASSIC=false

case "$MODE_CHOICE" in
  1) INSTALL_WEB=true ;;
  2) INSTALL_CLASSIC=true ;;
  3) INSTALL_WEB=true; INSTALL_CLASSIC=true ;;
  *) echo "❌ Неверный выбор. Прерывание."; exit 1 ;;
esac

# 3. Сбор параметров
DOMAIN=""
EMAIL=""
CLASSIC_PORT=8443
FAKE_DOMAIN=""

if [ "$INSTALL_WEB" = true ]; then
  echo ""
  echo "--- 🌐 Настройка Web Proxy ---"
  read -p "👉 Введите ваш домен для прокси (например, proxy.example.com): " DOMAIN
  DOMAIN=$(echo "$DOMAIN" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9.-]+$'; then
    echo "❌ Ошибка: домен должен содержать только буквы, цифры, точки и дефисы."
    exit 1
  fi

  read -p "👉 Введите Email для SSL (нажмите Enter, чтобы пропустить): " EMAIL
  EMAIL=$(echo "$EMAIL" | tr -d ' ')
  if [ -n "$EMAIL" ]; then
    if ! echo "$EMAIL" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
      echo "❌ Ошибка: некорректный формат Email."
      exit 1
    fi
  fi
fi

if [ "$INSTALL_CLASSIC" = true ]; then
  echo ""
  echo "--- 🛡️ Настройка Classic MTProxy ---"
  read -p "👉 Введите порт для подключения [по умолчанию 8443]: " USER_PORT
  CLASSIC_PORT=${USER_PORT:-8443}

  read -p "👉 Введите fake-домен для маскировки (TLS Cloaking) [например: google.com, cloudflare.com, yandex.ru]: " USER_FAKE
  USER_FAKE=$(echo "$USER_FAKE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
  FAKE_DOMAIN=${USER_FAKE:-google.com}
  echo "✅ Выбран fake-домен: $FAKE_DOMAIN"
fi

echo ""
echo "--- 🔑 Секретный ключ ---"
read -p "👉 Секретный ключ (32 hex) [оставьте пустым для автогенерации]: " SECRET
if [ -z "$SECRET" ]; then
  SECRET=$(openssl rand -hex 16)
  echo "✅ Сгенерирован секрет: $SECRET"
fi

if ! echo "$SECRET" | grep -qE '^([0-9a-f]{32}|dd[0-9a-f]{32})$'; then
  echo "❌ Ошибка: секрет должен состоять из 32 hex-символов (опционально с префиксом 'dd')."
  exit 1
fi

# Подготовка TLS-секрета для Classic MTProxy (hex(fake_domain))
if [ "$INSTALL_CLASSIC" = true ]; then
  FAKE_DOMAIN_HEX=$(echo -n "$FAKE_DOMAIN" | xxd -p | tr -d '\n')
  CLASSIC_SECRET="ee${SECRET}${FAKE_DOMAIN_HEX}"
fi

# 4. Установка общих зависимостей
echo ""
echo "📦 Установка системных пакетов..."
apt update -qq
apt install -y -qq curl git build-essential nftables golang-go debian-keyring debian-archive-keyring apt-transport-https xxd

# 5. Создание системных пользователей и директорий
mkdir -p /etc/tproxy-server /etc/mtproxy /srv/tproxy-site
useradd -r -s /usr/sbin/nologin mtproxy 2>/dev/null || true
useradd -r -s /usr/sbin/nologin tproxy 2>/dev/null || true

# 6. Клонирование и сборка tproxy-server
echo "📥 Подготовка tproxy-server..."
rm -rf /tmp/tproxy-server
git clone https://github.com/telegramdesktop/tproxy-server.git /tmp/tproxy-server
cd /tmp/tproxy-server

echo "🔨 Сборка tproxy-server..."
go build -trimpath -o /usr/local/bin/tproxy-server ./cmd/tproxy-server
chmod +x /usr/local/bin/tproxy-server

# 7. Установка бинарника MTProxy (официальный backend C-source)
echo "🔧 Сборка и настройка backend MTProxy..."
bash deploy/install-mtproxy.sh

# Настройка окружения MTProxy
cat <<ENV_EOF > /etc/mtproxy/mtproxy.env
MTPROXY_SECRET=$SECRET
MTPROXY_WORKERS=1
MTPROXY_MAX_CONNECTIONS=4096
ENV_EOF
chmod 0400 /etc/mtproxy/mtproxy.env

# 8. Копирование и очистка systemd-сервисов
cp deploy/tproxy-server.service /etc/systemd/system/
cp deploy/mtproxy.service /etc/systemd/system/

# Удаление отсутствующей зависимости от tproxy-firewall
sed -i '/tproxy-firewall.service/d' /etc/systemd/system/tproxy-server.service
sed -i '/tproxy-firewall.service/d' /etc/systemd/system/mtproxy.service

# 9. Настройка компонентов WEB Proxy (если выбрано)
if [ "$INSTALL_WEB" = true ]; then
  echo "🌐 Настройка компонентов Web Proxy..."

  # Сайт-заглушка
  cat <<'SITEEOF' > /srv/tproxy-site/index.html
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Вход в систему</title>
<style>
  * { box-sizing: border-box; }
  body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background: #f0f2f5; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
  .card { background: #fff; padding: 40px 32px; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,.08); width: 100%; max-width: 380px; }
  h1 { margin: 0 0 24px; font-size: 22px; text-align: center; color: #1a1a1a; }
  label { display: block; font-size: 13px; color: #555; margin-bottom: 6px; }
  input { width: 100%; padding: 10px 12px; margin-bottom: 16px; border: 1px solid #ccc; border-radius: 6px; font-size: 14px; }
  button { width: 100%; padding: 11px; background: #2b7fff; color: #fff; border: none; border-radius: 6px; font-size: 15px; cursor: pointer; }
  .error { display: none; margin-top: 16px; padding: 10px; background: #fdecea; color: #b3261e; border-radius: 6px; font-size: 13px; text-align: center; }
</style>
</head>
<body>
  <div class="card">
    <h1>Вход в систему</h1>
    <form id="loginForm">
      <label for="user">Логин</label>
      <input type="text" id="user" name="user" required>
      <label for="pass">Пароль</label>
      <input type="password" id="pass" name="pass" required>
      <button type="submit">Войти</button>
    </form>
    <div class="error" id="error">Неверный логин или пароль</div>
  </div>
  <script>
    document.getElementById('loginForm').addEventListener('submit', function(e) { e.preventDefault(); document.getElementById('error').style.display = 'block'; });
  </script>
</body>
</html>
SITEEOF

  # Конфигурация tproxy-server
  cat <<CFGEOF > /etc/tproxy-server/config.json
{
  "public_hostname": "$DOMAIN",
  "profiles_file": "/etc/tproxy-server/profiles.json",
  "public_dir": "/srv/tproxy-site"
}
CFGEOF
  chown root:tproxy /etc/tproxy-server/config.json
  chmod 0640 /etc/tproxy-server/config.json

  cat <<PROFEOF > /etc/tproxy-server/profiles.json
{
  "profiles": [
    {
      "name": "default",
      "secret": "$SECRET",
      "backend": "127.0.0.1:2398",
      "carrier_mode": "https"
    }
  ]
}
PROFEOF
  chown tproxy:tproxy /etc/tproxy-server/profiles.json
  chmod 0400 /etc/tproxy-server/profiles.json

  head -c 32 /dev/urandom > /etc/tproxy-server/token.key
  chown tproxy:tproxy /etc/tproxy-server/token.key
  chmod 0400 /etc/tproxy-server/token.key

  # Caddy
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null || true
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list >/dev/null
  apt update -qq
  apt install -y -qq caddy

  # Определение блока TLS в Caddyfile
  TLS_CONFIG=""
  if [ -n "$EMAIL" ]; then
    TLS_CONFIG="tls $EMAIL"
  fi

  cat <<CADDYEOF > /etc/caddy/Caddyfile
$DOMAIN {
    $TLS_CONFIG
    reverse_proxy 127.0.0.1:8080 {
        transport http {
            response_header_timeout 40s
        }
    }
    encode zstd gzip
}
CADDYEOF
  chown -R caddy:caddy /etc/caddy
fi

# 10. Настройка Classic MTProxy на отдельном порту (если выбрано)
if [ "$INSTALL_CLASSIC" = true ]; then
  echo "🛡️ Конфигурация отдельного classic-сервиса MTProxy..."
  
  cat <<SERVICE_EOF > /etc/systemd/system/mtproxy-classic.service
[Unit]
Description=Telegram Classic MTProxy (Direct TCP)
After=network.target

[Service]
Type=simple
User=mtproxy
Group=mtproxy
Restart=always
RestartSec=5
LimitNOFILE=65536
ExecStart=/usr/local/bin/mtproto-proxy -u mtproxy -p 8888 -H $CLASSIC_PORT -S $SECRET -P $FAKE_DOMAIN --aes-pwd /etc/mtproxy/proxy-secret /etc/mtproxy/proxy-multi.conf -M 1 --http-stats

[Install]
WantedBy=multi-user.target
SERVICE_EOF
fi

# 11. Настройка сетевой изоляции (nftables)
echo "🛡️ Применение правил nftables..."
nft add table inet tproxy_backend 2>/dev/null || true
nft add chain inet tproxy_backend input '{ type filter hook input priority 0; policy accept; }' 2>/dev/null || true

# Внутренние порты изолируются на localhost
nft add rule inet tproxy_backend input tcp dport 2398 ip saddr != 127.0.0.1 drop 2>/dev/null || true
nft add rule inet tproxy_backend input tcp dport 8080 ip saddr != 127.0.0.1 drop 2>/dev/null || true
nft add rule inet tproxy_backend input tcp dport 8081 ip saddr != 127.0.0.1 drop 2>/dev/null || true

# 12. Перезагрузка и включение служб
systemctl daemon-reload

SERVICES_TO_START="mtproxy"

if [ "$INSTALL_WEB" = true ]; then
  SERVICES_TO_START="$SERVICES_TO_START tproxy-server caddy"
fi

if [ "$INSTALL_CLASSIC" = true ]; then
  SERVICES_TO_START="$SERVICES_TO_START mtproxy-classic"
fi

systemctl enable $SERVICES_TO_START
systemctl restart $SERVICES_TO_START

# 13. Итоговый отчет
echo ""
echo "=========================================================="
echo " ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo "=========================================================="

if [ "$INSTALL_WEB" = true ]; then
  echo "📌 1. Telegram WEB Proxy (HTTPS порт 443):"
  echo "   - Домен      : $DOMAIN"
  echo "   - Порт       : 443"
  echo "   - Секрет     : $SECRET"
  echo "   🔗 Подключение:"
  echo "   https://t.me/webproxy?server=$DOMAIN&secret=$SECRET"
  echo ""
fi

if [ "$INSTALL_CLASSIC" = true ]; then
  echo "📌 2. Classic MTProxy (TLS маскировка):"
  echo "   - Сервер     : $SERVER_IP"
  echo "   - Порт       : $CLASSIC_PORT"
  echo "   - Маскировка : $FAKE_DOMAIN"
  echo "   - Секрет     : $CLASSIC_SECRET"
  echo "   🔗 Подключение:"
  echo "   https://t.me/proxy?server=$SERVER_IP&port=$CLASSIC_PORT&secret=$CLASSIC_SECRET"
  echo ""
fi
echo "=========================================================="

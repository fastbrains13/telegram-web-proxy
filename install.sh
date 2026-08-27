cat << 'EOF' > /root/install.sh
#!/bin/bash

echo "=========================================================="
echo " 🚀 Полная установка tproxy-server (Telegram WEB Proxy)"
echo "=========================================================="

# 1. Проверка прав root (совместимая со всеми shell)
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Ошибка: Запустите скрипт от имени root."
  exit 1
fi

# 2. Запрос параметров
echo ""
read -p "👉 Введите доменное имя (например, example.site): " DOMAIN
if ! echo "$DOMAIN" | grep -qE '^[a-z0-9.-]+$'; then
  echo "❌ Ошибка: домен должен быть в нижнем регистре и содержать только буквы, цифры, точки и дефисы."
  exit 1
fi

read -p "👉 Введите Email для SSL-сертификата (Let's Encrypt): " EMAIL
if ! echo "$EMAIL" | grep -qE '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
  echo "❌ Ошибка: некорректный формат Email."
  exit 1
fi

read -p "👉 Секретный ключ (оставьте пустым для автогенерации): " SECRET
if [ -z "$SECRET" ]; then
  SECRET=$(openssl rand -hex 16)
  echo "✅ Сгенерирован секрет: $SECRET"
fi

if ! echo "$SECRET" | grep -qE '^([0-9a-f]{32}|dd[0-9a-f]{32})$'; then
  echo "❌ Ошибка: секрет должен состоять из 32 hex-символов (опционально с префиксом 'dd')."
  exit 1
fi

# 3. Установка зависимостей
echo ""
echo "📦 Установка системных зависимостей..."
apt update -qq
apt install -y -qq curl git build-essential nftables golang-go debian-keyring debian-archive-keyring apt-transport-https

# 4. Подготовка директорий и сайта-заглушки
echo "📁 Подготовка директорий..."
mkdir -p /etc/tproxy-server /etc/mtproxy /srv/tproxy-site
cat <<'SITEEOF' > /srv/tproxy-site/index.html
<!DOCTYPE html><html><head><title>Proxy Active</title></head><body><h1>Telegram WEB Proxy</h1><p>Работает корректно.</p></body></html>
SITEEOF

# 5. Клонирование репозитория
echo "📥 Клонирование репозитория..."
rm -rf /tmp/tproxy-server
git clone https://github.com/telegramdesktop/tproxy-server.git /tmp/tproxy-server
cd /tmp/tproxy-server

# 6. Сборка БЕЗ запуска тестов (обход ошибки прав доступа)
echo "🔨 Сборка tproxy-server..."
go build -trimpath -o /usr/local/bin/tproxy-server ./cmd/tproxy-server
chmod +x /usr/local/bin/tproxy-server

# 7. Создание пользователей
useradd -r -s /usr/sbin/nologin mtproxy 2>/dev/null || true
useradd -r -s /usr/sbin/nologin tproxy 2>/dev/null || true

# 8. Создание конфигурационных файлов со СТРОГИМИ правами
echo "⚙️ Настройка конфигурации..."
cat <<CFGEOF > /etc/tproxy-server/config.json
{
  "hostname": "$DOMAIN",
  "profiles_file": "/etc/tproxy-server/profiles.json",
  "public_dir": "/srv/tproxy-site",
  "listen_addr": "127.0.0.1:8080",
  "admin_addr": "127.0.0.1:8081"
}
CFGEOF
chmod 0644 /etc/tproxy-server/config.json

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
chmod 0400 /etc/tproxy-server/profiles.json
chown root:root /etc/tproxy-server/profiles.json

cat <<ENV_EOF > /etc/mtproxy/mtproxy.env
MTPROXY_SECRET=$SECRET
MTPROXY_WORKERS=1
MTPROXY_MAX_CONNECTIONS=4096
ENV_EOF
chmod 0400 /etc/mtproxy/mtproxy.env

# 9. Установка MTProxy
echo "🔧 Настройка backend MTProxy..."
bash deploy/install-mtproxy.sh

# 10. Установка и настройка Caddy
echo "🌐 Установка и настройка Caddy..."
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt update -qq
apt install -y -qq caddy

cat <<CADDYEOF > /etc/caddy/Caddyfile
$DOMAIN {
    reverse_proxy 127.0.0.1:8080 {
        transport http {
            response_header_timeout 40s
        }
    }
    encode zstd gzip
}
CADDYEOF
chown -R caddy:caddy /etc/caddy

# 11. Настройка брандмауэра
echo "🛡️ Настройка nftables..."
nft add table inet tproxy_backend 2>/dev/null || true
nft add chain inet tproxy_backend input '{ type filter hook input priority 0; policy accept; }' 2>/dev/null || true
nft add rule inet tproxy_backend input tcp dport 2398 ip saddr != 127.0.0.1 drop 2>/dev/null || true
nft add rule inet tproxy_backend input tcp dport 8080 ip saddr != 127.0.0.1 drop 2>/dev/null || true
nft add rule inet tproxy_backend input tcp dport 8081 ip saddr != 127.0.0.1 drop 2>/dev/null || true

# 12. Регистрация и запуск systemd служб
echo "🚀 Регистрация и запуск служб..."
cp deploy/tproxy-server.service /etc/systemd/system/
cp deploy/mtproxy.service /etc/systemd/system/

systemctl daemon-reload
systemctl enable mtproxy tproxy-server caddy
systemctl restart mtproxy tproxy-server caddy

# 13. Финальный вывод
echo ""
echo "=========================================================="
echo " ✅ УСТАНОВКА УСПЕШНО ЗАВЕРШЕНА!"
echo "=========================================================="
echo " 📌 Данные для подключения в Telegram:"
echo "    Тип прокси : WEB Proxy (или MTProto Web)"
echo "    Хост       : $DOMAIN"
echo "    Порт       : 443"
echo "    Секрет     : $SECRET"
echo ""
echo " 🔗 Ссылка для быстрого подключения (откройте в Telegram):"
echo " https://t.me/webproxy?server=$DOMAIN&secret=$SECRET"
echo "=========================================================="
EOF

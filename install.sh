#!/bin/bash

# Скрипт автоматической установки tproxy-server (официальный WEB-прокси от Telegram Desktop)
# Репозиторий: https://github.com/telegramdesktop/tproxy-server

set -e

echo "=========================================================="
echo " Установка tproxy-server (Telegram WEB Proxy)"
echo "=========================================================="

# 1. Проверка прав и архитектуры
if [ "$EUID" -ne 0 ]; then
  echo "❌ Ошибка: Пожалуйста, запустите скрипт от имени root (или через sudo)."
  exit 1
fi

if [ "$(uname -m)" != "x86_64" ]; then
  echo "❌ Ошибка: Официальный MTProxy требует сервер с архитектурой x86_64."
  exit 1
fi

# 2. Ввод параметров
echo ""
echo "👉 Введите параметры для настройки прокси:"

read -p "Доменное имя (например, proxy.example.com): " HOSTNAME
if [[ ! "$HOSTNAME" =~ ^[a-z0-9.-]+$ ]]; then
  echo "❌ Ошибка: домен должен быть в нижнем регистре и содержать только буквы, цифры, точки и дефисы."
  exit 1
fi

read -p "Email для SSL-сертификата (Let's Encrypt): " EMAIL
if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
  echo "❌ Ошибка: некорректный формат Email."
  exit 1
fi

read -p "Секретный ключ (32 hex-символа, или нажмите Enter для автогенерации): " SECRET
if [ -z "$SECRET" ]; then
  SECRET=$(openssl rand -hex 16)
  echo "✅ Сгенерирован секрет: $SECRET"
fi

if [[ ! "$SECRET" =~ ^([0-9a-f]{32}|dd[0-9a-f]{32})$ ]]; then
  echo "❌ Ошибка: секрет должен состоять из 32 строчных шестнадцатеричных символов (опционально с префиксом 'dd')."
  exit 1
fi

# 3. Подготовка сайта-заглушки
# tproxy-server требует наличия веб-сайта, так как он работает как обратный прокси.
# Мы создадим минимальную заглушку. В будущем вы сможете заменить её на свой реальный сайт.
SITE_DIR="/srv/tproxy-site"
echo ""
echo "📁 Создание директории сайта-заглушки в $SITE_DIR ..."
mkdir -p "$SITE_DIR"
cat << 'EOF' > "$SITE_DIR/index.html"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Welcome</title>
</head>
<body>
    <p>This is a placeholder site. Replace it with your own content.</p>
</body>
</html>
EOF

# 4. Клонирование репозитория
echo ""
echo "📥 Клонирование официального репозитория..."
cd /tmp
rm -rf tproxy-server
git clone https://github.com/telegramdesktop/tproxy-server.git
cd tproxy-server

# 5. Запуск установки
echo ""
echo "⚙️ Запуск официального скрипта установки..."
echo "   (Это может занять 2-5 минут: установка Go, Caddy, сборка MTProxy)..."
echo ""

./deploy/install.sh \
  --hostname "$HOSTNAME" \
  --email "$EMAIL" \
  --secret "$SECRET" \
  --site-dir "$SITE_DIR"

# 6. Итоговая информация
echo ""
echo "=========================================================="
echo "✅ Установка успешно завершена!"
echo "=========================================================="
echo ""
echo "📌 Данные для подключения в Telegram:"
echo "   Тип прокси : WEB Proxy (или MTProto Web)"
echo "   Хост       : $HOSTNAME"
echo "   Порт       : 443"
echo "   Секрет     : $SECRET"
echo ""
echo "🔗 Ссылка для быстрого подключения (откройте в Telegram):"
echo "https://t.me/webproxy?server=$HOSTNAME&secret=$SECRET"
echo ""
echo "⚠️ ВАЖНЫЕ РЕКОМЕНДАЦИИ:"
echo "1. Убедитесь, что в брандмауэре сервера (и панели хостинга) открыты порты 80 (TCP) и 443 (TCP)."
echo "2. Замените содержимое $SITE_DIR на ваш реальный сайт, чтобы прокси не выглядел как стандартная заглушка (это критически важно для устойчивости к DPI)."
echo "3. Проверьте статус служб командой:"
echo "   systemctl status caddy tproxy-server mtproxy"
echo ""

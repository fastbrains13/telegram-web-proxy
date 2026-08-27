# ⚡ Telegram Web Proxy

Автоматическая установка Telegram Web Proxy на новый VPS.

В проекте используются:
- MTProxy
- `tproxy-server` (официальный релиз Telegram)
- Caddy (автоматический HTTPS)
- systemd
- Уникальная HTML-заглушка FastBrains

> ⚠️ **ВНИМАНИЕ**: Скрипт находится в стадии активного развития. Все риски и ответственность полностью на ваших плечах

## 1. Рекомендуемые сервера у следующих провайдеров

[Firstbyte](https://firstbyte.ru/?from=28204)

[VDSka](https://vdska.ru/?p=36069)

[VDSina](https://www.vdsina.com/?partner=b2m2e7hc7jnk) (скидка 10% при покупке сервера)

[SmartApe](http://www.smartape.ru/?partner=77444)

## 2. Требования к VPS

Новый VPS с характеристиками:
- **ОС**: Ubuntu 22.04 или 24.04 (x86_64)
- **Доступ**: root
- **Домен**: настроенная A-запись, указывающая на IP вашего VPS (например, `proxy.yourdomain.com`)
- **Порты**: 80 и 443 должны быть свободны

## 3. Установка в одну команду

Подключитесь к вашему VPS по SSH и выполните:

```bash
curl -fsSL https://raw.githubusercontent.com/fastbrains13/telegram-web-proxy/main/install.sh -o /root/install.sh
chmod +x install.sh
sudo ./install.sh

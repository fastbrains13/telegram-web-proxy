# ⚡ Настройка Telegram Web Proxy в одну команду

Скрипт автоматического развертывания официального **Telegram Web Proxy** (`tproxy-server`) на чистом VPS под управлением Ubuntu. 

Весь трафик прокси маскируется под легитимный HTTPS-сайт с автоматическим выпуском SSL-сертификатов Let's Encrypt через Caddy.

---

### Стек проекта:
* **MTProxy** — официальный бэкенд Telegram MTProto.
* **`tproxy-server`** — мультиплексор и маскировщик трафика от команды Telegram Desktop.
* **Caddy** — обратный веб-сервер с автоматической поддержкой ACME (TLS/SSL).
* **nftables** — сетевая фильтрация и изоляция внутренних портов бэкенда.
* **HTML-заглушка** — страница входа для посетителей веб-интерфейса в браузере.

> ⚠️ **ВНИМАНИЕ**: Скрипт находится в стадии активного развития. Все риски и ответственность за администрирование сервера лежат на вас.

---

<p align="center">
  <a href="https://beget.com/?id=2700620" target="_blank">
    <img src="https://cp.beget.com/promo_data/static/970x90-2.png" border="0" alt="Beget Hosting">
  </a>
</p>

## 1. Рекомендуемые VPS-провайдеры

* [Beget](https://beget.com/p2700620)
* [Play2go](https://play2go.cloud/?ref_id=jGD2_v4IsE8)
* [Firstbyte](https://firstbyte.ru/?from=28204)
* [SmartApe](http://www.smartape.ru/?partner=77444)
* [VDSka](https://vdska.ru/?p=36069)
* [Timeweb](https://timeweb.cloud/r/cc38309) *(бонус до 2000₽ при регистрации)*
* [VDSina](https://www.vdsina.com/?partner=b2m2e7hc7jnk)

---

## 2. Системные требования

* **ОС**: Ubuntu 22.04 LTS или Ubuntu 24.04 LTS (x86_64).
* **Права**: root-доступ (или пользователь с `sudo`).
* **Домен**: настроенная DNS A-запись, указывающая на публичный IPv4-адрес вашего сервера (например, `tg.example.com`).
  > **Важно**: если домен делегирован через Cloudflare, отключите проксирование (серый значок / **DNS Only**), иначе Caddy не сможет получить SSL-сертификат.
* **Сетевые порты**: открытые порты `80` и `443` TCP.

---

## 3. Установка

Подключитесь к серверу по SSH и выполните команду:

```bash
curl -fsSL [https://raw.githubusercontent.com/fastbrains13/telegram-web-proxy/main/install.sh](https://raw.githubusercontent.com/fastbrains13/telegram-web-proxy/main/install.sh) -o /root/install.sh && chmod +x /root/install.sh && sudo /root/install.sh

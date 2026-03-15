# SNI Routing — MTProxy + сайт на одном порту 443

## Архитектура

FakeTLS — это **НЕ настоящий TLS**. Nginx/HAProxy **не могут его терминировать**. Единственный рабочий вариант — L4 (TCP) маршрутизация по SNI **без терминации**.

**Subpath (`/mtproto`) — невозможен.** MTProto работает на уровне TCP, не HTTP. Нет понятия "path".

```
                      Порт 443
                         |
                  [nginx stream / haproxy]
                  L4 TCP — ssl_preread / inspect
                         |
           ┌─────────────┴──────────────┐
           |                            |
  SNI = example.com              SNI пустой / неизвестный
                                 (iOS, Android, Desktop)
           |                            |
           ▼                            ▼
 [127.0.0.1:8443]              [127.0.0.1:2443]
   Nginx HTTPS                  MTProto Proxy
   (реальный сайт)             (FakeTLS)
```

## Проблема с SNI в Telegram-клиентах

**Критически важно:** Не все Telegram-клиенты отправляют SNI в FakeTLS:

| Клиент | SNI? | Статус (март 2026) | Примечание |
|---|---|---|---|
| **Android** | **ДА** | Работает | Всегда отправлял при корректных `ee`-секретах. Имеет fallback на старый алгоритм |
| **iOS** | **НЕСТАБИЛЬНО** | Регрессия 12.2+ | Issue #1912 открыт. Часть юзеров 12.4.x видит SNI, часть нет |
| **Desktop** | **ДА** | Работает (с 6.3) | Новый алгоритм ClientHello. Требует обновлённый прокси-сервер |

**Причина путаницы:** Desktop 6.3 (ноябрь 2025) обновил алгоритм TLS handshake — старые прокси (mtg v1, старые MTProxy) не понимали новый формат. Это выглядело как "Desktop не шлёт SNI", но на самом деле проблема была в несовместимости протокола.

**Вывод:** MTProxy должен быть **default backend** (для пустого/неизвестного SNI), потому что iOS нестабильно отправляет SNI. Сайт маршрутизируется по конкретному SNI.

## Nginx Stream (рекомендуемый)

```nginx
# /etc/nginx/nginx.conf

user www-data;
worker_processes auto;

events {
    worker_connections 4096;
}

# ============ STREAM: L4 маршрутизатор ============
stream {
    log_format stream_log '$remote_addr [$time_local] '
                          'sni="$ssl_preread_server_name" '
                          'upstream=$upstream_addr';
    access_log /var/log/nginx/stream.log stream_log;

    map $ssl_preread_server_name $backend {
        example.com         web_backend;
        www.example.com     web_backend;
        # Добавьте поддомены при необходимости

        default             mtproto_backend;   # ← ВСЁ остальное → MTProxy
    }

    upstream mtproto_backend {
        server 127.0.0.1:2443;
    }

    upstream web_backend {
        server 127.0.0.1:8443;
    }

    server {
        listen 443;
        listen [::]:443;
        ssl_preread on;
        proxy_pass $backend;
        proxy_connect_timeout 10s;
        proxy_timeout 300s;
        proxy_buffer_size 16k;   # Для длинных ClientHello
    }
}

# ============ HTTP: реальный сайт ============
http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    # Порт 80: ACME challenge + редирект
    server {
        listen 80;
        listen [::]:80;
        server_name example.com www.example.com;

        location ^~ /.well-known/acme-challenge/ {
            root /var/www/letsencrypt;
        }

        location / {
            return 301 https://$host$request_uri;
        }
    }

    # Порт 8443: HTTPS (получает трафик от stream)
    server {
        listen 127.0.0.1:8443 ssl;
        server_name example.com www.example.com;

        ssl_certificate     /etc/letsencrypt/live/example.com/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;

        root /var/www/example.com;
        index index.html;
    }
}
```

## HAProxy (альтернатива)

```haproxy
# /etc/haproxy/haproxy.cfg

global
    log /dev/log local0
    maxconn 50000
    daemon

defaults
    log global
    timeout connect 10s
    timeout client 300s
    timeout server 300s

frontend ft_ssl
    bind *:443
    mode tcp
    tcp-request inspect-delay 5s
    tcp-request content accept if { req_ssl_hello_type 1 }

    use_backend bk_web if { req.ssl_sni -i example.com }
    use_backend bk_web if { req.ssl_sni -i www.example.com }

    default_backend bk_mtproto

backend bk_mtproto
    mode tcp
    server mtproto 127.0.0.1:2443 check

backend bk_web
    mode tcp
    server web 127.0.0.1:8443 check
```

## Let's Encrypt с stream блоком

Порт 443 занят stream — certbot `--nginx` не работает.

### Решение 1: Webroot через порт 80 (рекомендуемое)

```bash
mkdir -p /var/www/letsencrypt/.well-known/acme-challenge

certbot certonly \
    --webroot \
    -w /var/www/letsencrypt \
    -d example.com \
    -d www.example.com \
    --agree-tos \
    --non-interactive
```

### Решение 2: DNS challenge (Cloudflare)

```bash
apt install python3-certbot-dns-cloudflare

# /etc/letsencrypt/cloudflare.ini:
# dns_cloudflare_api_token = YOUR_TOKEN
chmod 600 /etc/letsencrypt/cloudflare.ini

certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
    -d "example.com" \
    -d "*.example.com"
```

### Автообновление

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
#!/bin/bash
nginx -t 2>/dev/null && systemctl reload nginx
```

```bash
chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
certbot renew --dry-run   # проверка
```

## Проверка маршрутизации

```bash
# Должен показать сертификат вашего сайта
openssl s_client -connect IP:443 -servername example.com </dev/null 2>/dev/null | head -5

# Без SNI — должен попасть в MTProxy
openssl s_client -connect IP:443 -noservername </dev/null 2>/dev/null | head -5

# Логи
tail -f /var/log/nginx/stream.log
```

## Важно

1. `$ssl_preread_protocol` **бесполезен** — FakeTLS тоже показывает TLSv1.3
2. Маршрутизация **только по SNI** (`$ssl_preread_server_name`)
3. **Caddy не подходит** — нет stream модуля
4. **Proxy Protocol** нужен для передачи реального IP клиента в бэкенд

# Telemt (Rust) — установка и настройка

**Репо:** https://github.com/telemt/telemt
**Язык:** Rust + Tokio | **Версия:** 3.3.17 | **Лицензия:** GPL-3.0

Лучший выбор для Telegram-бота: REST API для управления пользователями, per-user лимиты, TCP Splice маскировка.

## Быстрая установка (Docker)

### 1. Генерация секрета

```bash
openssl rand -hex 16
# Пример: a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6
```

### 2. Создание конфига `telemt.toml`

```toml
[general]
use_middle_proxy = true
log_level = "normal"

[general.modes]
classic = false
secure = false
tls = true

[server]
port = 443

[server.api]
enabled = true
listen = "127.0.0.1:9091"
whitelist = ["127.0.0.0/8"]
# auth_header = "my-secret-token"  # опционально

# [server.metrics]
# metrics_port = 9090  # Prometheus, выключено по умолчанию

[[server.listeners]]
ip = "0.0.0.0"

[censorship]
tls_domain = "petrovich.ru"    # Домен для маскировки (см. 08-best-practices.md)
mask = true
tls_emulation = true

[access.users]
user1 = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
```

### 3. Docker Compose (`docker-compose.yml`)

```yaml
services:
  telemt:
    image: whn0thacked/telemt-docker:latest
    container_name: telemt
    restart: unless-stopped
    network_mode: host
    environment:
      RUST_LOG: "info"
    volumes:
      - ./telemt.toml:/etc/telemt.toml:ro
    security_opt:
      - no-new-privileges:true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:rw,nosuid,nodev,noexec,size=16m
    deploy:
      resources:
        limits:
          cpus: "0.50"
          memory: 256M
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

### 4. Запуск

```bash
docker compose up -d
docker compose logs -f
```

## Установка без Docker (бинарник)

```bash
# Скачать бинарник
wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-$(uname -m)-unknown-linux-gnu.tar.gz" | tar xz
sudo mv telemt /bin/telemt
sudo chmod +x /bin/telemt

# Создать пользователя
sudo useradd -d /opt/telemt -m -r -U telemt

# Systemd сервис
sudo tee /etc/systemd/system/telemt.service << 'EOF'
[Unit]
Description=Telemt MTProxy
After=network.target

[Service]
Type=simple
User=telemt
ExecStart=/bin/telemt /etc/telemt/telemt.toml
LimitNOFILE=65536
Restart=on-failure
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now telemt
```

## REST API

Порт `9091`, JSON, префикс `/v1`.

### Управление пользователями

```bash
# Создать пользователя (секрет генерируется автоматически)
curl -X POST http://127.0.0.1:9091/v1/users \
  -H "Content-Type: application/json" \
  -d '{"username":"user_123456"}'

# Создать с expiration и лимитами
curl -X POST http://127.0.0.1:9091/v1/users \
  -H "Content-Type: application/json" \
  -d '{
    "username": "user_123456",
    "expiration_rfc3339": "2026-04-14T00:00:00Z",
    "max_tcp_conns": 10,
    "max_unique_ips": 3,
    "data_quota_bytes": 10737418240
  }'

# Список пользователей (включает готовые tg://proxy ссылки!)
curl http://127.0.0.1:9091/v1/users | jq

# Информация о конкретном пользователе
curl http://127.0.0.1:9091/v1/users/user_123456

# Изменить лимиты
curl -X PATCH http://127.0.0.1:9091/v1/users/user_123456 \
  -H "Content-Type: application/json" \
  -d '{"expiration_rfc3339": "2026-05-01T00:00:00Z"}'

# Удалить пользователя
curl -X DELETE http://127.0.0.1:9091/v1/users/user_123456
```

### Поля при создании/обновлении

| Поле | Тип | Обязательное | Описание |
|------|-----|---|---|
| `username` | string | Да | `[A-Za-z0-9_.-]`, 1-64 символа |
| `secret` | string | Нет | 32 hex. Автогенерация если не указан |
| `expiration_rfc3339` | string | Нет | Срок действия (ISO 8601) |
| `data_quota_bytes` | u64 | Нет | Квота трафика в байтах |
| `max_tcp_conns` | usize | Нет | Макс. одновременных TCP |
| `max_unique_ips` | usize | Нет | Макс. уникальных IP |
| `user_ad_tag` | string | Нет | 32 hex, рекламный тег |

### Ответ содержит готовые ссылки

```json
{
  "links": {
    "tls": ["tg://proxy?server=1.2.3.4&port=443&secret=ee..."],
    "secure": ["tg://proxy?server=1.2.3.4&port=443&secret=dd..."],
    "classic": ["tg://proxy?server=1.2.3.4&port=443&secret=..."]
  }
}
```

### Другие эндпоинты

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/v1/health` | Здоровье сервиса |
| GET | `/v1/system/info` | Информация о системе |
| GET | `/v1/stats/summary` | Статистика |
| GET | `/v1/stats/users` | Статистика по пользователям |

### Аутентификация

1. **IP whitelist** — `whitelist` в `[server.api]`, CIDR формат. По умолчанию `127.0.0.1/32`
2. **Auth header** — `auth_header` в `[server.api]`, exact string match

### Ограничения

- `DELETE` последнего пользователя → `409 last_user_forbidden`
- `POST /v1/users/{name}/rotate-secret` → `404` (баг, не реализован в текущей версии)
- Утечка памяти в draining writers (issue #390, не исправлено в 3.3.17) — мониторьте RSS, рестартуйте при необходимости

## TCP Splice — маскировка

Когда к серверу подключается НЕ клиент Telegram (DPI-зонд, браузер):
1. Telemt определяет что это не MTProxy handshake
2. Устанавливает TCP-соединение с реальным сервером `tls_domain`
3. Прозрачно сплайсит TCP-потоки
4. Клиент получает **настоящий сертификат и контент** реального сайта

Нет MITM, нет поддельных сертификатов. DPI не может отличить от реального HTTPS.

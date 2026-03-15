# Best Practices — домен, VPS, безопасность

## 1. Выбор домена маскировки

### Критически важно: тот же ASN

DPI проверяет соответствие SNI и IP:
```
ПЛОХО:  VPS IP = 167.235.x.x (Hetzner, AS24940)
        SNI = www.google.com (AS15169)
        → ASN не совпадают → подозрительно!

ХОРОШО: VPS IP = 167.235.x.x (Hetzner, AS24940)
        SNI = some-site.de (тоже Hetzner, AS24940)
        → один ASN → нормально, shared hosting
```

### RealiTLScanner — подбор домена

Инструмент от XTLS для поиска доменов-соседей на тех же IP.

```bash
# Установка (нужен Go 1.21+)
git clone https://github.com/XTLS/RealiTLScanner.git
cd RealiTLScanner && go build

# Запускать С ЛОКАЛЬНОЙ МАШИНЫ, не с VPS!
# (Массовое сканирование с VPS → abuse reports → блокировка)

# Сканирование подсети вашего VPS
./RealiTLScanner -addr YOUR_VPS_SUBNET/24 -port 443 -thread 10 -out neighbors.csv

# Вывод CSV: IP, ORIGIN, CERT_DOMAIN, CERT_ISSUER, GEO_CODE
```

### Проверка кандидата

```bash
# TLS 1.3 + HTTP/2 (обязательно)
curl -I --tlsv1.3 --http2 https://candidate-domain.com

# Не редиректит (200, не 301/302)
curl -sI https://candidate-domain.com | head -5

# Тот же ASN
whois $(dig +short candidate-domain.com) | grep -i origin
```

### Хорошие домены

- Корпоративные сайты на том же хостере
- Зеркала Linux-дистрибутивов
- Инфраструктурные сервисы (CDN-узлы)
- Российские коммерческие сайты (для российского VPS): 1c.ru, wildberries.ru

### Плохие домены

- `google.com`, `microsoft.com` — другой ASN
- `example.com` — зарезервированный, подозрительный
- `*.gov.ru` — привлекает внимание
- Тот же домен что у всех (маркер)
- Личные блоги (мало трафика, легко профилировать)

## 2. Выбор VPS

### Российский vs зарубежный

| | Российский VPS | Зарубежный VPS |
|---|---|---|
| DPI на участке "юзер → прокси" | Минимальная | Максимальная (граница) |
| Задержка | 5-20 мс | 50-150 мс |
| Юридический риск | Высокий (РКН может отключить) | Низкий |
| Цена | от 80-250 руб/мес | от $3-5/мес |

**Рекомендация:** Российский VPS для максимальной скорости, но с пониманием юридических рисков. С 1 марта 2026 РКН расширил контроль над магистральным трафиком — преимущество внутреннего трафика уменьшается.

**ntc.party** ведёт [список хостеров за ТСПУ](https://ntc.party/t/хостинги-подключенные-к-тспуdpi/4473) — проверяйте перед покупкой.

### Юридические риски (РФ)

- Использование VPN/прокси физлицами — **не запрещено**
- Реклама средств обхода блокировок — штраф до 500к руб (с сент 2025)
- Хостер обязан сотрудничать с РКН — сервер могут отключить

### Минимальные требования

- 1 CPU, 512 MB RAM, Linux (Ubuntu/Debian)
- Порт 443 свободен
- Docker (для контейнерного деплоя)

### Рекомендуемые провайдеры

**Российские:** Aeza, VDSina, Timeweb, AdminVPS
**Зарубежные:** Low End Box ($1-2/мес), Амстердам/Финляндия для низкой задержки

## 3. Безопасность

### Docker hardening

```yaml
security_opt:
  - no-new-privileges:true
cap_drop:
  - ALL
cap_add:
  - NET_BIND_SERVICE
read_only: true
tmpfs:
  - /tmp:nosuid,nodev,noexec
```

### Firewall

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp      # SSH
ufw allow 443/tcp     # MTProxy
ufw enable
```

### Systemd hardening (без Docker)

```ini
[Service]
ProtectHome=true
ProtectKernelTunables=true
DynamicUser=yes
ProtectSystem=full
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
LimitNOFILE=65536
```

## 4. Сколько пользователей на сервер?

| Конфигурация | Пользователей |
|---|---|
| 1 CPU, 512 MB | ~500-1000 |
| 1 CPU, 1 GB | ~4000 |
| 4 CPU, 8 GB | ~90k conn (Erlang) |

**Важно:** Чем больше пользователей — тем выше вероятность обнаружения по паттернам трафика. Рекомендация автора mtprotoproxy: **"Много прокси с малым числом пользователей"** (< 10 на сервер для максимальной скрытности).

## 5. Чеклист деплоя

1. ☐ Выбрать VPS (российский для РФ-пользователей)
2. ☐ Установить Docker
3. ☐ Сканировать соседей RealiTLScanner (с локальной машины!)
4. ☐ Выбрать домен маскировки (тот же ASN)
5. ☐ Сгенерировать секрет (`openssl rand -hex 16`)
6. ☐ Настроить telemt.toml / mtg config.toml
7. ☐ Развернуть через docker-compose
8. ☐ Настроить firewall (22 + 443)
9. ☐ Проверить маскировку (`curl`, `openssl s_client`)
10. ☐ Получить ссылку `tg://proxy?...`
11. ☐ **Не распространять ссылку публично**
12. ☐ Настроить мониторинг

# MTG (Go) — установка и настройка

**Репо:** https://github.com/9seconds/mtg
**Язык:** Go | **Версия:** 2.1.13 | **Лицензия:** MIT

Лучший выбор для максимального обхода DPI: Doppelganger, domain fronting, anti-replay. Но **1 секрет на инстанс** — не подходит для per-user управления.

## Особенности

- **Только FakeTLS** — Classic и Secure убраны в v2
- **Один секрет = один инстанс** — осознанное решение автора
- **Нет Ad Tag** — убрано в v2
- **Нет REST API** — управление только через TOML конфиг
- **Doppelganger** — статистическая мимикрия TLS (только в master, планируется v2.2)
- **Domain fronting** — байт-идентичные ответы реального сайта при зондировании
- Перерыв 3.5 года (авг 2022 → фев 2026), сейчас очень активен

## Быстрая установка (Docker)

```bash
# 1. Генерация секрета (выбирайте домен на том же ASN что и VPS!)
docker run --rm nineseconds/mtg:2 generate-secret --hex storage.googleapis.com

# 2. Создание конфига config.toml
cat > config.toml << 'EOF'
secret = "ee<ваш_секрет_из_шага_1>"
bind-to = "0.0.0.0:3128"

[defense.anti-replay]
enabled = true
max-size = "1mib"

[defense.blocklist]
enabled = true
urls = ["https://iplists.firehol.org/files/firehol_level1.netset"]
update-each = "24h"

# Doppelganger (только на master, не в v2.1.13!)
# [defense.doppelganger]
# urls = ["https://example.com/index.html", "https://example.com/about.html"]
# repeats-per-raid = 10
# raid-each = "6h"
EOF

# 3. Запуск
docker run -d \
  -v $(pwd)/config.toml:/config.toml \
  -p 443:3128 \
  --name mtg-proxy \
  --restart=unless-stopped \
  nineseconds/mtg:2

# 4. Получить ссылку для клиентов
docker exec mtg-proxy /mtg access /config.toml
```

## Установка с systemd

```bash
# Установить Go и собрать
go install github.com/9seconds/mtg/v2@latest

# Генерация секрета
mtg generate-secret --hex your-domain.com

# Конфиг /etc/mtg.toml (аналогично Docker)

# Systemd юнит
sudo tee /etc/systemd/system/mtg.service << 'EOF'
[Unit]
Description=mtg MTProto proxy
After=network.target

[Service]
ExecStart=/usr/local/bin/mtg run /etc/mtg.toml
Restart=always
RestartSec=3
DynamicUser=true
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mtg
```

## Doppelganger — уникальная фича

**Статус:** Замержено в master 12-14 марта 2026. Планируется в v2.2. В v2.1.13 **отсутствует**.

**Что делает:** Имитирует статистические характеристики TLS-соединений реального сайта — размеры TLS-записей, задержки, паттерны чанкинга. Для DPI трафик статистически неотличим от реального HTTPS.

**Как работает:**
1. mtg периодически обращается к указанным URL (2-3 страницы сайта)
2. Собирает статистику по размерам TLS-записей и задержкам
3. Искусственно эмулирует эти характеристики в MTProxy-трафике

**Дефолты (ok.ru):** mtg поставляется с предсобранной статистикой ok.ru. Работает из коробки без настройки.

```toml
[defense.doppelganger]
urls = [
  "https://lalala.com/index.html",
  "https://lalala.com/contacts.html",
]
repeats-per-raid = 10
raid-each = "6h"
drs = false   # Dynamic TLS Record Sizing (Cloudflare, Go, Caddy)
```

**Рекомендации:**
- 2-3 URL с того же домена, что и для fronting
- Смешивайте лёгкие (HTML) и тяжёлые (изображения) страницы
- Не используйте ok.ru если ваш VPS не в российском ASN

## Domain Fronting

При невалидном MTProxy-запросе mtg **не разрывает соединение**, а:
1. Подключается к реальному сайту (домен из секрета)
2. Проксирует всё что отправил клиент на реальный сайт
3. Возвращает **байт-в-байт идентичный** ответ

DPI при active probing получает настоящий ответ от легитимного сайта.

## Мониторинг

Встроенная поддержка (из коробки):
- **Prometheus** — `/metrics` endpoint
- **StatsD** — push metrics
- Метрики: соединения, трафик, replay-атаки, blocklist hits, domain fronting events

```toml
[stats.prometheus]
bind-to = "127.0.0.1:3129"

# или StatsD
# [stats.statsd]
# address = "127.0.0.1:8125"
```

## Использование с ботом

mtg НЕ подходит для per-user ключей. Варианты:

1. **Один общий секрет** — все пользователи бота получают одну ссылку. Нельзя отзывать доступ индивидуально.
2. **Ротация секрета** — раз в сутки менять секрет, бот выдаёт новый только активным подписчикам.
3. **Fallback для stealth** — mtg как вторичный прокси для регионов с жёстким DPI, основной — telemt.

## Скорость

**Известная проблема:** mtg ~5x медленнее официального MTProxy (issue #220: 1 MB/s vs 5 MB/s). Для Telegram это обычно не критично (сообщения, фото, небольшие видео), но для загрузки больших файлов может быть заметно.

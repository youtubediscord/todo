# 5 независимых реализаций MTProto Proxy

Все пять проектов — **полностью разный код**, написанный с нуля на разных языках. Реализуют один и тот же протокол MTProto Proxy.

## Сводная таблица

| | **telemt** | **mtg** | **mtprotoproxy** | **mtproto_proxy** | **mtproto.zig** |
|---|---|---|---|---|---|
| **Язык** | Rust + Tokio | Go | Python (asyncio) | Erlang/OTP | Zig (без GC, пре-аллокация) |
| **Репо** | telemt/telemt | 9seconds/mtg | alexbers/mtprotoproxy | seriyps/mtproto_proxy | sleep3r/mtproto.zig |
| **Версия** | 3.4.15 (июнь 2026) | 2.1.13 (фев 2026) | v1.1.1 (май 2022, коммиты до 2026) | 0.7.4 (фев 2026) | 1.0.1 (июнь 2026) |
| **Лицензия** | — | MIT | MIT | Apache 2.0 | MIT |
| **REST API** | Полный CRUD `/v1/users` | Нет | Нет | Нет | Нет (CLI `mtbuddy`) |
| **Мультиюзер** | Да + per-user лимиты | 1 секрет = 1 инстанс | Да (config.py) | Да (sys.config) | Да + per-user секреты/лимиты |
| **Hot-reload** | API (без рестарта) | Нельзя | SIGUSR2 | systemctl reload | SIGHUP (юзеры+конфиг; запрещён при workers>1) |
| **Маскировка при зондах** | TCP Splice → реальный сайт | Domain Fronting (байт-идентичный) | Редирект на TLS_DOMAIN | Ничего (закрывает conn) | `mask` → реальный домен + nginx decoy (реальный серт) |
| **Traffic mimicry** | Нет | Doppelganger (только в master, не в релизе) | Нет | Нет | DRS + ServerHello desync (частично) |
| **SOCKS5 upstream** | Да (+SOCKS4) | Да | Да | Нет | Да (+HTTP CONNECT, +WG/AmneziaWG туннель) |
| **Proxy Protocol** | Да | v1/v2 | v1/v2 | Нет | Нет (есть `public_port` для HAProxy/Nginx) |
| **Prometheus** | Да (порт 9090, выкл. по умолч.) | Да (из коробки) | Да | Да | Да (выкл. по умолч.) |
| **Ad Tag** | Per-user (через API) | Нет (убрано в v2) | Общий | Общий | Общий (`tag` / `ad_tag`) |
| **Anti-replay** | Sliding window | Stable Bloom filter | OrderedDict FIFO | ETS-таблицы | Хеш-таблица, TTL 60 мин |
| **Производительность** | ~5-15k conn/1CPU | ~10-20k conn | ~4k юзеров/1CPU | 90k conn/4CPU | SO_REUSEPORT мультиворкер, пре-аллокация |
| **Memory leak** | Да (#390, не исправлен) | Исторические OOM — исправлены | Пул соединений (#298) | 100% CPU (#104) | Нет известных |

### Уникальное у `mtproto.zig`: обход DPI «под ключ»

Остальные четыре — это **только прокси**: обход DPI на уровне ОС (дробление пакетов, zapret) настраиваешь сам, отдельно. `mtproto.zig` через `mtbuddy install` ставит это автоматически:

| Техника | telemt | mtg | mtprotoproxy | mtproto_proxy | mtproto.zig |
|---|---|---|---|---|---|
| **TCPMSS-дробление ClientHello** | сам | сам | сам | сам | **ставит сам** (`--tcpmss 88`) |
| **nfqws TCP desync (zapret)** | сам | сам | сам | сам | **ставит сам** (`mtbuddy nfqws`) |
| **IPv6-hopping при бане** | Нет | Нет | Нет | Нет | **Да** (`--ipv6-hop`) |
| **VPN-туннель upstream (WG/AmneziaWG)** | Нет | Нет | Нет | Нет | **Да** (`type = "tunnel"`) |

Подробный разбор техник и настроек — в [[mtproxy/mtproto-zig|MTProxy и mtproto.zig: как пережить ТСПУ]].

## Какой выбрать?

### Для Telegram-бота с per-user ключами → **telemt**

Единственный с REST API. Создание/удаление юзеров без SSH и рестартов:
```bash
curl -X POST http://127.0.0.1:9091/v1/users \
  -d '{"username":"user_123", "expiration_rfc3339":"2026-04-14T00:00:00Z"}'
```

### Для максимального обхода DPI → **mtg**

Doppelganger (в master, планируется v2.2) имитирует статистические характеристики TLS-трафика реального сайта — размеры записей, тайминги. Уникальная фича.

### Для простоты → **mtprotoproxy**

Один файл Python (~2400 строк), минимум зависимостей. Работает без pip-пакетов.

### Для высоких нагрузок → **mtproto_proxy** (Erlang)

90k соединений / 1 Gbps на 4 ядрах. Erlang OTP супервизоры — краш одного соединения не роняет сервер.

### Для обхода DPI «под ключ» → **mtproto.zig** (Zig)

Единственный, кто **сам** ставит OS-level обход (TCPMSS-дробление + zapret/nfqws desync), маскировку nginx и IPv6-hopping — одной командой `mtbuddy install`, без ручной возни с iptables. Плюс статический бинарь без зависимостей и без GC. Если нужен «поставил и работает» против ТСПУ — это он. Разбор: [[mtproxy/mtproto-zig|MTProxy и mtproto.zig]].

## Обёртки (НЕ отдельные проекты)

Эти проекты — скрипты/Dockerfile вокруг **telemt**. Свой код не содержат:

| Обёртка | Что делает |
|---|---|
| An0nX/telemt-docker | Docker build telemt (distroless, ~3.75 MB) |
| itcaat/mtproto-installer | curl\|bash установщик telemt + Traefik |
| nolaxe/install-MTProxy | Bash-менеджер (install/uninstall/status) |

Если нужен telemt — ставьте telemt напрямую.

## Официальный TelegramMessenger/MTProxy

- Язык: C, GPLv2
- Поддерживает все 3 режима (Classic, dd, FakeTLS через `-D`)
- Фактически заброшен (README не обновлялся с 2018, последний фикс — ноябрь 2025)
- Лимит 16 секретов (хардкод, нужен патч для увеличения)
- Нет Docker, нет API
- **Не рекомендуется** — используйте telemt или mtg

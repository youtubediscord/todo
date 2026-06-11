---
date: 2026-06-07
tags:
  - mtproto
  - mtproxy
  - mtproto-zig
  - setup
  - dpi
  - tspu
aliases:
  - Настройка mtproto.zig
  - mtproto.zig setup
  - MTProxy runbook
link: https://github.com/sleep3r/mtproto.zig
---

# 🛠️ Настройка MTProxy на mtproto.zig — пошагово и «что происходит на проводе»

> [!info] Что это и для кого
> Практический **runbook**: как поднять MTProxy на [[mtproxy/mtproto-zig|mtproto.zig]] и **понимать, что делает каждый слой защиты** — с учётом свежих наблюдений (протухший фингерпринт клиента из [tdesktop#30733](https://github.com/telegramdesktop/tdesktop/issues/30733), детект по `expected_64_got_0`, приёмы TCPMSS и SYN-ACK).
>
> Теория и «почему» — в обзорной статье [[mtproxy/mtproto-zig|MTProxy и mtproto.zig]]. Здесь — команды, конфиг и диагностика.

> [!tip] Почему mtproto.zig, а не telemt
> Оба — хорошие FakeTLS-прокси. `mtproto.zig` берут, когда нужен **обход DPI «под ключ»**: он сам ставит TCPMSS-дробление + nfqws-desync + nginx-маскировку одной командой, без ручного iptables. telemt — когда нужен REST API для бота ([[Zapret/mtproto/02-implementations|сравнение]]).

---

## Шаг 0. Подготовка

| Что | Как и почему |
|---|---|
| **VPS / подсеть** | Не «народный» хостинг (Selectel/Я.Облако — Сигнал 1 [[VLESS/dpi-tls-june-2026|сибирской схемы]]). Подбор — [[VPS/VPS\|VPS]]. |
| **Домен маскировки** | Популярный, с **одним раундом x25519**: `rutube.ru`, `ozon.ru`, `vk.com`, `yandex.ru`. **НЕ** `wb.ru` и др. HRR/secp521r1. |
| **Порт** | `443`. Любой другой подозрителен. |
| **Доступ** | root/sudo на сервере. |

> ⚠️ Домен вшивается в ссылку `tg://` и **неизменен** после раздачи. Выбирай один раз.

---

## Шаг 1. Установка

```bash
# 1. bootstrap mtbuddy (проверяет minisign-подпись + SHA-256)
curl -fsSL https://raw.githubusercontent.com/sleep3r/mtproto.zig/main/deploy/bootstrap.sh | sudo bash

# 2. установка прокси со всеми DPI-модулями
sudo mtbuddy install --port 443 --domain rutube.ru --yes
```

Что делает install (`--no-dpi` отключает п.5–6):

1. Качает готовый бинарь (определяет CPU: `x86_64_v3` → `x86_64` → `aarch64`)
2. Генерит секрет (или `--secret <32hex>`)
3. systemd-сервис `mtproto-proxy`
4. Открывает порт в `ufw`
5. **TCPMSS=88** iptables (дробит ClientHello) ← см. Шаг 4
6. **nginx-маскировка + nfqws-desync** ← см. Шаг 5
7. Печатает `tg://`-ссылку

Полезные флаги: `--secret`, `--user`, `--tcpmss <n>` (дефолт 88), `--no-tcpmss`, `--no-nfqws`, `--no-masking`, `--ipv6-hop`.

---

## Шаг 2. Конфиг `config.toml`

Большинство — уже дефолты; фиксируем ключевое явно (`/opt/mtproto-proxy/config.toml`):

```toml
[general]
use_middle_proxy = true        # медиа на не-Premium + promo-теги

[server]
port = 443
# rate_limit_per_subnet = 0    # ОСТАВЬ 0 для мобильных юзеров РФ (carrier-NAT)

[censorship]
tls_domain = "rutube.ru"       # single-round x25519, неизменен после раздачи
mask = true                    # форвард зондов на реальный домен (анти-probing)
fake_tls_only = true           # реджектить палевный dd-транспорт
# desync = true                # дефолт on — дробит ServerHello (1 байт + 3мс)
drs = true                     # мимикрия размеров TLS-записей под браузер
fast_mode = true

[metrics]
enabled = true                 # Prometheus /metrics (см. Шаг 6 — диагностика)
host = "127.0.0.1"
port = 9400

[access.users]
user1 = "00112233445566778899aabbccddeeff"   # openssl rand -hex 16
```

После правки: `sudo systemctl restart mtproto-proxy` (SIGHUP-reload тоже есть, но при `workers>1` запрещён).

---

## Шаг 3. Что происходит на проводе (карта защит)

```
КЛИЕНТ (Telegram)                    ТСПУ                    СЕРВЕР (mtproto.zig)
   │  ── ClientHello (почерк!) ──────► 👁 фингерпринт ──────►  снимает fp в лог
   │                                   │ (тут и блок #30733)
   │  ◄──────────── ServerHello (дроблён desync) ────────────  mask/desync/drs
   │  ── 64-байт MTProto-хендшейк ───► (если жив) ───────────►  proxy → DC
```

| Слой | Что делает | Против чего |
|---|---|---|
| **TCPMSS=88** | клиент режет ClientHello на ~6 кусков | фингерпринт (DPI не пересобирает) |
| **nfqws desync** | fake-пакеты + TTL-split (S→C) | stateful DPI |
| **desync ServerHello** | 1 байт + 3мс + хвост | пассивные сигнатуры |
| **mask** | зонды → реальный `tls_domain` | active probing |
| **drs** | размеры записей как у браузера | статистика трафика |

> [!danger] Слабое звено, которое сервер НЕ чинит — фингерпринт клиента
> Почерк ClientHello (JA3/JA4) генерирует **приложение Telegram**, не сервер. По [tdesktop#30733](https://github.com/telegramdesktop/tdesktop/issues/30733): Desktop мимикрирует под **Chrome 134/macOS** (`t13d1516h2_8daaf6152771_d8a2da3f94cd`), а живой Chrome — 148 → пресет **протух**, и это маркер. Это **тот самый** блок, дающий `expected_64_got_0` ([[Zapret/mtproto/10-telemt-logs-dpi|разбор логов]]).
>
> Лечится только в самом Telegram. Всё, что может сервер — **спрятать/сломать опознание** этого почерка (TCPMSS, desync), а не поправить его. Поэтому Шаги 4–6 важны.

---

## Шаг 4. TCPMSS — дробление ClientHello

### Как работает

Сервер анонсирует в `SYN-ACK` малый **MSS**, и клиент вынужден резать всё исходящее (включая ClientHello ~517 байт) на мелкие сегменты. DPI без потоковой пересборки не складывает почерк целиком → не матчит сигнатуру.

В `mtproto.zig` включено по умолчанию (`TCPMSS=88`). Сменить значение: `mtbuddy install --tcpmss 96`.

### Вариант «через балансировщик» — помогает?

> **Да, помогает.** Это тот же механизм. Если перед прокси стоит балансировщик (он терминирует клиентский TCP), MSS-clamp надо вешать **именно на балансировщик** — там рождается SYN-ACK к клиенту:
>
> ```bash
> iptables -t mangle -A OUTPUT -p tcp --sport 443 \
>   --tcp-flags SYN,ACK SYN,ACK -j TCPMSS --set-mss 96
> ```
>
> Конфиг telemt/mtproto.zig при этом трогать не надо — правило работает на уровне ядра.

Почему «на балансировщике»: clamp на бэкенде (где сидит сам прокси) **не дойдёт** до клиента, если балансировщик пере-устанавливает TCP. Правило должно быть на той коробке, что шлёт SYN-ACK клиенту.

> [!note] 88 или 96 — разница невелика
> Оба дают ~6 сегментов на ClientHello. mtproto.zig по умолчанию 88; совет из интернета — 96. Бери любое; если ставишь mtproto.zig напрямую (без отдельного балансировщика) — **TCPMSS уже стоит, дублировать руками не нужно**.

> [!tip] Это и есть «решение JA4» из teleproxy
> Когда говорят «в teleproxy решён JA4» — речь именно об этой фрагментации: teleproxy
> ставит `TCP_MAXSEG=256`, чтобы DPI не извлёк JA4 из первого пакета. JA4 при этом
> **не меняется** (его задаёт клиент). mtproto.zig делает то же самое и агрессивнее
> (MSS=88), так что **этот приём у тебя уже включён**. Почему это не «смена почерка»
> и где лежит настоящий фикс — [[mtproxy/ja4-sni-client-side|Кто может менять JA4/SNI]].

> [!warning] Дробление ≠ панацея
> MSS-clamp бьёт по DPI, который **не пересобирает** поток. Если ТСПУ делает реассемблинг — одного дробления мало, нужен **desync** (nfqws, Шаг 5), который активно ломает пересборку fake-пакетами. Поэтому их ставят вместе.

---

## Шаг 5. nfqws TCP desync + тюнинг TTL

Ставится при install. Стратегия: `--dpi-desync=fake,split2 --dpi-desync-ttl=6 --dpi-desync-fooling=md5sig` — fake-пакет с заниженным TTL (долетает до ТСПУ, умирает до клиента) + битая MD5-опция, чтобы сбить state-машину DPI.

**TTL надо подтюнить под маршрут** (дефолт 6 не универсален, «4–8 для росс. ISP»):

```bash
traceroute <ip_клиента_или_DC>     # прикинуть хоп, где сидит ТСПУ
sudo mtbuddy nfqws --ttl 7         # переставить
systemctl status nfqws-mtproto     # проверить, что запущен
```

TTL должен быть **больше** расстояния до ТСПУ, но **меньше** расстояния до клиента.

---

## Шаг 5.5 (опционально). Egress через Xray/SOCKS5 или туннель

Это аналог `SOCKS5_PROXY` + `DIRECT_MODE` из конфигов teleproxy: маршрут
**исходящего** трафика прокси к дата-центрам Telegram через Xray/VLESS (SOCKS5)
или WireGuard/AmneziaWG-туннель.

```toml
[upstream]
type = "socks5"            # "direct" | "tunnel" | "socks5" | "http"

[upstream.socks5]
host = "127.0.0.1"
port = 1080               # порт локального Xray/VLESS
# username = ""
# password = ""
```

Для туннеля вместо SOCKS5:

```toml
[upstream]
type = "tunnel"
[upstream.tunnel]
interfaces = ["awg0", "awg1"]   # WireGuard/AmneziaWG, с авто-фолбэком
```

> [!important] Что это лечит, а что нет
> Egress-маршрут помогает, когда **дата-центры Telegram недоступны с твоего VPS**
> (заблокированы/режутся на пути proxy→DC), или нужен лишний хоп. Это путь
> **сервер→DC** — на **входящий** ClientHello (где JA4, который видит ТСПУ у
> клиента) он **не влияет**. Не путай: это про доступность DC, а не про обход
> детекта почерка. См. [[mtproxy/ja4-sni-client-side|Кто может менять JA4/SNI]].

---

## Шаг 6 (опционально). Лимит SYN-ACK — десинхрон + анти-залп

**На пальцах:** сервер иногда «роняет» свой ответ при установке соединения (SYN-ACK), клиент переспрашивает через секунду. От этого DPI сбивается со счёта и не опознаёт почерк клиента, а соединения идут не пачкой, а по одному в секунду. Спорный, но у людей **рабочий** приём.

Подробная механика (с аналогией), цена и **per-port** вариант (бюджет 1/сек на каждый порт, чтобы не калечить всех юзеров) — в [[Zapret/mtproto/10-telemt-logs-dpi#Лимит SYN-ACK — помогает или нет|разборе для telemt]] (для mtproto.zig всё идентично, только порт 443).

Коротко: ставить стоит, если блок держится после Шагов 4–5; брать **сразу per-port**; мониторить логи (Шаг 7), чтобы поймать адаптацию ТСПУ.

---

## Шаг 7. Диагностика — mtproto.zig сам показывает атаку DPI

### Фингерпринт клиента в логах

mtproto.zig **логирует почерк первых 16 ClientHello** (диагностический бюджет):

```bash
journalctl -u mtproto-proxy | grep "client ClientHello"
# client ClientHello [ciphers=... groups=... key_share=...] (we serve: ...)
```

> [!tip] Как связать с #30733
> Смотри `key_share` в логе. Свежий браузер шлёт **`X25519MLKEM768`** (post-quantum). Если твой клиент его **не** шлёт — он на старом пресете и попадает под детект из #30733. Это прямой способ увидеть «протух ли почерк» на своём трафике.

### Метрики close-reason — детектор начала блокировок

mtproto.zig отдаёт Prometheus-метрику с причинами закрытия — её **всплеск = ТСПУ начал резать**:

```bash
curl -s 127.0.0.1:9400/metrics | grep -E "close_reason|handshake_timeouts"
# mtproto_connection_close_reason_total{reason="tls_validation_failed"} ...
# mtproto_connection_close_reason_total{reason="replay_detected"} ...      ← зонды Revisor
# mtproto_connection_close_reason_total{reason="bad_handshake"} ...
# mtproto_handshake_timeouts_total ...                                     ← аналог expected_64_got_0
```

Рост `tls_validation_failed` / `replay_detected` / `handshake_timeouts` над фоном — это и есть сигнал, что цензор начал работать по тебе (так и задумано разработчиком). `replay_detected` отдельно ловит **active-probe зонды ТСПУ (Revisor)**.

Плюс есть веб-дашборд (порт 61208, Basic-auth, токен в `/opt/mtproto-proxy/monitor/dashboard.token`) — открывать **только через SSH-тоннель**.

---

## Когда всё-таки заблокировали — порядок действий

1. **Проверь логи/метрики** (Шаг 7): растёт ли `handshake_timeouts` / `tls_validation_failed`, и какой `key_share` у падающих клиентов.
2. **Подтюнь TTL nfqws** (Шаг 5) — частая причина, что desync «не достаёт» до ТСПУ.
3. **Снизь MSS** (`--tcpmss 80`) или добавь clamp на балансировщик (Шаг 4).
4. **Включи SYN-ACK per-port** (Шаг 6).
5. **Если рвётся путь до DC** (а не вход) — egress через Xray/SOCKS5 или туннель (Шаг 5.5).
6. **Смени узел/подсеть** (Сигнал 1) — если IP/диапазон попал под раздачу.
6. **Не дёргай настройки рефлекторно** под блоком — сам паттерн адаптации может усугубить.
7. **Запасной канал** — [[VLESS/dpi-tls-june-2026|VLESS+REALITY/XHTTP]] на отдельном узле.

---

## ✅ Чек-лист

- [ ] VPS на «чистой» подсети, домен single-round x25519, порт 443
- [ ] `mask = true`, `fake_tls_only = true`, `drs = true`
- [ ] `TCPMSS` активен (`iptables -t mangle -S OUTPUT | grep TCPMSS`) — или clamp на балансировщике
- [ ] nfqws запущен, **TTL подтюнен** (`systemctl status nfqws-mtproto`)
- [ ] `[metrics] enabled = true` + мониторинг `close_reason`/`handshake_timeouts`
- [ ] Проверил `key_share` клиента в логах (свежесть почерка, #30733)
- [ ] `rate_limit_per_subnet = 0` для мобильных юзеров РФ
- [ ] Готов запасной VLESS/XHTTP

---

## 📚 См. также

- [[mtproxy/ja4-sni-client-side|Кто может менять JA4/SNI]] — почему смена почерка/SNI возможна только на клиенте, что из мер ниже реально серверное
- [[mtproxy/mtproto-zig|MTProxy и mtproto.zig]] — теория: как работает и почему
- [[Zapret/mtproto/10-telemt-logs-dpi|Чтение логов и SYN-ACK лимит]] — детект DPI, per-port nft
- 🔗 [tdesktop#30733](https://github.com/telegramdesktop/tdesktop/issues/30733) — протухший фингерпринт
- [[Zapret/mtproto/05-censorship|ТСПУ: каскад детекции]]
- [[Zapret/mtproto/02-implementations|5 реализаций MTProxy]]
- [[VLESS/dpi-tls-june-2026|Сибирская схема DPI]]
- [[VPS/VPS|Выбор VPS]]

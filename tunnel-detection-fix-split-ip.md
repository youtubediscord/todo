# Фикс обнаружения и блокировки туннелей: разделение IP + маршрутизация sing-box

**Дата:** 7 апреля 2026  
**Источник:** [Dreaght — ntc.party](https://ntc.party/t/фикс-обнаружения-и-блокировки-туннелей-sing-box-маршрутизация/), 2 апреля 2026  
**Контекст:** Шпионские модули в РФ-приложениях сливают входной IP VPN-сервера → РКН блокирует сервер. Инфраструктурный фикс на уровне VPS.  
**Связанные заметки:**
- [Уязвимость VLESS-клиентов — SOCKS5 на localhost](VLESS-SOCKS5-vulnerability.md)
- [Защита VPN от localhost-атаки](VLESS-localhost-protection-guide.md)
- [Localhost-трекинг Meta/Яндекс](Localhost-tracking-Meta-Yandex-SOCKS5.md)

---

## Оглавление

1. [TL;DR](#1-tldr)
2. [Модель угрозы](#2-модель-угрозы)
3. [Почему sandbox и split-tunneling не спасают](#3-почему-sandbox-и-split-tunneling-не-спасают)
4. [Шаг 1: Купить второй IPv4 на VPS](#4-шаг-1-купить-второй-ipv4-на-vps)
5. [Шаг 2: Разделить входной/выходной IP в sing-box](#5-шаг-2-разделить-входнойвыходной-ip-в-sing-box)
6. [Шаг 3: WARP для неизвестного трафика](#6-шаг-3-warp-для-неизвестного-трафика)
7. [Шаг 4: Direct для доверенных CIDR](#7-шаг-4-direct-для-доверенных-cidr)
8. [Шаг 5: Tor для геоблокированных сервисов](#8-шаг-5-tor-для-геоблокированных-сервисов)
9. [Шаг 6: I2P через VPS](#9-шаг-6-i2p-через-vps)
10. [Шаг 7: SSH через туннель](#10-шаг-7-ssh-через-туннель)
11. [Шаг 8: DNS-разделение RU/Default](#11-шаг-8-dns-разделение-rudefault)
12. [Итоговая архитектура](#12-итоговая-архитектура)
13. [Рекомендация по транспорту](#13-рекомендация-по-транспорту)
14. [Чеклист](#14-чеклист)

---

## 1. TL;DR

- Шпионские модули в РФ-приложениях (MAX, Яндекс, ВК, и др.) обнаруживают входной IP VPN-сервера и сливают его РКН.
- РКН через логи провайдеров + корреляционную атаку по времени блокирует сервер.
- **Минимальный фикс:** купить второй IPv4, принимать VLESS на входном IP, а выходить в интернет через выходной IP.
- **Расширенная схема:** маршрутизация на VPS через sing-box — WARP, direct, Tor, DNS-разделение.
- Клиентские устройства должны быть «тупыми» — просто гнать весь трафик через VLESS на VPS.

---

## 2. Модель угрозы

### Что подтверждено

1. **MAX содержит шпионский модуль** — разработчики встроили модуль слежки за VPN-пользователями с удалённым управлением, сделали его максимально трудноблокируемым.
2. **РКН продавил закон о логах** — провайдеры обязаны сливать данные (netflow и пр.), позволяющие однозначно идентифицировать абонентов по внутреннему NAT IP.
3. **Active probing** — РКН автоматически прозванивает обнаруженные входные IP VPN-серверов.

### Как работает корреляционная атака

```
1. Шпион в приложении (MAX/VK/Яндекс) → запрос через свой exit IP → логируется на сервере
2. В то же временное окно другой шпион (другое приложение) → запрос через другой exit IP
3. У провайдера: из логов (netflow) → внутренний NAT IP пользователя
4. Два IP в одно время от одного NAT IP → один из них = VPN-туннель
5. Особенно легко при split-tunneling: два разных IP в одном временном окне
```

### Симптомы блокировки

- Периодические обрывы соединений к self-hosted VPS.
- ClientHello доходит, сервер не видит ACK, клиент ими долбится.
- RST-пакеты от лица сервера к клиенту и от клиента к серверу (инжектируемые ТСПУ).
- SSH тоже отваливается.
- Блокировка входного IP со всех локаций сразу.

---

## 3. Почему sandbox и split-tunneling не спасают

| Подход | Почему не работает |
|--------|--------------------|
| **Sandbox / Knox / Shelter / Island** | Loopback-интерфейс общий, шпион и так может обойти изоляцию |
| **Per-app split-tunneling** | Заставляет конечные устройства быть «умными» — рано или поздно ошибёшься. Архитектурно неправильно |
| **Бан конкретных приложений** | Тараканов по одному ловить — тупик. IP утекает сотней способов |
| **Изоляция интерфейса сети (QubesOS-style)** | Нереалистично на смартфонах, заведомо проигрышная борьба |
| **IP-чекеры / блок шпионов** | Невозможно отловить все каналы утечки, пролезут в правила маршрутизации |

> **Правильный подход:** инфраструктурный фикс на сервере. Клиенты — тупые, сервер — умный.

---

## 4. Шаг 1: Купить второй IPv4 на VPS

1. В панели управления VPS → вкладка **«Сеть»** → купить дополнительный белый IPv4.
2. Проверить, что оба IP доступны:

```bash
ip a
```

Должны быть видны:
- **Входной IP** (`X.X.X.X`) — на нём будет слушать sing-box. **Нигде не светить!**
- **Выходной IP** (`Y.Y.Y.Y`) — на него bind outbound. Этот IP увидят шпионы, и это ОК.
- IPv6 выходной (опционально, WARP предоставляет свой).

### Настройка сетевого интерфейса (systemd-networkd)

Если нового IP нет в `ip a` после покупки — настройте вручную.

Файл `/etc/systemd/network/20-eth0.network`:

```ini
[Match]
Name=eth0

[Network]
# IPv4 — ПОРЯДОК ВАЖЕН: выходной IP первым (будет дефолтным)!
Address=Y.Y.Y.Y/24
Address=X.X.X.X/24
Gateway=Y.Y.Y.1

# IPv6
Address=YYYY:YYYY:Y:Y::YYYY/64
Gateway=YYYY:YYYY:Y:Y::1

DNS=1.1.1.1
DNS=2606:4700:4700::1111
IPv6AcceptRA=yes
```

> **Критично:** `X.X.X.X` (входной) должен идти **ПОСЛЕ** `Y.Y.Y.Y` (выходной), чтобы выходной был дефолтным в системе!

Перезапустить:

```bash
systemctl restart systemd-networkd
```

---

## 5. Шаг 2: Разделить входной/выходной IP в sing-box

Конфиг `/etc/sing-box/config.json`:

### Inbound — слушать ТОЛЬКО на входном IP

```json
{
  "inbounds": [
    {
      "type": "vless",
      "tag": "reality-in",
      "listen": "X.X.X.X",
      "listen_port": 443,
      "...": "остальные параметры VLESS-Reality"
    }
  ]
}
```

> Где `X.X.X.X` — **входной IP**, который нельзя нигде светить.

### Outbound — выходить через выходной IP

```json
{
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "inet4_bind_address": "Y.Y.Y.Y"
    }
  ]
}
```

> Где `Y.Y.Y.Y` — **выходной IP**. Его и увидят шпионы — но заблокировать по нему входной IP уже не смогут.

### Подстраховка для других outbound

Если есть другие outbound (upstream прокси, WARP и т.д.) — добавить `inet4_bind_address` и туда:

```json
{
  "type": "direct",
  "tag": "some-other-outbound",
  "inet4_bind_address": "Y.Y.Y.Y"
}
```

> **Это минимальный фикс.** Его одного уже достаточно, чтобы закрыть основную уязвимость.

---

## 6. Шаг 3: WARP для неизвестного трафика

Зачем: выходной IP принадлежит ASN датацентра → сервисы типа Кинопоиск не откроются. WARP даёт «резидентный» IP.

Цепочка: `Me → VLESS → WARP → Неизвестный трафик`

### Генерация конфига WARP

С VPS выполнить (инструкции из репозитория [WARP-клиента](https://github.com/ViRb3/wgcf)):

```bash
wgcf register
wgcf generate
```

### Endpoint в sing-box

```json
{
  "endpoints": [
    {
      "type": "wireguard",
      "tag": "warp-ep",
      "system": false,
      "name": "wg0",
      "mtu": 1280,
      "address": [
        "172.16.0.2/32",
        "fd01:5ca1:ab1e:8d97:ef27:3f9b:aa5c:1234/128"
      ],
      "private_key": "ВАШ_ПРИВАТНЫЙ_КЛЮЧ=",
      "domain_resolver": "google",
      "peers": [
        {
          "address": "engage.cloudflareclient.com",
          "port": 2408,
          "public_key": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
          "allowed_ips": [
            "0.0.0.0/0",
            "::/0"
          ]
        }
      ]
    }
  ]
}
```

> Замените `address`, `private_key` на значения из сгенерированного `wgcf-profile.conf`. `public_key` пира — стандартный CF WARP.

---

## 7. Шаг 4: Direct для доверенных CIDR

Доверенные сервисы, на чьих CIDR нельзя разместить свой сервер — напрямую в direct без WARP.

Цепочка: `Me → VLESS → Direct → Apple, Telegram, и др.`

### Route rules

```json
{
  "route": {
    "rules": [
      {
        "rule_set": ["geoip-apple", "geoip-telegram"],
        "action": "route",
        "outbound": "direct"
      }
    ]
  }
}
```

> Важно: используйте **CIDR / geoip**, а не geosite. Geosite работает через домены — шпион может подставить свой домен в тот же CIDR.

---

## 8. Шаг 5: Tor для геоблокированных сервисов

Некоторые сервисы (OpenAI, Habr, TikTok) блокируют IP датацентров и WARP. Решение — Tor или upstream прокси.

Цепочка: `Me → VLESS → Tor → Геоблокированные сервисы`

### Установка Tor на VPS

```bash
# Debian/Ubuntu
sudo apt install tor

# Arch
sudo pacman -S tor
```

Tor запустится как SOCKS5 прокси на `127.0.0.1:9050`.

### Outbound в sing-box

```json
{
  "type": "socks",
  "tag": "tor-out",
  "server": "127.0.0.1",
  "server_port": 9050
}
```

### Route rule

```json
{
  "rule_set": ["geosite-openai", "geosite-tiktok"],
  "action": "route",
  "outbound": "tor-out"
}
```

> Альтернатива Tor: upstream ShadowSocks-прокси (с/без WARP). Современный Tor достаточно быстрый для большинства задач.

---

## 9. Шаг 6: I2P через VPS

Цепочка: `Me → VLESS → I2P`

I2P-роутер работает на самом VPS. Клиент не знает про I2P — просто гонит трафик через VLESS, а VPS маршрутизирует в I2P по правилам.

### Установка I2P на VPS

```bash
# Debian/Ubuntu
sudo apt install i2pd

# Arch
sudo pacman -S i2pd
```

I2P-роутер запустится и создаст HTTP-прокси на `127.0.0.1:4444` и SOCKS на `127.0.0.1:4447`.

### Outbound в sing-box

```json
{
  "type": "socks",
  "tag": "i2p-out",
  "server": "127.0.0.1",
  "server_port": 4447
}
```

### Route rule (для .i2p доменов)

```json
{
  "domain_suffix": [".i2p"],
  "action": "route",
  "outbound": "i2p-out"
}
```

---

## 10. Шаг 7: SSH через туннель

SSH слушает ТОЛЬКО на выходном IP → подключение автоматически идёт через VLESS.

Цепочка: `Me → VLESS → SSH (к выходному IP Y.Y.Y.Y) → мой сервер`

### Настройка sshd

В `/etc/ssh/sshd_config`:

```
ListenAddress Y.Y.Y.Y
```

> Пинг от входного IP к выходному IP в подсети хостера — околонулевой. Также можно подключаться через IPv6 если есть.

### Аварийный доступ — через Tor (onion SSH)

Если туннель лёг:

```
Me → Tor bridges → Tor → SSH-over-onion → мой сервер
```

В `/etc/tor/torrc`:

```
HiddenServiceDir /var/lib/tor/ssh/
HiddenServicePort 22 127.0.0.1:22
```

После перезапуска Tor — onion-адрес в `/var/lib/tor/ssh/hostname`.

> Это single-point-of-failure бэкап. Мосты Tor можно получить через email, PGP, GitHub Actions бот.

---

## 11. Шаг 8: DNS-разделение RU/Default

Проблема: Google DNS не возвращает «правильные» IP для РФ-сервисов (госуслуги и т.д.). Решение — форсировать Yandex DNS для RU-сегмента на самом VPS.

```
DNS over VLESS:
  RU → Yandex DoU (unencrypted, на VPS)
  Default → Google DoT (encrypted)
```

> Не заморачивайте конечные клиенты DNS-правилами — всё на сервере.

### dns.rules — перенаправить RU-домены на Yandex

```json
{
  "dns": {
    "servers": [
      {
        "tag": "google",
        "address": "tls://8.8.8.8",
        "detour": "direct"
      },
      {
        "tag": "local",
        "address": "77.88.8.8",
        "detour": "direct"
      }
    ],
    "rules": [
      {
        "rule_set": ["geosite-category-ru"],
        "server": "local"
      }
    ]
  }
}
```

### route.rules — заставить RU-сервисы использовать Yandex DNS

```json
{
  "route": {
    "rules": [
      {
        "rule_set": ["geosite-category-ru"],
        "action": "resolve",
        "server": "local"
      }
    ]
  }
}
```

### rule_set — источник списка RU-доменов

```json
{
  "route": {
    "rule_set": [
      {
        "tag": "geosite-category-ru",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/runetfreedom/russia-v2ray-rules-dat/release/sing-box/rule-set-geosite/geosite-category-ru.srs"
      }
    ]
  }
}
```

---

## 12. Итоговая архитектура

```
Клиент (смартфон / ПК)
  │
  │  Весь трафик (кроме BitTorrent на ПК)
  │
  ▼
VLESS-XTLS-uTLS-REALITY-xudp-gRPC
  │  → входной IP X.X.X.X (скрытый)
  │
  ▼
VPS sing-box (маршрутизатор)
  │
  ├─► RU-сервисы (geosite-category-ru)
  │     DNS: Yandex 77.88.8.8
  │     → Direct (выходной IP Y.Y.Y.Y)
  │
  ├─► Доверенные CIDR (Apple, Telegram)
  │     → Direct (выходной IP Y.Y.Y.Y)
  │
  ├─► Неизвестный трафик (default)
  │     DNS: Google 8.8.8.8 DoT
  │     → WARP (CF WireGuard)
  │
  ├─► Геоблокированные (OpenAI, TikTok, Habr)
  │     → Tor SOCKS5 (localhost:9050)
  │       или ShadowSocks (с/без WARP)
  │
  ├─► I2P
  │     → I2P-роутер на самом VPS
  │
  ├─► SSH
  │     → к выходному IP Y.Y.Y.Y (через VLESS автоматически)
  │     → или по IPv6
  │     → аварийный: bridges → Tor → SSH-over-onion
  │
  └─► BitTorrent (только ПК)
        → DIRECT (напрямую, минуя VPN)

Клиент → DIRECT → BitTorrent
```

### Проброс портов на входном IP

```
80/TCP  — на входном IP (X.X.X.X)
443/UDP — на входном IP (X.X.X.X)
```

SSH слушать **только** на выходном IPv4 (`Y.Y.Y.Y`).

### Правила маршрутизации

Реализованы на **сервере** по:
- `geosite` / `geoip` — rule_set
- Портам — port matching
- `user_auth` — дифференциация по пользователям

### Принцип

- **Клиенты — тупые.** Только гонят весь трафик через VLESS.
- **VPS — умный.** Вся логика маршрутизации на сервере.
- **Входной IP скрыт.** Шпионы видят только выходной IP (или WARP/Tor IP).
- **Выходной IPv4 — дефолтный** в системе, входной IPv4 — дополнительный.
- **Принуждение DNS:** Yandex DoU для RU-доменов, даже если клиент хотел другой DNS.

---

## 13. Рекомендация по транспорту

**Протокол:** `VLESS-XTLS-uTLS-REALITY-xudp-gRPC`

- **REALITY** — SNI к домену в подсети хостера (не к публичному сайту).
- **gRPC транспорт** — обязателен как минимум. Мультиплексирование gRPC предотвращает триггер «Сибирской блокировки» (корреляция по временным паттернам TCP-соединений).
- После фикса (разделение IP) автор пользовался обычным TCP без мультиплексирования — проблемы исчезли. Но gRPC рекомендуется для подстраховки.

---

## 14. Чеклист

- [ ] Куплен второй IPv4 на VPS
- [ ] Оба IP видны в `ip a`
- [ ] В systemd-networkd: выходной IP **первым**, входной — вторым
- [ ] `inbounds.listen` = входной IP (X.X.X.X)
- [ ] `outbounds.direct.inet4_bind_address` = выходной IP (Y.Y.Y.Y)
- [ ] Все прочие outbound тоже с `inet4_bind_address` = Y.Y.Y.Y
- [ ] Входной IP не фигурирует ни в каких outbound
- [ ] Проброс портов: 80/TCP и 443/UDP на входном IP
- [ ] SSH слушает **только** на выходном IPv4
- [ ] WARP endpoint настроен (ключи сгенерированы с VPS)
- [ ] I2P-роутер (i2pd) запущен на VPS
- [ ] Tor демон запущен на VPS
- [ ] Tor onion для аварийного SSH доступа
- [ ] DNS: RU → Yandex, Default → Google DoT
- [ ] Route rules: geosite-category-ru → resolve через local DNS
- [ ] Маршрутизация по geosite/geoip/портам/user_auth — на сервере
- [ ] Клиенты настроены гнать ВЕСЬ трафик через VLESS (кроме BitTorrent на ПК)
- [ ] Проверить: `curl ifconfig.me` с клиента → показывает WARP/выходной IP, **НЕ** входной
- [ ] Проверить: госуслуги и РФ-сервисы открываются через туннель

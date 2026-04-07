# Практическое руководство: защита VPN от localhost-атаки

**Дата:** 7 апреля 2026  
**Контекст:** Уязвимость VLESS-клиентов + эксплуатация localhost Meta/Яндексом  
**Аудитория:** Пользователи VPN, администраторы серверов, разработчики клиентов  
**Связанные заметки:**
- [Уязвимость VLESS-клиентов](VLESS-SOCKS5-vulnerability.md)
- [Localhost-трекинг Meta/Яндекс](Localhost-tracking-Meta-Yandex-SOCKS5.md)

---

## Оглавление

1. [Суть проблемы за 30 секунд](#1-суть-проблемы-за-30-секунд)
2. [Проверенные клиенты: кто уязвим, кто нет](#2-проверенные-клиенты-кто-уязвим-кто-нет)
3. [Что делать пользователям Android](#3-что-делать-пользователям-android)
4. [Что делать пользователям Windows](#4-что-делать-пользователям-windows)
5. [Что делать пользователям iOS](#5-что-делать-пользователям-ios)
6. [Что делать администраторам серверов](#6-что-делать-администраторам-серверов)
7. [Конфигурации: xray-core клиент](#7-конфигурации-xray-core-клиент)
8. [Конфигурации: sing-box клиент](#8-конфигурации-sing-box-клиент)
9. [Конфигурации: xray-core сервер](#9-конфигурации-xray-core-сервер)
10. [Конфигурации: CloudFlare WARP на сервере](#10-конфигурации-cloudflare-warp-на-сервере)
11. [Конфигурации: блокировка geoip:ru на сервере](#11-конфигурации-блокировка-geoipru-на-сервере)
12. [Конфигурации: маршрутизация «Всё кроме РФ» на клиенте](#12-конфигурации-маршрутизация-всё-кроме-рф-на-клиенте)
13. [Блокировка Happ на сервере подписок](#13-блокировка-happ-на-сервере-подписок)
14. [FAQ: hev-socks5-tunnel, Karing, Husi, v2rayN](#14-faq-hev-socks5-tunnel-karing-husi-v2rayn)
15. [CVE-2023-43644: обход аутентификации sing-box](#15-cve-2023-43644-обход-аутентификации-sing-box)
16. [Чеклист действий](#16-чеклист-действий)

---

## 1. Суть проблемы за 30 секунд

Все VPN-клиенты на базе xray/sing-box создают на телефоне/компьютере **локальный SOCKS5-прокси без пароля**. Любое приложение-шпион (Яндекс, WB, Ozon, гос.приложения) может:

1. Найти этот прокси за секунды (скан портов localhost)
2. Подключиться без пароля
3. Узнать IP вашего VPN-сервера
4. Передать IP в РКН → сервер заблокирован

**Knox, Shelter, Island, режим инкогнито, split tunneling — НЕ помогают.**

Скриншот POC-приложения с включённой SOCKS5-аутентификацией (Husi):
```
Per-app split tunnel bypass
Status: VPN not found          ← прокси не обнаружен
Direct IP: xxx.xxx.xxx.xxx
IP via proxy: -                ← не смог подключиться
Xray API: Not found            ← API недоступен
```
**Вывод:** аутентификация работает — POC не смог пробиться через запароленный SOCKS5.

---

## 2. Проверенные клиенты: кто уязвим, кто нет

### Android

| Клиент | Ядро | SOCKS5 auth | UDP auth | Статус | Что делать |
|--------|------|-------------|----------|--------|------------|
| **v2rayNG** | xray (hev-socks5-tunnel) | ❌ Нет | ❌ | 🟡 Уязвим | Перейти на Husi/SFA или ждать фикса |
| **Hiddify** | sing-box | ❌ Нет в UI | ❌ | 🟡 Уязвим | Перейти на Husi/SFA |
| **Neko Box** | sing-box | ❌ Нет | ❌ | 🟡 Уязвим | Перейти на Husi/SFA |
| **Npv Tunnel** | xray | ❌ Нет | ❌ | 🟡 Уязвим | Перейти на Husi/SFA |
| **Happ** | xray | ❌ Нет | ❌ | 🔴 **Удалить немедленно** | HandlerService = дамп ключей |
| **Karing** | sing-box | ⚠️ Возможно через JSON | ? | 🟡 Нужна проверка | См. [FAQ](#14-faq) |
| **Husi** | sing-box (dun) | ✅ **Да** | ⚠️ Сессионная | 🟢 **Рекомендован** | Включить auth в настройках |
| **SFA (sing-box)** | sing-box | ✅ Да (JSON) | ⚠️ Сессионная | 🟢 Можно настроить | Ручная правка JSON |
| **saeeddev94/xray** | xray | ✅ Да (JSON) | ⚠️ Сессионная | 🟢 Можно настроить | F-Droid, ручной JSON |

### Windows

| Клиент | Ядро | SOCKS5 auth | Статус | Что делать |
|--------|------|-------------|--------|------------|
| **v2rayN** | xray | ⚠️ Через JSON | 🟡 Нужна ручная настройка | Включить auth + firewall |
| **Nekoray** | sing-box/xray | ❌ Нет в UI | 🟡 Уязвим | Firewall + process rules |
| **XrayFluent** | xray | ❌ Нет | 🟡 Уязвим | Будет исправлено |

### iOS

| Клиент | Ядро | SOCKS5 auth | Статус | Что делать |
|--------|------|-------------|--------|------------|
| **Happ** | xray | ❌ + API без auth | 🔴 **Удалить** | Удалено из App Store, обновлений не будет |
| **V2BOX** | xray | ❌ Нет | 🟡 Уязвим | Нет решения |
| **Exclave** | xray | ❌ Нет | 🟡 Уязвим | Нет решения |
| **Shadowrocket** | — | ⚠️ Неизвестно | ❓ Нужна проверка | — |

### О hev-socks5-tunnel (используется в v2rayNG)

**hev-socks5-tunnel** — это легковесная реализация tun2socks. Сама библиотека **поддерживает** SOCKS5-аутентификацию (username/password). Но **v2rayNG не включает auth** при настройке туннеля — передаёт `noauth`. Проблема не в hev-socks5-tunnel, а в том, что v2rayNG не выставляет аутентификацию на inbound xray-core, к которому подключается туннель.

### О Karing

**Karing** использует ядро sing-box. Создаёт local proxy на портах:
- HTTP/HTTPS: `127.0.0.1:3066`
- SOCKS5: `127.0.0.1:3067`

Поддержка аутентификации наследуется от sing-box, но **в UI Karing нет настройки SOCKS5 auth**. Теоретически можно через кастомный JSON-конфиг, но это нужно проверять.

> ⚠️ **Важно:** Karing использует нестандартные порты (3066/3067), которых нет в методичке Минцифры. Но скан всех портов localhost — дело секунд.

### О Husi (подтверждённый фикс)

**Husi** ([codeberg.org/xchacha20-poly1305/husi](https://codeberg.org/xchacha20-poly1305/husi)) — форк sing-box для Android с поддержкой SOCKS5-аутентификации в UI. Проверено: POC-приложение per-app-split-bypass **не может** обнаружить прокси при включённой аутентификации (скриншот выше).

> ⚠️ **Критично:** убедитесь что Husi использует sing-box версии **1.4.5 или выше** — в более ранних версиях есть CVE-2023-43644 (обход аутентификации). См. [раздел 15](#15-cve-2023-43644-обход-аутентификации-sing-box).

---

## 3. Что делать пользователям Android

### Приоритет 1: Немедленно

1. **Удалить Happ** — HandlerService без аутентификации позволяет дампить ваши ключи и IP сервера. Один пользователь с Happ компрометирует весь сервер.

2. **Перейти на клиент с SOCKS5 auth:**
   - **Husi** (рекомендован) — [codeberg.org/xchacha20-poly1305/husi](https://codeberg.org/xchacha20-poly1305/husi)
   - **SFA** (sing-box for Android) — ручная настройка JSON
   - **saeeddev94/xray** — [F-Droid](https://f-droid.org/packages/io.github.saeeddev94.xray/) — ручной JSON

3. **Включить аутентификацию** в настройках клиента (см. конфиги ниже)

### Приоритет 2: Серверная защита

4. Попросить администратора сервера настроить **раздельные IP** (входной ≠ выходной)
5. Убедиться что на сервере **заблокирован geoip:ru на outbound**
6. Использовать маршрутизацию **«Всё кроме РФ»** на клиенте

### Приоритет 3: Изоляция

7. **Российское ПО — на отдельное устройство.** Knox/Shelter/Island **НЕ изолируют loopback**.
8. Если есть root: заблокировать доступ к SOCKS-порту через iptables:
   ```bash
   # Разрешить только UID VPN-клиента (например, 10150)
   iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 10808 -m owner --uid-owner 10150 -j ACCEPT
   iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 10808 -j DROP
   # То же для UDP
   iptables -I OUTPUT -p udp -d 127.0.0.1 --dport 10808 -m owner --uid-owner 10150 -j ACCEPT
   iptables -I OUTPUT -p udp -d 127.0.0.1 --dport 10808 -j DROP
   ```
   > UID приложения: `adb shell dumpsys package <package.name> | grep userId`

### Чего НЕ делать

- ❌ Не полагаться на смену порта — скан 65535 портов на localhost за секунды
- ❌ Не полагаться на Knox/Shelter/Island — loopback общий
- ❌ Не полагаться на split tunneling — шпион ходит напрямую на 127.0.0.1
- ❌ Не полагаться на режим инкогнито — не влияет на localhost

---

## 4. Что делать пользователям Windows

На Windows ситуация **лучше**, чем на Android: есть Windows Firewall с контролем по процессам.

### Приоритет 1: Firewall

1. **Заблокировать доступ к порту 10808/10809 для всех процессов кроме доверенных:**

   PowerShell (от администратора):
   ```powershell
   # Заблокировать ВСЕ подключения к SOCKS-порту
   New-NetFirewallRule -DisplayName "Block SOCKS5 10808" `
     -Direction Outbound -LocalPort 10808 -Protocol TCP `
     -Action Block -Profile Any

   # Разрешить только xray.exe
   New-NetFirewallRule -DisplayName "Allow xray SOCKS5" `
     -Direction Outbound -LocalPort 10808 -Protocol TCP `
     -Program "C:\path\to\xray.exe" -Action Allow -Profile Any

   # Разрешить браузеру (если нужен прямой SOCKS)
   New-NetFirewallRule -DisplayName "Allow Firefox SOCKS5" `
     -Direction Outbound -LocalPort 10808 -Protocol TCP `
     -Program "C:\Program Files\Mozilla Firefox\firefox.exe" `
     -Action Allow -Profile Any

   # То же для HTTP-прокси порта
   New-NetFirewallRule -DisplayName "Block HTTP proxy 10809" `
     -Direction Outbound -LocalPort 10809 -Protocol TCP `
     -Action Block -Profile Any

   New-NetFirewallRule -DisplayName "Allow xray HTTP" `
     -Direction Outbound -LocalPort 10809 -Protocol TCP `
     -Program "C:\path\to\xray.exe" -Action Allow -Profile Any
   ```

   > **Важно:** правила `Allow` должны быть выше правил `Block` по приоритету. В Windows Firewall `Block` имеет приоритет по умолчанию, поэтому нужно настроить через GPO или использовать `netsh` с правильным порядком.

2. **Альтернатива — xray routing с process name:**

   В конфиге xray-core на клиенте можно ограничить, какие процессы могут использовать прокси:
   ```json
   {
     "routing": {
       "rules": [
         {
           "type": "field",
           "processName": ["firefox", "chrome", "msedge", "telegram"],
           "outboundTag": "proxy"
         },
         {
           "type": "field",
           "processName": ["yandex", "vk", "ozon"],
           "outboundTag": "block"
         }
       ]
     }
   }
   ```
   > **Ограничение:** `processName` работает только для локальных подключений (тот же хост). Формат: `"firefox"` (без .exe) или `"C:\\Program Files\\app.exe"` (абсолютный путь).

### Приоритет 2: Конфигурация клиента

3. **Включить SOCKS5 auth** в конфиге (даже на Windows это полезно):

   В v2rayN: настройки → custom inbound config → изменить `"auth": "noauth"` на `"auth": "password"` + добавить `"accounts"`.

4. **Использовать маршрутизацию «Всё кроме РФ»:**

   В v2rayN 7.0+: `Настройки → Региональные пресеты → Россия → Всё кроме РФ`. Автоматически скачивает правила из [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat).

---

## 5. Что делать пользователям iOS

Ситуация на iOS **самая сложная:**
- Большинство клиентов удалено из App Store → обновлений не будет
- Нет root → нет iptables
- Нет возможности редактировать inbound JSON в большинстве клиентов

### Что можно сделать

1. **Удалить Happ** — самый опасный клиент, удалён из App Store, фикса не будет
2. **Использовать клиенты с поддержкой custom JSON** — если такие ещё установлены
3. **Защита на стороне сервера** — единственная реальная опция:
   - Раздельные входной/выходной IP
   - WARP на выходе
   - geoip:ru → block на сервере

### Особенность iOS

Исследователи LocalMess отмечают: iOS **технически уязвима** к тому же вектору (loopback не изолирован), но фоновые приложения iOS **жёстко ограничены** — им сложнее запускать постоянные фоновые сканеры. Это не защита, а лишь усложнение атаки.

---

## 6. Что делать администраторам серверов

### Приоритет 1: Раздельные IP

Если у сервера **один IP** — выходной IP = входной IP. Утечка выходного = потеря сервера.

**Решение: два IP-адреса.**
- Входной IP (для подключения клиентов) → inbound слушает на нём
- Выходной IP (для исходящего трафика) → freedom outbound через `sendThrough`

```json
{
  "outbounds": [
    {
      "protocol": "freedom",
      "sendThrough": "203.0.113.46",
      "tag": "freedom-out"
    }
  ]
}
```

Если второй IP недоступен → используйте WARP (раздел 10).

### Приоритет 2: WARP на выходе

CloudFlare WARP маскирует выходной IP. Даже если шпион узнает выходной IP через SOCKS5, он получит IP Cloudflare, а не вашего сервера.

### Приоритет 3: Блокировка geoip:ru на outbound

Шпионский модуль, пробравшийся через SOCKS5, отправит запрос на российский сервер (для передачи вашего IP в РКН). Если заблокировать исходящий трафик на geoip:ru, шпион не сможет связаться со своим сервером через ваш VPN.

### Приоритет 4: Блокировка Happ

На сервере подписок заблокировать UserAgent `Happ/*`. Один пользователь с Happ = компрометация всего сервера (ключи, SNI, входной IP).

### Приоритет 5: Мониторинг

Отслеживать нетипичные запросы через прокси:
- `ifconfig.me`, `ipinfo.io`, `whatismyip.com`, `api.ipify.org`
- Массовые запросы на российские IP
- Паттерны, характерные для сканирования

---

## 7. Конфигурации: xray-core клиент

### Безопасный inbound (SOCKS5 с аутентификацией)

```json
{
  "inbounds": [
    {
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "port": 10808,
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "xfl_a8b3c2d1",
            "pass": "p_7e4f91d0c3b8a2e5f6"
          }
        ],
        "udp": false
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": true
      }
    },
    {
      "tag": "http-in",
      "listen": "127.0.0.1",
      "port": 10809,
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "xfl_a8b3c2d1",
            "pass": "p_7e4f91d0c3b8a2e5f6"
          }
        ]
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": true
      }
    }
  ]
}
```

### Описание полей

| Поле | Значение | Почему |
|------|----------|--------|
| `"auth": "password"` | Включает аутентификацию | Шпион не сможет подключиться без логина/пароля |
| `"accounts"` | `[{user, pass}]` | Рандомные credentials — генерировать при каждом запуске |
| `"udp": false` | Отключает UDP | UDP ASSOCIATE не аутентифицирует per-packet (RFC 1928) |
| `"listen": "127.0.0.1"` | Только localhost | Никогда `0.0.0.0` — иначе прокси доступен из сети |
| `"sniffing"` | Определение протоколов | Нужно для правильной маршрутизации |

### Почему UDP отключён

Протокол SOCKS5 (RFC 1928, Section 7) аутентифицирует **только TCP-соединение**. Команда UDP ASSOCIATE создаёт UDP-ретранслятор, но сами UDP-датаграммы **не содержат поля аутентификации**:

```
UDP-датаграмма SOCKS5:
+-----+------+------+----------+----------+----------+
| RSV | FRAG | ATYP | DST.ADDR | DST.PORT |   DATA   |
+-----+------+------+----------+----------+----------+
|  2  |  1   |  1   | Variable |    2     | Variable |
+-----+------+------+----------+----------+----------+
        ↑ Нет поля для логина/пароля
```

xray-core и sing-box **не реализуют** per-packet аутентификацию для UDP. Поэтому при включённой SOCKS5-аутентификации UDP нужно отключать.

### Без UDP — что перестанет работать?

- ❌ DNS через SOCKS UDP (решение: использовать DNS over HTTPS/TLS)
- ❌ QUIC через SOCKS UDP (решение: fallback на TCP)
- ✅ Обычный веб-браузинг работает (TCP)
- ✅ Telegram работает (TCP fallback)
- ✅ Стриминг работает (TCP)

---

## 8. Конфигурации: sing-box клиент

### Безопасный inbound (mixed с аутентификацией)

```json
{
  "inbounds": [
    {
      "type": "mixed",
      "tag": "mixed-in",
      "listen": "127.0.0.1",
      "listen_port": 2080,
      "users": [
        {
          "username": "sb_d4c1a7f2",
          "password": "p_9e2f5b83a1c7d0e4"
        }
      ],
      "set_system_proxy": false
    }
  ]
}
```

### Без inbound вообще (если не нужен локальный прокси)

Если клиент использует только TUN-режим и вам не нужен локальный SOCKS5-прокси, **удалите mixed inbound полностью**. sing-box **не создаёт** его автоматически — это делают клиенты.

```json
{
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": true,
      "stack": "system"
    }
  ]
}
```

Без mixed/socks inbound шпиону нечего сканировать на localhost.

### Разница type: "socks" vs type: "mixed"

| | `"socks"` | `"mixed"` |
|---|-----------|-----------|
| SOCKS4/4a | ✅ | ✅ |
| SOCKS5 | ✅ | ✅ |
| HTTP proxy | ❌ | ✅ |
| `users` (auth) | ✅ | ✅ |
| Рекомендация | Если нужен только SOCKS | Если нужен SOCKS + HTTP |

---

## 9. Конфигурации: xray-core сервер

### Безопасный серверный конфиг (VLESS + Reality + WARP + блокировка РФ)

```json
{
  "log": {
    "loglevel": "warning"
  },
  "api": {
    "tag": "api",
    "services": ["StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {
      "0": {
        "statsUserUplink": true,
        "statsUserDownlink": true
      }
    },
    "system": {
      "statsInboundUplink": true,
      "statsInboundDownlink": true,
      "statsOutboundUplink": true,
      "statsOutboundDownlink": true
    }
  },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": 443,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "ваш-UUID",
            "email": "user@example.com",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "www.microsoft.com:443",
          "xver": 0,
          "serverNames": ["www.microsoft.com", "microsoft.com"],
          "privateKey": "ВАШЕ_ЗНАЧЕНИЕ_ИЗ_xray_x25519",
          "shortIds": ["", "abcdef12"]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls", "quic"]
      },
      "tag": "vless-reality-in"
    },
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api-in"
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    },
    {
      "protocol": "wireguard",
      "settings": {
        "secretKey": "ВАШЕ_WARP_PRIVATE_KEY",
        "address": ["172.16.0.2/32", "fd01:5ca1:ab1e:823e::/128"],
        "peers": [
          {
            "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
            "allowedIPs": ["0.0.0.0/0", "::/0"],
            "endpoint": "engage.cloudflareclient.com:2408"
          }
        ],
        "reserved": [0, 0, 0],
        "mtu": 1280
      },
      "tag": "warp-out"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["api-in"],
        "outboundTag": "api"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "block",
        "ruleTag": "block-private"
      },
      {
        "type": "field",
        "ip": ["geoip:ru"],
        "outboundTag": "block",
        "ruleTag": "block-russia-ip"
      },
      {
        "type": "field",
        "domain": ["geosite:category-gov-ru", "regexp:\\.ru$"],
        "outboundTag": "block",
        "ruleTag": "block-russia-domains"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block",
        "ruleTag": "block-torrent"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "warp-out",
        "ruleTag": "default-to-warp"
      }
    ]
  }
}
```

### Что делает каждое правило маршрутизации

| Правило | Что блокирует/перенаправляет | Зачем |
|---------|------------------------------|-------|
| `geoip:private` → block | Частные IP (10.x, 192.168.x, 127.x) | Шпион не сможет «вернуться» на локалку через прокси |
| `geoip:ru` → block | Российские IP | Шпион не свяжется с РКН через ваш VPN |
| `category-gov-ru` → block | Госсайты РФ | Госсервисы не получат трафик через прокси |
| `regexp:\.ru$` → block | Все .ru домены | Дополнительная защита |
| `bittorrent` → block | Торренты | Экономия ресурсов, правовая безопасность |
| default → warp-out | Весь остальной трафик | Маскировка выходного IP через WARP |

### О API-сервисах

```json
"services": ["StatsService"]
```

Включён **только** StatsService для мониторинга трафика. **НЕ включать:**
- ❌ `HandlerService` — позволяет дампить конфиги (уязвимость Happ)
- ❌ `RoutingService` — позволяет менять маршрутизацию
- ❌ `ReflectionService` — позволяет обнаружить доступные API

---

## 10. Конфигурации: CloudFlare WARP на сервере

### Зачем

Если шпион всё-таки узнает выходной IP через SOCKS5, он получит IP **Cloudflare WARP**, а не вашего сервера. Ваш реальный IP остаётся скрытым.

### Получение WARP-ключей

#### Способ 1: wgcf

```bash
# Установка
curl -fsSL git.io/wgcf.sh | sudo bash

# Регистрация
wgcf register
wgcf generate

# Файл wgcf-profile.conf содержит:
# PrivateKey = ВАШЕ_WARP_PRIVATE_KEY
# PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
# Address = 172.16.0.2/32, fd01:5ca1:ab1e:823e::/128
# Endpoint = engage.cloudflareclient.com:2408
```

#### Способ 2: warp-go (если wgcf не работает)

```bash
wget -N https://gitlab.com/fscarmen/warp/-/raw/main/warp-go.sh
bash warp-go.sh
```

### Конфиг WireGuard outbound для xray

```json
{
  "protocol": "wireguard",
  "settings": {
    "secretKey": "ЗНАЧЕНИЕ_ИЗ_PrivateKey",
    "address": [
      "172.16.0.2/32",
      "fd01:5ca1:ab1e:823e::/128"
    ],
    "peers": [
      {
        "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=",
        "allowedIPs": ["0.0.0.0/0", "::/0"],
        "endpoint": "engage.cloudflareclient.com:2408"
      }
    ],
    "reserved": [0, 0, 0],
    "mtu": 1280
  },
  "tag": "warp-out"
}
```

**Параметры:**
- `secretKey` — приватный ключ из WARP-регистрации
- `address` — IP-адреса туннеля (IPv4 + IPv6)
- `peers[0].publicKey` — публичный ключ Cloudflare (фиксированный)
- `endpoint` — сервер Cloudflare
- `reserved` — обязательно `[0, 0, 0]` (или значения из wgcf)
- `mtu` — 1280 для максимальной совместимости

### Маршрутизация: весь трафик через WARP

```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "warp-out"
      }
    ]
  }
}
```

### Маршрутизация: только определённый трафик через WARP

```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": ["openai.com", "netflix.com", "spotify.com"],
        "outboundTag": "warp-out"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "direct"
      }
    ]
  }
}
```

---

## 11. Конфигурации: блокировка geoip:ru на сервере

### Полная блокировка (рекомендуется)

```json
{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:ru"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-gov-ru",
          "regexp:\\.ru$",
          "regexp:\\.рф$"
        ],
        "outboundTag": "block"
      }
    ]
  },
  "outbounds": [
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ]
}
```

### Расширенная блокировка (с кастомными списками)

Проект [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) предоставляет актуальные списки:

```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["ext:geoip_RU.dat:ru-block"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "domain": ["ext:geosite_RU.dat:ru-block"],
        "outboundTag": "block"
      }
    ]
  }
}
```

Файлы `geoip_RU.dat` и `geosite_RU.dat` нужно скачать и поместить в директорию ресурсов xray (обычно рядом с `geoip.dat`).

### Зачем блокировать geoip:ru на СЕРВЕРЕ

Если шпион на устройстве пользователя подключится к SOCKS5-прокси и попытается передать выходной IP на российский сервер (например, `api.rkn.gov.ru`), запрос уйдёт через VPN-сервер. Если на сервере geoip:ru → block, запрос будет заблокирован — шпион не сможет передать данные.

Без этой блокировки шпион может анализировать паттерн трафика, сопоставлять его с логами провайдера и вычислить ваш входной IP.

---

## 12. Конфигурации: маршрутизация «Всё кроме РФ» на клиенте

### xray-core клиент

```json
{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "domain": ["geosite:category-ru"],
        "outboundTag": "direct",
        "ruleTag": "ru-sites-direct"
      },
      {
        "type": "field",
        "ip": ["geoip:ru"],
        "outboundTag": "direct",
        "ruleTag": "ru-ip-direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct",
        "ruleTag": "private-direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy",
        "ruleTag": "default-proxy"
      }
    ]
  },
  "outbounds": [
    {
      "protocol": "vless",
      "tag": "proxy",
      "settings": {
        "vnext": [{
          "address": "ВАШ_СЕРВЕР",
          "port": 443,
          "users": [{
            "id": "ВАШ_UUID",
            "encryption": "none",
            "flow": "xtls-rprx-vision"
          }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "fingerprint": "chrome",
          "serverName": "www.microsoft.com",
          "publicKey": "ВАШ_PUBLIC_KEY",
          "shortId": ""
        }
      }
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
}
```

### sing-box клиент (v1.8+)

```json
{
  "route": {
    "rules": [
      {
        "rule_set": ["geoip-ru", "geosite-ru"],
        "outbound": "direct"
      },
      {
        "rule_set": "geoip-private",
        "outbound": "direct"
      }
    ],
    "rule_set": [
      {
        "tag": "geoip-ru",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs"
      },
      {
        "tag": "geosite-ru",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ru.srs"
      },
      {
        "tag": "geoip-private",
        "type": "remote",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-private.srs"
      }
    ],
    "final": "proxy"
  }
}
```

> sing-box v1.8+ использует `rule_set` вместо устаревших `geoip`/`geosite` полей.

### v2rayN — настройка пресета

1. Откройте v2rayN → **Настройки** → **Региональные пресеты**
2. Выберите **Россия**
3. Выберите пресет **«Все, кроме РФ»** (RUv1-All except RF)
4. Правила скачаются автоматически из:
   - GeoIP: `runetfreedom/russia-v2ray-rules-dat`
   - GeoSite: `runetfreedom/russia-v2ray-custom-routing-list`

### Зачем маршрутизация «Всё кроме РФ» на клиенте

1. Российские сайты открываются **напрямую** (быстрее, стабильнее)
2. Шпионский модуль в приложении не может отправить данные через VPN (geoip:ru → direct)
3. Нет заблокированных ресурсов на российских IP (блокировки реализованы иначе)

---

## 13. Блокировка Happ на сервере подписок

### Почему это критично

Happ включает **xray API HandlerService без аутентификации**. Через него можно:
- Дампить **полный outbound-конфиг** (ключи, IP, SNI)
- Узнать **входной IP сервера** (не только выходной)
- Потенциально **расшифровать трафик**

**Один пользователь с Happ компрометирует ВЕСЬ сервер.**

### xray-core НЕ умеет фильтровать по UserAgent

xray-core не имеет встроенной возможности проверять HTTP UserAgent в VLESS/VMess inbound. Фильтрацию нужно делать на уровне **сервера подписок** (nginx/caddy).

### Nginx: блокировка Happ по UserAgent

```nginx
# /etc/nginx/conf.d/block-happ.conf

map $http_user_agent $is_happ {
    default         0;
    ~*Happ          1;
    ~*"Happ/"       1;
}

server {
    listen 443 ssl http2;
    server_name sub.example.com;

    # SSL конфигурация...

    # Блокировка Happ
    if ($is_happ) {
        return 403 "Access denied";
    }

    location /api/subscribe {
        # ваша конфигурация подписок
        proxy_pass http://127.0.0.1:8080;
    }
}
```

### Caddy: блокировка Happ по UserAgent

```caddy
sub.example.com {
    @happ_blocked header_regexp User-Agent "(?i)Happ"
    respond @happ_blocked 403

    reverse_proxy /api/subscribe localhost:8080
}
```

### 3x-ui: блокировка (если подписки через панель)

Если вы используете 3x-ui и раздаёте подписки через встроенный API — поставьте nginx/caddy перед панелью как reverse proxy и добавьте UserAgent-фильтр.

---

## 14. FAQ: hev-socks5-tunnel, Karing, Husi, v2rayN

### Q: v2rayNG использует hev-socks5-tunnel — в нём та же уязвимость?

**A:** `hev-socks5-tunnel` — это библиотека tun2socks, которая **сама по себе поддерживает** SOCKS5-аутентификацию (username/password). Уязвимость не в библиотеке, а в том что **v2rayNG не включает аутентификацию** на SOCKS5 inbound xray-core. hev-socks5-tunnel подключается к xray-core inbound `127.0.0.1:10808` с `noauth` — и шпион может сделать то же самое.

**Чтобы исправить:**
- v2rayNG должен добавить `"auth": "password"` в xray inbound
- И передать те же credentials в конфиг hev-socks5-tunnel
- Пока этого нет — v2rayNG уязвим

### Q: Karing уязвим?

**A:** Скорее всего **да**. Karing использует ядро sing-box и создаёт mixed inbound на `127.0.0.1:3066` (HTTP) и `127.0.0.1:3067` (SOCKS5). В UI Karing **нет настройки SOCKS5 auth**. Теоретически можно через кастомный JSON, но штатно — без аутентификации.

Порты 3066/3067 нестандартные (не в методичке Минцифры), но скан всех портов — секунды.

### Q: Husi — действительно безопасен?

**A:** Husi — единственный Android-клиент с **подтверждённой** SOCKS5-аутентификацией в UI. POC-приложение не смогло обнаружить прокси при включённой аутентификации. **НО:**

1. Убедитесь что используется sing-box **v1.4.5+** — в более ранних есть CVE-2023-43644 (обход auth)
2. UDP ASSOCIATE всё равно не аутентифицируется per-packet — лучше отключить
3. Аутентификация — не панацея, а барьер. Сложную атаку она не остановит

### Q: В v2rayN на Windows можно включить SOCKS5 auth?

**A:** Да, начиная с v7.0+, через ручную правку конфига:
1. Настройки → параметры ядра → кастомный inbound
2. Изменить `"auth": "noauth"` на `"auth": "password"`
3. Добавить `"accounts": [{"user": "xxx", "pass": "yyy"}]`
4. Сохранить и перезапустить

Также в v2rayN 7.0+ есть пресет «Все, кроме РФ» в региональных настройках.

### Q: Как v2rayN реализует «Все, кроме РФ»?

**A:** Настройки → Региональные пресеты → Россия. Скачивает правила из:
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat) — geoip
- [runetfreedom/russia-v2ray-custom-routing-list](https://github.com/nicknameisthekey/russia-v2ray-custom-routing-list) — geosite

Правила: `geoip:ru → direct`, `geosite:ru → direct`, всё остальное → proxy.

---

## 15. CVE-2023-43644: обход аутентификации sing-box

### Критическая уязвимость

**CVE-2023-43644** — Missing Authentication for Critical Function в sing-box SOCKS5 inbound.

| | |
|---|---|
| **CVSS** | 9.1 (Critical) |
| **Затронуто** | sing-box < 1.4.5, sing-box < 1.5.0-rc.5 |
| **Исправлено** | sing-box ≥ 1.4.5, sing-box ≥ 1.5.0-rc.5 |
| **Суть** | Атакующий может обойти SOCKS5-аутентификацию специально сформированным запросом |
| **Источник** | [GHSA-r5hm-mp3j-285g](https://github.com/advisories/GHSA-r5hm-mp3j-285g) |

### Техническая суть

В функции `HandleConnection0` (файл `protocol/socks/handshake.go`) обработка запросов продолжалась **даже после неудачной аутентификации**. Не проверялся код статуса аутентификации.

### Кого затрагивает

- **Husi** — если использует старую версию sing-box (до 1.4.5)
- **Karing** — если использует старую версию sing-box
- **SFA** — если использует старую версию sing-box
- **Все клиенты на базе sing-box** с SOCKS5 inbound

### Как проверить версию

В sing-box клиенте: настройки → о программе → версия ядра. Должна быть **≥ 1.4.5**.

### Рекомендация

Даже если вы включили SOCKS5 auth — **обновите sing-box**. На старых версиях аутентификация обходится.

---

## 16. Чеклист действий

### Для пользователей

- [ ] Удалить Happ (если установлен)
- [ ] Перейти на клиент с SOCKS5 auth (Husi, SFA, saeeddev94/xray)
- [ ] Включить аутентификацию на SOCKS5 inbound
- [ ] Отключить UDP в SOCKS5 (или убедиться что не критично)
- [ ] Включить маршрутизацию «Все, кроме РФ» на клиенте
- [ ] Российское ПО — на отдельное устройство (Android)
- [ ] На Windows: настроить Firewall по процессам
- [ ] Убедиться что sing-box ≥ 1.4.5 (если на sing-box)

### Для администраторов серверов

- [ ] Настроить раздельные входной/выходной IP (или WARP)
- [ ] Заблокировать geoip:ru на outbound
- [ ] Заблокировать geoip:private на outbound
- [ ] Заблокировать .ru/.рф домены на outbound
- [ ] Заблокировать Happ по UserAgent на сервере подписок
- [ ] Убрать HandlerService из API (оставить только StatsService)
- [ ] Убрать ReflectionService из API
- [ ] Включить WARP как outbound (маскировка выходного IP)
- [ ] Мониторить запросы к ifconfig.me/ipinfo.io через прокси

### Для разработчиков клиентов

- [ ] Включить `"auth": "password"` по умолчанию
- [ ] Генерировать рандомные credentials при каждом запуске
- [ ] Отключить UDP в SOCKS5 или реализовать per-packet auth
- [ ] Рандомизировать порт (не стандартные 10808/2080/1080)
- [ ] Слушать только на `127.0.0.1` (никогда `0.0.0.0`)
- [ ] Не включать HandlerService в xray API
- [ ] Обновить sing-box до ≥ 1.4.5 (CVE-2023-43644)

---

## Источники

### Документация протоколов
- [RFC 1928 — SOCKS Protocol Version 5](https://www.rfc-editor.org/rfc/rfc1928)
- [RFC 1929 — Username/Password Auth for SOCKS V5](https://www.rfc-editor.org/rfc/rfc1929)
- [xray-core SOCKS inbound](https://xtls.github.io/en/config/inbounds/socks.html)
- [xray-core Routing](https://xtls.github.io/en/config/routing.html)
- [xray-core Freedom outbound](https://xtls.github.io/en/config/outbounds/freedom.html)
- [xray-core WireGuard outbound](https://xtls.github.io/en/config/outbounds/wireguard.html)
- [xray-core API](https://xtls.github.io/en/config/api.html)
- [xray-core WARP guide](https://xtls.github.io/en/document/level-2/warp.html)
- [sing-box SOCKS inbound](https://sing-box.sagernet.org/configuration/inbound/socks/)
- [sing-box Mixed inbound](https://sing-box.sagernet.org/configuration/inbound/mixed/)
- [sing-box Route rules](https://sing-box.sagernet.org/configuration/route/rule/)

### Уязвимости и исследования
- [CVE-2023-43644 — sing-box SOCKS5 auth bypass](https://github.com/advisories/GHSA-r5hm-mp3j-285g)
- [localmess.github.io — Meta/Яндекс localhost-трекинг](https://localmess.github.io/)
- [Habr: Критическая уязвимость VLESS клиентов](https://habr.com/ru/articles/1020080/)
- [POC: per-app-split-bypass](https://github.com/runetfreedom/per-app-split-bypass-poc)

### Клиенты
- [Husi (Codeberg)](https://codeberg.org/xchacha20-poly1305/husi)
- [saeeddev94/xray (F-Droid)](https://f-droid.org/packages/io.github.saeeddev94.xray/)
- [Karing](https://github.com/KaringX/karing)
- [hev-socks5-tunnel](https://github.com/heiher/hev-socks5-tunnel)
- [v2rayN](https://github.com/2dust/v2rayN)

### GeoIP/GeoSite правила
- [runetfreedom/russia-v2ray-rules-dat](https://github.com/runetfreedom/russia-v2ray-rules-dat)
- [nicknameisthekey/russia-v2ray-custom-routing-list](https://github.com/nicknameisthekey/russia-v2ray-custom-routing-list)
- [Loyalsoldier/v2ray-rules-dat](https://github.com/Loyalsoldier/v2ray-rules-dat)

### Серверные панели
- [3x-ui](https://github.com/MHSanaei/3x-ui)
- [3x-ui WARP setup](https://3x-ui.com/)

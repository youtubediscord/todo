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
14. [**ГАЙД: v2rayNG — как защититься**](#14-гайд-v2rayng--как-защититься)
15. [**ГАЙД: NekoBox — как защититься**](#15-гайд-nekobox--как-защититься)
16. [**ГАЙД: Clash/mihomo — как защититься**](#16-гайд-clashmihomo--как-защититься)
17. [Фаерволы на Android: что реально работает](#17-фаерволы-на-android-что-реально-работает)
18. [FAQ: hev-socks5-tunnel, Karing, Husi, v2rayN](#18-faq-hev-socks5-tunnel-karing-husi-v2rayn)
19. [CVE-2023-43644: обход аутентификации sing-box](#19-cve-2023-43644-обход-аутентификации-sing-box)
20. [Чеклист действий](#20-чеклист-действий)

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

| Клиент | Ядро | Порт | SOCKS5 auth | Статус | Что делать |
|--------|------|------|-------------|--------|------------|
| **v2rayNG** 2.0.0 | xray | 10808 | ❌ Нет в UI. ⚠️ Custom config — ненадёжно (v2rayNG может перезаписать inbound) | 🟡 Уязвим | Перейти на Husi; или AFWall+ (root) |
| **Hiddify** 4.1.1 | sing-box + xray | ? | ❌ Нет в UI | 🟡 Уязвим | Перейти на Husi/SFA |
| **NekoBox** 1.4.2 | sing-box 1.12.19 | 2080 | ❌ Нет в UI. ⚠️ Custom JSON — возможно, но сбрасывается при обновлении | 🟡 Уязвим | Перейти на Husi; или удалить mixed inbound |
| **Npv Tunnel** | xray | ? | ❌ Нет | 🟡 Уязвим | Перейти на Husi/SFA |
| **v2RayTun** 5.19.64 | xray | ? | ⚠️ Ядро поддерживает, UI — неизвестно | 🟡 Скорее уязвим | Уточнить у разработчика |
| **Happ** | xray | ? | ❌ + API HandlerService без auth | 🔴 **УДАЛИТЬ НЕМЕДЛЕННО** | Дамп ключей, IP, SNI |
| **Karing** | sing-box | 3067 | ⚠️ Ядро поддерживает, в UI нет настройки | 🟡 Скорее уязвим | Проверить custom JSON |
| **Exclave** | sing-box | ? | ✅ Да (через конфиг) | 🟢 Можно настроить | Настроить auth в конфиге |
| **Husi** 1.1.0 | sing-box (dun) | ? | ✅ **Да, есть в UI** | 🟢 **Рекомендован** | Включить auth в настройках |
| **SFA** 1.13.6 | sing-box | ? | ✅ Да (JSON) | 🟢 Можно настроить | Ручная правка JSON |
| **saeeddev94/xray** | xray | ? | ✅ Да (JSON + UI) | 🟢 Можно настроить | F-Droid, настроить auth |
| **v2RayTun** 5.20.67 | xray | ? | ❌ Нет в UI. Разработчик обещал фикс (март 2026), пока нет | 🟡 Уязвим | Ждать фикса или перейти. ⚠️ Шлёт домены подписок на свои сервера |
| **ClashMeta Android** 2.11.25 | mihomo | — | ✅ Да (YAML). По дефолту `socks-port` **выключен** (TUN-only) → прокси нет → нечего сканировать | 🟢 **Безопасен по дефолту** | Если включили `socks-port` — добавить auth + убрать `skip-auth-prefixes` |
| **FlClash** | mihomo | — | ✅ Да (YAML). Аналогично — дефолт TUN-only | 🟢 **Безопасен по дефолту** | Аналогично ClashMeta |
| **Incy** 2.0.8 | xray 26.3.27 | ? | ⚠️ Ядро поддерживает, UI-настройка auth не документирована | 🟡 Вероятно уязвим | Нужна проверка — closed-source-подобный |
| **anet** 0.4.2 | Собственный (Rust/ASTP) | — | ✅ **Не применимо** | 🟢 **Не уязвим** | Нет SOCKS5/HTTP прокси на localhost. Чистый TUN через собственный протокол |

### Windows / Desktop

| Клиент | Ядро | Порт | SOCKS5 auth | Статус | Что делать |
|--------|------|------|-------------|--------|------------|
| **v2rayN** 7.20.2 | xray/sing-box | 10808 | ✅ Да (JSON + UI) | 🟢 Можно настроить | Включить auth + Windows Firewall |
| **Nekoray** | sing-box/xray | ? | ❌ Нет в UI | 🔴 **Заброшен (2026)** | Перейти на Throne / v2rayN / Clash Verge Rev |
| **Throne** 1.1.1 (март 2026) | sing-box (основной) + xray (для VLESS) | 2080 | ⚠️ Дефолтный mixed нельзя отключить, но можно создать кастомный inbound с auth | 🟡 Уязвим по дефолту, **можно настроить** | Создать кастомный inbound с auth; заблокировать дефолтный фаерволом |
| **XrayFluent** | xray | 10808 | ❌ Нет | 🟡 Уязвим | Будет исправлено |
| **Karing** (Windows) | sing-box | 3067/3066 | ⚠️ Ядро поддерживает, UI-настройка не подтверждена | 🟡 Вероятно уязвим | Проверить custom JSON |
| **Clash Verge Rev** | mihomo | — | ✅ Да (YAML). По дефолту TUN-only, `socks-port` выключен | 🟢 **Безопасен по дефолту** | Если включили socks-port — добавить auth + убрать skip |
| **ClashX Meta** (macOS) | mihomo | — | ✅ Да (YAML). Аналогично | 🟢 **Безопасен по дефолту** | Аналогично |
| **Incy** (Desktop) 2.0.8 | xray 26.3.27 | ? | ⚠️ Не документировано | 🟡 Нужна проверка | — |

### iOS

| Клиент | Ядро | SOCKS5 auth | Статус | Что делать |
|--------|------|-------------|--------|------------|
| **Happ** | xray | ❌ + API без auth | 🔴 **УДАЛИТЬ** | Удалено из **российского** App Store; в других регионах может быть доступно, но фикса не будет |
| **V2BOX** 5.3.4 | xray | ❌ Нет подтверждения | 🟡 Скорее уязвим | Нет решения |
| **RabbitHole** 1.3.0 | ? (closed-source) | ⚠️ Неизвестно | ❓ Нужна проверка | Closed-source, поддерживает SOCKS5 — нужна проверка POC |
| **Shadowrocket** | iOS VPN framework | ⚠️ Вероятно не применимо (iOS sandbox) | 🟢/❓ **Скорее не уязвим, нужна проверка POC** | iOS sandbox ограничивает listening sockets; нужна проверка на реальном устройстве |

> **Shadowrocket** — это VPN-клиент, который **подключается К** прокси-серверам. Он **не создаёт** локальный SOCKS5-сервер на localhost, в отличие от v2rayNG/NekoBox/Husi. Поэтому шпиону нечего сканировать — уязвимость не применима.

> **Shadowrocket** — использует iOS Network Extension (VPN framework). Основной режим — TUN через системный VPN. **Однако:** верификация показала, что Shadowrocket может поддерживать SOCKS5-прокси конфигурации, указывающие на localhost. На iOS фоновые приложения жёстко ограничены sandbox'ом, что **затрудняет** создание постоянного listening socket'а, доступного другим приложениям. **Вердикт: требуется проверка POC-приложением на реальном устройстве.** Вероятно менее уязвим чем Android-клиенты из-за ограничений iOS, но полностью исключить нельзя.

> **Exclave** ранее указывался как iOS-клиент — это ошибка. Exclave ([github.com/dyhkwong/Exclave](https://github.com/dyhkwong/Exclave)) — это **Android**-клиент на базе sing-box, доступен на F-Droid. Поддерживает аутентификацию через конфиг.

> **RabbitHole** — closed-source iOS/macOS клиент от RABBIT HOLE STUDIO LTD. Поддерживает VLESS, VMess, Hysteria2, SOCKS5 и др. Без публичного репозитория невозможно точно определить, создаёт ли он SOCKS5 на localhost. Требуется ручная проверка POC-приложением.

> **Incy** — кроссплатформенный клиент на xray-core 26.3.27 ([github.com/INCY-DEV/incy-platforms](https://github.com/INCY-DEV/incy-platforms)). v2.0.8 (7 апреля 2026). Поддерживает VLESS Reality, VMess, Trojan, SS, Hysteria2, WireGuard. Auth-статус на локальном inbound не документирован — нужна проверка.

> **Throne** ([github.com/throneproj/Throne](https://github.com/throneproj/Throne)) — **преемник заброшенного Nekoray**. Qt-based, sing-box + встроенный xray-core. v1.1.1 (апрель 2026). Дефолтный mixed inbound **нельзя отключить**, но можно: (1) перевесить на другой IP:port, (2) заблокировать фаерволом, (3) создать кастомный socks/mixed inbound с auth. Из обсуждения на ntc.party: «в Throne ситуация получше — можно создать кастомный инбаунд и закрыть его логопассом».

> **anet** ([github.com/ZeroTworu/anet](https://github.com/ZeroTworu/anet)) — полностью кастомный Rust VPN с собственным протоколом ASTP v0.5 (ChaCha20Poly1305/X25519/Ed25519). **Не создаёт** SOCKS5/HTTP прокси — только чистый TUN. Нишевый проект для «сети друзей» (624 звезды). К данной уязвимости **не применим**.

> **v2RayTun** — xray-core, 16 млн скачиваний, open-source. Разработчик **подтвердил уязвимость** (март 2026) и обещал фикс, но на апрель 2026 фикса нет. ⚠️ Privacy concern: отправляет домены подписок на свои серверы при каждом запуске.

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
        "domain": ["regexp:\\.ru$", "regexp:\\.рф$"],
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

## 14. ГАЙД: v2rayNG — как защититься

> **Статус:** v2rayNG 2.0.0 (апрель 2026) — **SOCKS5-аутентификация НЕ поддерживается через UI**

### Текущая ситуация

v2rayNG — самый популярный xray-клиент на Android. Он создаёт локальный SOCKS5-прокси на `127.0.0.1:10808` **без аутентификации**. В UI приложения **нет настройки** для включения auth. Последняя версия (2.0.0 от 4 апреля 2026) эту проблему **не исправляет**.

Разработчики уведомлены 10 марта 2026 — на 7 апреля фикса нет.

### Вариант A: Custom Config (частичная защита)

v2rayNG поддерживает импорт полного xray JSON-конфига. Можно попробовать включить auth через custom config:

**Шаг 1.** Создайте файл `config.json` на телефоне (через любой текстовый редактор):

```json
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": 10808,
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "password",
        "accounts": [
          {
            "user": "myuser_r4nd0m",
            "pass": "mypass_s3cur3_x7k9"
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
      "port": 10809,
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {
        "accounts": [
          {
            "user": "myuser_r4nd0m",
            "pass": "mypass_s3cur3_x7k9"
          }
        ]
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "tag": "proxy",
      "settings": {
        "vnext": [
          {
            "address": "ВАШ_СЕРВЕР_IP",
            "port": 443,
            "users": [
              {
                "id": "ВАШ_UUID",
                "encryption": "none",
                "flow": "xtls-rprx-vision"
              }
            ]
          }
        ]
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
    },
    {
      "protocol": "blackhole",
      "tag": "block"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": ["geoip:ru"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy"
      }
    ]
  }
}
```

**Шаг 2.** В v2rayNG: нажмите **+** → **Custom config** → **Import custom config from locally** → выберите файл.

**Шаг 3.** Нажмите на импортированный конфиг, чтобы активировать его. Нажмите **V** для подключения.

### ⚠️ Важное ограничение Custom Config

**v2rayNG может перезаписать ваши inbound-настройки своими дефолтными.** Это известная проблема:
- GitHub Issue #275: «Which parts of custom configs are honored?» — ответ: v2rayNG частично перезаписывает inbounds
- GitHub Issue #646: «Custom configurations don't work properly»
- На практике v2rayNG может проигнорировать `"auth": "password"` и выставить `"noauth"`

**Как проверить:** после подключения запустите [POC-приложение](https://github.com/runetfreedom/per-app-split-bypass-poc). Если показывает «VPN not found» / «IP via proxy: -» → auth работает. Если показывает IP → auth перезаписан.

### Вариант B: Смена порта (слабая защита)

Если custom config не работает:

1. В v2rayNG: **Настройки** → прокрутите вниз → поле **Local SOCKS5 port**
2. Замените `10808` на **нестандартный** (например, `47293`)
3. HTTP-порт: аналогично замените `10809` на другой

**Почему это слабая защита:**
- Скан всех 65535 портов — секунды
- Но в методичке Минцифры перечислены конкретные порты, и многие POC/шпионы проверяют только известные
- Это **не защита**, а **усложнение** — лучше чем ничего

### Вариант C: Перейти на Husi (рекомендация)

Если для вас критична защита — **перейти на Husi**:

1. Скачайте Husi: [codeberg.org/xchacha20-poly1305/husi](https://codeberg.org/xchacha20-poly1305/husi/releases)
2. Экспортируйте ссылку из v2rayNG: долгое нажатие на сервер → **Поделиться** → скопируйте VLESS-ссылку
3. В Husi: импортируйте VLESS-ссылку
4. В настройках Husi: включите SOCKS5-аутентификацию (login/password)
5. Проверьте POC — должен показать «VPN not found»

### Вариант D: v2rayNG + AFWall+ (требует root)

Если у вас root:

```bash
# Узнать UID v2rayNG
dumpsys package com.v2ray.ang | grep userId
# Например: userId=10150

# Разрешить только v2rayNG подключаться к порту 10808
iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 10808 -m owner --uid-owner 10150 -j ACCEPT
iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 10808 -j DROP
iptables -I OUTPUT -p udp -d 127.0.0.1 --dport 10808 -m owner --uid-owner 10150 -j ACCEPT
iptables -I OUTPUT -p udp -d 127.0.0.1 --dport 10808 -j DROP

# То же для HTTP-порта
iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 10809 -m owner --uid-owner 10150 -j ACCEPT
iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 10809 -j DROP
```

> Правила iptables сбрасываются при перезагрузке. Используйте AFWall+ для автоматического применения при старте.

### Сводка по v2rayNG

| Метод | Эффективность | Сложность | Root? |
|-------|--------------|-----------|-------|
| Custom config с auth | ⚠️ Может не работать (v2rayNG перезаписывает) | Средняя | Нет |
| Смена порта | 🟡 Слабая (скан все равно найдёт) | Лёгкая | Нет |
| Переход на Husi | ✅ **Подтверждённая защита** | Средняя | Нет |
| AFWall+ iptables | ✅ Полная защита | Сложная | **Да** |
| Отдельное устройство | ✅ Полная изоляция | — | Нет |

---

## 15. ГАЙД: NekoBox — как защититься

> **Статус:** NekoBox 1.4.2 (февраль 2026) — **SOCKS5-аутентификация НЕ поддерживается через UI**
> **Ядро:** sing-box 1.12.19-neko-1 (CVE-2023-43644 исправлена)
> **Nekoray (десктоп):** прекращён, не поддерживается с 2026 года

### Текущая ситуация

NekoBox создаёт **mixed inbound** (SOCKS4/4a/5 + HTTP) на `127.0.0.1:2080` **без аутентификации**. В UI нет настройки SOCKS5 auth. Порт 2080 нестандартный (не в методичке Минцифры), но это не защита — скан все равно найдёт.

### Вариант A: Custom sing-box JSON (лучший вариант без root)

NekoBox позволяет кастомизировать sing-box конфигурацию. Нужно добавить аутентификацию в mixed inbound:

**Шаг 1.** В NekoBox: **Настройки** → **Config Override** (или **Custom Config**)

**Шаг 2.** Добавьте в секцию `inbounds` поле `users`:

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
          "username": "neko_x8f2a1",
          "password": "p_k3m9v7c4b6n1"
        }
      ],
      "sniff": true,
      "sniff_override_destination": false
    }
  ]
}
```

**Шаг 3.** Сохраните и перезапустите NekoBox.

**Шаг 4.** Проверьте [POC-приложением](https://github.com/runetfreedom/per-app-split-bypass-poc):
- «VPN not found» = auth работает ✅
- Показывает IP = auth не применился ❌

### ⚠️ Важное ограничение

NekoBox генерирует sing-box JSON автоматически из UI-настроек. При обновлении конфигурации (смена сервера, обновление подписки) **кастомные inbound могут быть перезаписаны**. Проверяйте auth после каждого изменения.

### Вариант B: Удалить mixed inbound полностью

Если вы используете NekoBox **только в TUN-режиме** (весь трафик через VPN), локальный SOCKS5-прокси вам не нужен. Можно попробовать отключить его:

1. В custom config: удалите mixed inbound из `inbounds`
2. Оставьте только TUN inbound:

```json
{
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "inet4_address": "172.19.0.1/30",
      "auto_route": true,
      "strict_route": true
    }
  ]
}
```

**Без mixed inbound** шпиону нечего сканировать на localhost — прокси не существует.

**Ограничение:** некоторые приложения (Telegram, Firefox с ручной настройкой прокси) могут требовать SOCKS5-прокси напрямую. Без mixed inbound они не смогут подключиться через VPN.

### Вариант C: Смена порта

1. В NekoBox: **Настройки** → **Basic Settings** → **Mixed Port**
2. Замените `2080` на нестандартный (например, `38741`)
3. Перезапустите

Та же оговорка: слабая защита, скан найдёт. Но лучше чем дефолтный 2080.

### Вариант D: Переход на Husi

Husi — тоже sing-box клиент, конфиги **совместимы**:

1. Скачайте Husi: [codeberg.org/xchacha20-poly1305/husi/releases](https://codeberg.org/xchacha20-poly1305/husi/releases)
2. Экспортируйте конфигурации из NekoBox (подписки, VLESS-ссылки)
3. Импортируйте в Husi
4. Включите SOCKS5-аутентификацию в настройках Husi
5. Проверьте POC

**Миграция:** автоматического инструмента нет. Подписки импортируются через ссылки. Routing-правила придётся настроить заново.

### Вариант E: AFWall+ iptables (требует root)

```bash
# Узнать UID NekoBox
dumpsys package moe.nb4a | grep userId
# Например: userId=10200

# Разрешить только NekoBox на порт 2080
iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 2080 -m owner --uid-owner 10200 -j ACCEPT
iptables -I OUTPUT -p tcp -d 127.0.0.1 --dport 2080 -j DROP
iptables -I OUTPUT -p udp -d 127.0.0.1 --dport 2080 -m owner --uid-owner 10200 -j ACCEPT
iptables -I OUTPUT -p udp -d 127.0.0.1 --dport 2080 -j DROP
```

### Nekoray (десктоп) — прекращён

Nekoray (десктопная версия) **больше не поддерживается** с 2026 года. Разработчик: «不再维护，自寻替代品» (больше не обслуживается, ищите альтернативы).

Альтернативы на десктопе:
- **v2rayN** (Windows) — пресет «Все, кроме РФ», ручная правка JSON
- **sing-box** CLI (все платформы) — полный контроль конфигурации
- **XrayFluent** (Windows) — будет исправлен

### Сводка по NekoBox

| Метод | Эффективность | Сложность | Root? |
|-------|--------------|-----------|-------|
| Custom JSON с users | ⚠️ Работает, но может сброситься при обновлении | Средняя | Нет |
| Удаление mixed inbound | ✅ Нет прокси = нечего сканировать | Средняя | Нет |
| Смена порта | 🟡 Слабая | Лёгкая | Нет |
| Переход на Husi | ✅ **Подтверждённая защита** | Средняя | Нет |
| AFWall+ iptables | ✅ Полная защита | Сложная | **Да** |

---

## 16. ГАЙД: Clash/mihomo — как защититься

> **Ядро:** mihomo (Clash Meta) — поддерживает SOCKS5 auth нативно  
> **Проблема:** по дефолту `skip-auth-prefixes` включает `127.0.0.1/8` → **localhost обходит аутентификацию**  
> **Клиенты:** ClashMeta Android, FlClash, Clash Verge Rev, ClashX Meta

### Текущая ситуация

mihomo/Clash — **единственное ядро** с двумя важными преимуществами:

1. **По дефолту `socks-port` выключен** (`# socks-port: 7891` — закомментировано). Дефолтный режим — **rule-based** (правила маршрутизации), без локального SOCKS5-прокси. Шпиону нечего сканировать → **безопасен из коробки**.

2. **Аутентификация поддерживается нативно** через YAML-конфиг — проще чем в xray/sing-box.

**НО:** если вы **сами включили** `socks-port` (раскомментировали строку), возникают два сценария:
- Без `authentication` → прокси полностью открыт → **уязвим**
- С `authentication`, но дефолтным `skip-auth-prefixes: [127.0.0.1/8]` → localhost обходит пароль → **всё ещё уязвим**

Поле `skip-auth-prefixes` по дефолту содержит `127.0.0.1/8` и `::1/128` — это by design, localhost считается «доверенной» зоной. Для защиты от шпионского ПО нужно **убрать localhost из skip-auth-prefixes**.

### Фундаментальное отличие от xray/sing-box

| | xray/sing-box клиенты | mihomo/Clash клиенты |
|---|---|---|
| **SOCKS5 по дефолту** | ✅ Всегда включён | ❌ Выключен (TUN-only) |
| **Auth по дефолту** | `noauth` (открыт) | N/A (порт не открыт) |
| **Риск из коробки** | 🔴 Высокий | 🟢 Низкий |
| **Если включить socks-port** | Открыт без auth | Открыт без auth (аналогично) |
| **Нативная поддержка auth** | Да, но через JSON | Да, через YAML (проще) |

**Вывод:** если вы используете Clash/mihomo в дефолтном TUN-режиме без `socks-port` — **вы не уязвимы**. Проблема возникает только если вы сами включили SOCKS5-порт.

### Дефолтные порты mihomo

| Порт | Тип | Описание |
|------|-----|----------|
| `7890` | HTTP(S) | HTTP-прокси |
| `7891` | SOCKS5 | SOCKS5-прокси |
| `10801` (или `7892`) | Mixed | HTTP + SOCKS5 на одном порту |
| `7892` | Redirect | Прозрачный прокси |
| `7893` | TProxy | Только Linux/Android |

### Уязвимая конфигурация (дефолт)

```yaml
# ❌ УЯЗВИМО: localhost обходит auth
port: 7890
socks-port: 7891
mixed-port: 10801

authentication:
  - "user:password"

# Вот в чём проблема — дефолтные значения:
skip-auth-prefixes:
  - 127.0.0.1/8
  - ::1/128
```

Даже с `authentication` шпион с localhost подключится **без пароля** через `skip-auth-prefixes`.

### Безопасная конфигурация (Вариант 1: глобальная)

```yaml
port: 7890
socks-port: 7891
mixed-port: 10801
allow-lan: false          # Не слушать на 0.0.0.0
bind-address: 127.0.0.1  # Только localhost

authentication:
  - "clash_x8f2a:p_k3m9v7c4b6"

# ✅ КРИТИЧНО: убрать localhost из skip-auth-prefixes
skip-auth-prefixes: []    # Пустой массив = auth для ВСЕХ
```

> ⚠️ **Побочный эффект:** некоторые приложения (Telegram, браузеры с настроенным прокси) могут потребовать ввод логина/пароля для подключения к локальному прокси. Если используете TUN-режим — это не проблема.

### Безопасная конфигурация (Вариант 2: per-listener)

Более гибкий подход — настроить auth на уровне отдельных listeners:

```yaml
listeners:
  - name: socks-local
    type: socks
    port: 7891
    listen: 127.0.0.1
    users:
      - username: clash_local
        password: s3cur3_p4ss_x7k9

  - name: mixed-local
    type: mixed
    port: 10801
    listen: 127.0.0.1
    udp: true
    users:
      - username: clash_local
        password: s3cur3_p4ss_x7k9

  - name: http-local
    type: http
    port: 7890
    listen: 127.0.0.1
    users:
      - username: clash_local
        password: s3cur3_p4ss_x7k9
```

> ⚠️ **Верификацией установлено:** per-listener `users` перезаписывает глобальный `authentication`, но **может НЕ перезаписывать** `skip-auth-prefixes`. Глобальный `skip-auth-prefixes` применяется на уровне сети и может обходить даже per-listener auth. **Рекомендация:** всегда устанавливать `skip-auth-prefixes: []` глобально, даже при использовании per-listener `users`.

### Инструкция по клиентам

**ClashMeta for Android** (v2.11.25+):
1. Откройте конфиг (Profile → Edit)
2. Добавьте `authentication` и `skip-auth-prefixes: []`
3. Или используйте `listeners` с `users`
4. Сохраните и перезапустите

**Clash Verge Rev** (Windows/macOS/Linux):
1. Профиль → правый клик → «Open File»
2. Отредактируйте YAML
3. Или: Settings → Merge Config → добавьте override

**FlClash:**
1. Аналогично — редактирование YAML профиля
2. Документация: [flclash.cc](https://flclash.cc/)

### Известные CVE Clash/mihomo

| CVE | Описание | Затронуто |
|-----|----------|-----------|
| **CVE-2024-5732** | Clash ≤ 0.20.1 Windows — обход аутентификации на Proxy Port (удалённый доступ) | Clash (не mihomo) |
| **CVE-2025-50505** | Clash Verge Rev — уязвимость API | Clash Verge Rev |
| **mihomo-party macOS** | Привилегированный UNIX-сокет `/tmp/mihomo-party-helper.sock` с world-rw правами, без аутентификации → перехват трафика | mihomo-party < 1.8.1 |

### Безопасность API mihomo

```yaml
# config.yaml
external-controller: 127.0.0.1:9090
secret: "ваш_секретный_токен"
```

> ⚠️ **Важно:** API-аутентификация через `Authorization: Bearer {secret}` **НЕ проверяется** при подключении через Unix-сокет или Windows named pipe. Защита — только file permissions (0600).

### Сводка по Clash/mihomo

| Метод | Эффективность | Сложность |
|-------|--------------|-----------|
| `authentication` + `skip-auth-prefixes: []` | ✅ Полная защита | Лёгкая (3 строки YAML) |
| Per-listener `users` | ✅ Полная, гибкая | Средняя |
| Только смена порта | 🟡 Слабая | Лёгкая |
| TUN без SOCKS-прокси | ✅ Нет прокси = нечего сканировать | Средняя |

**Вывод:** Clash/mihomo — **лучшая ситуация** из всех ядер. Auth поддерживается нативно, фикс — 3 строки в YAML. Нужно только убрать `127.0.0.1/8` из `skip-auth-prefixes`.

---

## 17. Фаерволы на Android: что реально работает

### Без root: почти ничего

| Приложение | Блокирует localhost? | Почему |
|------------|---------------------|--------|
| **NetGuard** (VPN-based) | ❌ **Нет** | Android VPN API не перехватывает localhost-трафик. VPN видит только трафик через сетевые интерфейсы, а loopback (127.0.0.1) — внутренний |
| **RethinkDNS** (VPN-based) | ❌ **Нет** | Та же причина — VPN API не покрывает localhost |
| **Blokada** (VPN-based) | ❌ **Нет** | Аналогично |
| **AdGuard** (VPN-based) | ❌ **Нет** (localhost) | Но блокирует скрипты Meta Pixel/Яндекс.Метрики на уровне DNS/HTTP — **полезно против трекинга** |

**Почему VPN-based фаерволы не помогают:**

```
┌─────────────────────────────────────────────────────┐
│                    Android                           │
│                                                     │
│  Приложение A ──→ 127.0.0.1:10808 ──→ xray/sing-box│
│       ↑                                             │
│       │ ← Это localhost, не проходит через VPN API  │
│       │                                             │
│  NetGuard/RethinkDNS (VPN) перехватывают ТОЛЬКО:    │
│       eth0, wlan0, rmnet0 (реальные интерфейсы)     │
│       ↓                                             │
│  Приложение B ──→ google.com ──→ [VPN перехватывает]│
└─────────────────────────────────────────────────────┘
```

Loopback-интерфейс — **внутренний**, он не маршрутизируется через VPN-тоннель. VPN API от Google **by design** не перехватывает localhost.

### С root: AFWall+ (iptables)

**AFWall+** ([github.com/ukanth/afwall](https://github.com/ukanth/afwall)) использует iptables **напрямую в ядре Linux**, минуя Android VPN API. Это единственный способ заблокировать localhost-доступ на Android.

**Установка:**
1. Убедитесь что есть root (Magisk/KernelSU)
2. Установите AFWall+ из F-Droid или GitHub
3. Откройте → разрешите root-доступ
4. Режим: **Whitelist** (разрешить только выбранным)

**Настройка кастомных правил:**

В AFWall+: **Меню** → **Set custom script** → добавьте:

```bash
# Защита SOCKS5-порта v2rayNG (10808)
# Разрешить только UID v2rayNG (замените 10150 на реальный UID)
iptables -I "afwall" -p tcp -d 127.0.0.1 --dport 10808 -m owner --uid-owner 10150 -j ACCEPT
iptables -I "afwall" -p tcp -d 127.0.0.1 --dport 10808 -j REJECT

# Защита HTTP-порта v2rayNG (10809)
iptables -A "afwall" -p tcp -d 127.0.0.1 --dport 10809 -m owner --uid-owner 10150 -j ACCEPT
iptables -A "afwall" -p tcp -d 127.0.0.1 --dport 10809 -j REJECT

# Защита mixed-порта NekoBox (2080)
# (замените 10200 на реальный UID NekoBox)
iptables -A "afwall" -p tcp -d 127.0.0.1 --dport 2080 -m owner --uid-owner 10200 -j ACCEPT
iptables -A "afwall" -p tcp -d 127.0.0.1 --dport 2080 -j REJECT
```

**Как узнать UID приложения:**
```bash
# Через adb
adb shell dumpsys package com.v2ray.ang | grep userId
# userId=10150

adb shell dumpsys package moe.nb4a | grep userId
# userId=10200
```

Или в AFWall+ UI: каждое приложение показывает свой UID в скобках.

**Важно:** правила iptables сбрасываются при перезагрузке. AFWall+ автоматически применяет кастомный скрипт при каждом старте — поэтому используйте именно AFWall+, а не ручные iptables.

### Без root: что хоть немного помогает

1. **AdGuard DNS** — блокирует скрипты Meta Pixel и Яндекс.Метрики, которые могут обнаруживать VPN через localhost. Не защищает от прямого сканирования шпионским модулем, но убирает трекинг из браузера.

2. **Brave Browser** — с 2022 года блокирует запросы к localhost из веб-страниц. Защищает от трекинга Meta/Яндекс через браузер, но не от нативного шпионского приложения.

3. **Отдельное устройство** — физическая изоляция. Российское ПО на одном телефоне, VPN на другом. Loopback не пересекается между устройствами.

---

## 18. FAQ: hev-socks5-tunnel, Karing, Husi, v2rayN

### Q: Как включить auth, если я не владелец подписки?

**A: Владение подпиской НЕ имеет значения.** SOCKS5-аутентификация на local inbound — это **чисто клиентская настройка**. Она защищает локальный прокси на ВАШЕМ устройстве от других приложений. Сервер подписки об этом даже не знает.

```
СЕРВЕР (владелец подписки)          ВАШЕ УСТРОЙСТВО (вы контролируете)
┌──────────────────────┐            ┌──────────────────────────────┐
│ VLESS Reality inbound│◄──────────│ xray outbound (VLESS)        │
│ Вы НЕ контролируете  │  туннель  │                              │
└──────────────────────┘            │ SOCKS5 inbound ← ВОТ ЭТО   │
                                    │ localhost:10808   ВАШЕ      │
                                    │ auth: password ← МЕНЯТЬ ТУТ │
                                    └──────────────────────────────┘
```

**Реальная проблема:** при обновлении подписки некоторые клиенты перегенерируют конфиг и могут **сбросить** ваши кастомные inbound-настройки. Но это зависит от клиента:

- **v2rayN** (Windows) ✅ — хранит inbound-настройки (`Config.Inbound`) в `guiNConfig.json` **отдельно** от подписок (SQLite `guiN.db`). Auth **не сбрасывается** при обновлении подписки. Архитектура подтверждена через DeepWiki и исходный код.
- **Clash/mihomo** ✅ — `authentication` и `skip-auth-prefixes` в глобальной секции config.yaml. `proxy-providers` (подписки) обновляют **только список прокси**, не трогая глобальный конфиг. Clash Verge Rev дополнительно защищает глобальные настройки через Merge-профили.
- **Husi** (Android) ⚠️ — вероятно сохраняет auth в настройках приложения, но **документально не подтверждено**. Рекомендуется проверить auth после каждого обновления подписки.
- **v2rayNG** (Android) ⚠️ — custom config **проблематичен**. Известные проблемы: нет документации какие секции custom config реально применяются — пользователи вынуждены спрашивать ([#275](https://github.com/2dust/v2rayNG/issues/275) — «How to use custom config feature?»), краши при кастомных DNS-конфигурациях ([#1911](https://github.com/2dust/v2rayNG/issues/1911) — «V2ray Crash When using custom config»), игнорирование кастомных DNS при включённом local DNS ([#3670](https://github.com/2dust/v2rayNG/issues/3670)). Прямых доказательств перезаписи auth при обновлении подписки не найдено, но стабильность custom config не гарантирована — **не рекомендуется** как единственный метод защиты. Надёжнее перейти на Husi.

### Q: Нужно ли просить админа сервера что-то менять?

**A:** Для защиты local inbound — **нет**. Но для полной защиты **рекомендуется** попросить админа:
- Настроить раздельные входной/выходной IP (или WARP)
- Заблокировать geoip:ru на outbound
- Заблокировать Happ по UserAgent

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

## 19. CVE-2023-43644: обход аутентификации sing-box

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

## 20. Чеклист действий

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

---
tags:
link:
aliases:
img:
---
# Типы фильтров (*профилей*) в [[Zapret2]] и их параметры

Фильтры в nfqws2 определяют, какие пакеты/соединения будут обрабатываться профилем мультистратегии. *Не путать с начальными входящими [[wf|фильтрами WinDivert]]!*

---

## 📋 **Основные типы фильтров**

### 1. **`--filter-l3`** - Фильтр L3 протокола (IP версия)

**Синтаксис:**
```bash
--filter-l3=ipv4|ipv6
```

**Параметры:**
- `ipv4` - только IPv4 пакеты
- `ipv6` - только IPv6 пакеты
- Можно указывать несколько через запятую

**Примеры:**
```bash
--filter-l3=ipv4           # только IPv4
--filter-l3=ipv6           # только IPv6
--filter-l3=ipv4,ipv6      # оба (по умолчанию)
```

---

### 2. **`--filter-tcp`** - Фильтр TCP портов

**Синтаксис:**
```bash
--filter-tcp=[~]port1[-port2]|*
```

**Параметры:**
- `port` - конкретный порт (например: `80`)
- `port1-port2` - диапазон портов (например: `1000-2000`)
- `~port` - отрицание (все кроме указанного)
- `*` - все порты
- Можно указывать несколько через запятую

**Особенности:**
- Если указан `--filter-tcp` и НЕ указан `--filter-udp`, то UDP **блокируется**
- Фильтрует как source, так и destination порты

**Примеры:**
```bash
--filter-tcp=80,443        # только порты 80 и 443
--filter-tcp=80-443        # диапазон от 80 до 443
--filter-tcp=~443          # все порты КРОМЕ 443
--filter-tcp=*             # все TCP порты
```

---

### 3. **`--filter-udp`** - Фильтр UDP портов

**Синтаксис:**
```bash
--filter-udp=[~]port1[-port2]|*
```

**Параметры:** (аналогично TCP)
- `port` - конкретный порт
- `port1-port2` - диапазон портов
- `~port` - отрицание
- `*` - все порты
- Можно указывать несколько через запятую

**Особенности:**
- Если указан `--filter-udp` и НЕ указан `--filter-tcp`, то TCP **блокируется**

**Примеры:**
```bash
--filter-udp=443           # QUIC (UDP/443)
--filter-udp=53,443        # DNS и QUIC
--filter-udp=*             # все UDP порты
```

---

### 4. **`--filter-l7`** - Фильтр L7 протокола

**Синтаксис:**
```bash
--filter-l7=proto[,proto,...]
```

**Доступные протоколы:**
1. `all` - все протоколы
2. `unknown` - неопознанные протоколы
3. `known` - все известные протоколы
4. `http` - HTTP протокол
5. `tls` - TLS/SSL (HTTPS)
6. `quic` - QUIC (HTTP/3)
7. `wireguard` - WireGuard VPN
8. `dht` - DHT (BitTorrent)
9. `discord` - Discord протокол
10. `stun` - STUN
11. `xmpp` - XMPP (Jabber)
12. `dns` - DNS
13. `mtproto` - MTProto (Telegram)

**Примеры:**
```bash
--filter-l7=http           # только HTTP
--filter-l7=tls,http       # TLS и HTTP
--filter-l7=quic           # только QUIC
--filter-l7=known          # все известные протоколы
```

---

### 5. **`--filter-ssid`** - Фильтр по WiFi SSID (только на некоторых платформах)

**Синтаксис:**
```bash
--filter-ssid=ssid1[,ssid2,ssid3,...]
```

**Параметры:**
- Список SSID через запятую
- Применяется только к указанным WiFi сетям

**Пример:**
```bash
--filter-ssid=MyHomeWiFi,OfficeNetwork
```

![[ipset]]

![[hostlist]]
## 💡 **Комбинированные примеры**

### Пример 1: Базовая фильтрация HTTP/HTTPS
```bash
nfqws2 \
  --filter-tcp=80,443 \
  --filter-l7=http,tls \
  --lua-desync=fake:blob=fake_default_tls
```

### Пример 2: QUIC с hostlist
```bash
nfqws2 \
  --filter-udp=443 \
  --filter-l7=quic \
  --hostlist=/path/to/youtube.txt \
  --lua-desync=fake:blob=fake_default_quic:repeats=6
```

### Пример 3: Мультипрофиль с разными фильтрами
```bash
nfqws2 \
  --filter-tcp=80 --filter-l7=http \
  --hostlist=/path/to/list1.txt \
  --lua-desync=multisplit \
  --new \
  --filter-tcp=443 --filter-l7=tls \
  --hostlist-exclude=/path/to/exclude.txt \
  --lua-desync=fake:blob=fake_default_tls \
  --new \
  --filter-udp=443 --filter-l7=quic \
  --lua-desync=fake:blob=fake_default_quic
```

### Пример 4: Автоматический hostlist
```bash
nfqws2 \
  --filter-tcp=443 --filter-l7=tls \
  --hostlist-auto=/var/lib/zapret/auto.txt \
  --hostlist-auto-fail-threshold=3 \
  --hostlist-auto-fail-time=60 \
  --hostlist-auto-retrans-threshold=2 \
  --lua-desync=fake:blob=fake_default_tls
```

### Пример 5: IP фильтрация
```bash
nfqws2 \
  --filter-tcp=443 \
  --ipset=/path/to/blocked_ips.txt \
  --ipset-exclude-ip=192.168.0.0/16,10.0.0.0/8 \
  --lua-desync=fake:blob=fake_default_tls
```

---

## 📝 **Важные особенности**

1. **Порядок фильтров:** Фильтры применяются последовательно (AND логика)
2. **TCP/UDP взаимоисключение:** Указание только TCP фильтра блокирует UDP и наоборот
3. **Hostlist subdomains:** Поддомены включаются автоматически
4. **Множественные файлы:** Можно указывать несколько `--ipset`, `--hostlist` и т.д.
5. **Gzip поддержка:** Файлы могут быть сжаты gzip
6. **Профили:** Каждый профиль (разделенный `--new`) имеет свои фильтры

Фильтры позволяют точно таргетировать desync-стратегии на нужные соединения, минимизируя нагрузку на систему!
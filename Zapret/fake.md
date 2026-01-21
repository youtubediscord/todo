---
date: 2026-01-21
tags:
  - zapret
  - zapret2
  - nfqws2
  - lua
  - lua-desync
  - antidpi
  - fake
aliases:
---

# `fake` (zapret / nfqws2)

Документация по Lua-функции `fake(ctx, desync)` из `lua/zapret-antidpi.lua`.

`fake` — **прямой фейк**: отправляет отдельный пакет/пакеты с указанным `blob` (возможна автосегментация по MSS для TCP), **не выносит вердикт** и **не блокирует** отправку оригинала. То есть в типичной схеме DPI видит “мусорный” пакет + затем оригинальный трафик.

Фейк почти всегда требует “порчи” заголовков (standard fooling), чтобы сервер/приложение **не приняло** фейковый payload.

## Где смотреть в коде

- `lua/zapret-antidpi.lua` — `fake(ctx, desync)` (см. комментарии над функцией)
- `lua/zapret-lib.lua` — `tls_mod_shim()` (поддержка `sni=%var`) и отправка `rawsend_payload_segmented()`
- `nfq2/protocol.c` — `TLSMod_parse_list()` / `TLSMod()` (реальная логика `tls_mod=...`)

## Быстрый старт

### TLS fake (типичный)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5
```

### HTTP fake (типичный)
```bash
--payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5
```

## Что именно делает `fake` (логика)

Упрощённо:

1) проверяет `dir`/`payload` фильтры (дефолты: `dir=out`, `payload=known`)  
2) работает только на первом `replay`-куске (`replay_first`)  
3) требует `blob=...` (иначе `error`)  
4) если `optional` и blob отсутствует → skip  
5) берёт данные blob как `fake_payload`  
6) если есть `desync.reasm_data` и задан `tls_mod=...` → применяет TLS-модификации через `tls_mod_shim()`  
7) отправляет `fake_payload` через `rawsend_payload_segmented()` (с учётом standard args: fooling/ip_id/rawsend/reconstruct/ipfrag)

## Полный список аргументов `fake` и какие значения они принимают

### A) Собственные аргументы `fake`

#### `blob` (обязательный)
- **Формат:** `blob=<blobName>`
- **Тип:** имя blob‑переменной (загружается через `--blob=<name>:@file|0xHEX` или уже существует в Lua как глобал/поле `desync`)
- **Важно:** без `blob` функция падает с ошибкой: `fake: 'blob' arg required`
- **Длина:** может быть любой; для TCP сегментация делается автоматически по MSS

#### `optional`
- **Формат:** `optional` (флаг)
- **Смысл:** если `blob` отсутствует → ничего не делать (без ошибки)

#### `tls_mod`
- **Формат:** `tls_mod=<commaSeparatedList>`
- **Тип:** строка вида `opt1,opt2,opt3...`
- **Когда применяется в `fake`:** только если есть `desync.reasm_data` (обычно при сборке/перепроигрывании `reasm` для `tls_client_hello`)
- **Опции `tls_mod`:**
  - `none` — ничего не делать
  - `rnd` — рандомизировать поля TLS ClientHello: `Random` (32 байта) и `Session ID` (байты, длина берётся из самого ClientHello)
  - `rndsni` — рандомизировать строку SNI (домен) в TLS ClientHello
  - `sni=<host>` — заменить SNI на указанный хост (меняет длины внутри TLS структур)
  - `dupsid` — скопировать `Session ID` из **оригинального** ClientHello (из `desync.reasm_data`) в фейк (требует совпадения длины session id)
  - `padencap` — “TLS padding encapsulation”: гарантирует наличие padding extension (type 21) в конце и увеличивает поля длины TLS record/handshake/extensions/padding на `len(original_payload)`

##### `sni=%var` (подстановка внутри `tls_mod`)
Есть специальная поддержка для записи вида `tls_mod=sni=%var` *внутри строки*:

- пример: `tls_mod=sni=%target`
- `%target` берётся как `desync.target` (если есть) или как глобальная переменная Lua `target`
- если переменной нет → ошибка `tls_mod_shim: non-existent var 'target'`

Это именно “внутренняя” подстановка **не на старте значения аргумента**, а внутри строки `tls_mod`.

---

### B) Standard args (общие, но реально влияют на отправку фейка)

#### 1) `dir` (standard direction)
- `dir=in|out|any` (дефолт `out`)

#### 2) `payload` (standard payload)
- `payload=type1[,type2,...]` или `payload=known|all`
- поддерживает инверсию: `payload=~type1[,type2,...]`
- дефолт `known`

#### 3) Fooling (standard fooling) — крайне важно для fake
Любые поля из standard fooling применяются к отправляемому фейку: TTL/HL, TCP options, TCP flags, и т.д.
Часто используют: `tcp_md5`, `badsum`, `tcp_flags_unset=ack`, `ip_ttl=1`, `ip6_ttl=1`.

#### 4) IPID (standard ipid)
- `ip_id=seq|rnd|zero|none`
- `ip_id_conn` (флаг)

#### 5) Reconstruct (standard reconstruct)
- `badsum` (флаг)

#### 6) Rawsend (standard rawsend)
- `repeats=N`
- `ifout=<iface>`
- `fwmark=N`

#### 7) IP fragmentation (standard ipfrag)
Включается, только если указать `ipfrag` (даже без значения):

- `ipfrag[=frag_function]` — если значение пустое, используется `ipfrag2`
- `ipfrag_disorder` (флаг) — слать IP-фрагменты с последнего к первому
- `ipfrag_pos_udp=N` (кратно 8; дефолт 8) — только для `ipfrag2` (актуально для UDP, напр. `quic_initial`)
- `ipfrag_pos_tcp=N` (кратно 8; дефолт 32) — только для `ipfrag2`
- `ipfrag_next=N` — только для `ipfrag2` (IPv6 “next header” во 2-м фрагменте)

## Нюансы поведения (частые ловушки)

### 1) `fake` не делает `DROP`
Оригинальный пакет уйдёт следом (если другие инстансы не дропнут его). Это ожидаемо.

### 2) `fake` действует только на первом `replay`-куске
Если пакет — часть replay, на последующих частях `fake` ничего не делает.

### 3) `tls_mod` внутри `fake` может “не сработать”
В `fake` TLS-модификация вызывается только если есть `desync.reasm_data`. Если её нет, а вы хотите `rnd/rndsni/sni=...`, можно заранее подготовить blob:

```bash
--lua-init="fake_default_tls=tls_mod(fake_default_tls,'rnd,rndsni')"
```

## Примеры (15 штук)

### 1) Минимальный fake для TLS (обязателен `blob`)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5
```

### 2) Минимальный fake для HTTP
```bash
--payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5
```

### 3) `optional`: тихо пропустить, если blob не загружен
```bash
--payload=tls_client_hello --lua-desync=fake:blob=maybe_missing:optional:tcp_md5
```

### 4) Повторы отправки фейка (каждый сегмент/пакет N раз)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=5
```

### 5) Рандомизировать Random + Session ID в фейковом ClientHello
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd
```

### 6) Рандомизировать SNI
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rndsni
```

### 7) Поменять SNI на конкретный домен
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=sni=www.google.com
```

### 8) `sni=%var` внутри `tls_mod` (подстановка из Lua-переменной)
```bash
--lua-init="target='www.google.com'" --payload=tls_client_hello \
--lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=sni=%target
```

### 9) `dupsid`: скопировать session id из реального ClientHello в фейк
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=dupsid
```

### 10) `padencap`: “увеличить” длины TLS и padding extension (для путаницы DPI)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=padencap
```

### 11) Комбо `rnd,rndsni,dupsid,padencap` (как в типовых пресетах)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap
```

### 12) “Жёсткий” фулинг через TTL/HL (часто используют для прямых фейков)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:ip_ttl=1:ip6_ttl=1:tcp_md5
```

### 13) Портить checksum (`badsum`) + убирать ACK (пример из совместимости с nfqws1-подходами)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:badsum:tcp_flags_unset=ack:tls_mod=rnd,dupsid,padencap
```

### 14) Включить IP-фрагментацию `ipfrag2` для фейка (TCP)
```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:ipfrag:ipfrag_pos_tcp=32
```

### 15) UDP/QUIC: фейк + `ipfrag_pos_udp`
```bash
--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ipfrag:ipfrag_pos_udp=8
```


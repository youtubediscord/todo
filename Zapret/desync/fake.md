---
date: 2026-02-17
tags:
  - zapret
  - zapret2
  - nfqws2
  - lua
  - lua-desync
  - antidpi
  - tcp
  - udp
  - fake
aliases:
  - fake
---

# `fake` — прямой фейк (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:438`
**nfqws1 эквивалент:** `--dpi-desync=fake`
**Сигнатура:** `function fake(ctx, desync)`

`fake` — самая часто используемая функция в zapret. Она отправляет **отдельный** пакет (или группу пакетов) с фейковым payload из указанного blob. При этом функция **не выносит вердикт** и **не блокирует** отправку оригинала — оригинальный пакет уходит следом. DPI видит сначала фейк, затем настоящий трафик. Задача фейка — "отравить" состояние DPI ложными данными (неверный SNI, невалидный HTTP-запрос и т.д.).

Работает с **TCP и UDP** (в отличие от функций сегментации, которые только TCP).

Родственные функции: [[syndata]] (payload в SYN), [[fakedsplit]] (фейки + сегментация), [[fakeddisorder]] (фейки + обратный порядок), [[multisplit]] (чистая сегментация), [[multidisorder]] (сегментация в обратном порядке).

---

## Оглавление

- [Зачем нужен fake](#зачем-нужен-fake)
- [Быстрый старт](#быстрый-старт)
- [Как fake работает внутри](#как-fake-работает-внутри)
- [blob — источник фейковых данных](#blob--источник-фейковых-данных)
  - [Стандартные blob-ы](#стандартные-blob-ы)
  - [Пользовательские blob-ы](#пользовательские-blob-ы)
- [tls_mod — модификации TLS в фейке](#tls_mod--модификации-tls-в-фейке)
  - [Опции tls_mod](#опции-tls_mod)
  - [Подстановка sni=%var](#подстановка-snivar)
  - [Когда tls_mod применяется, а когда нет](#когда-tls_mod-применяется-а-когда-нет)
  - [padencap — подробности](#padencap--подробности)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы fake](#a-собственные-аргументы-fake)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard ipfrag](#f-standard-ipfrag)
  - [G) Standard reconstruct](#g-standard-reconstruct)
  - [H) Standard rawsend](#h-standard-rawsend)
- [Автосегментация по MSS](#автосегментация-по-mss)
- [Поведение при replay / reasm](#поведение-при-replay--reasm)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Сравнение с syndata и fakedsplit](#сравнение-с-syndata-и-fakedsplit)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен fake

DPI анализирует первые пакеты TCP/UDP-потока, ища сигнатуры (SNI в TLS ClientHello, Host в HTTP, QUIC Initial). Если **перед** настоящим пакетом отправить фейковый пакет с ложными данными, DPI может:

1. **Принять фейк за реальный трафик:** DPI обработает фейковый SNI/Host и примет решение на его основе — пропустит соединение
2. **Сбиться с состояния:** получив невалидные данные, DPI потеряет контекст потока и перестанет его анализировать
3. **Не суметь заблокировать:** если DPI блокирует по hostname, а в фейке другой hostname — реальный запрос может пройти

При этом **сервер должен отбросить фейк**. Для этого к фейку применяется fooling — порча заголовков (TTL, badseq, md5sig, badsum), из-за которой сервер или промежуточные маршрутизаторы отбрасывают пакет, а DPI — нет.

**fake** — "огонь по площадям": он шлёт фейк отдельным пакетом, не трогая оригинал. Для более тонкой работы (замешивание фейков внутри сегментов) используйте [[fakedsplit]]/[[fakeddisorder]], для скрытых фейков через TCP window — seqovl в [[multisplit]]/[[multidisorder]].

---

## Быстрый старт

Минимальный TLS-фейк (обязателен `blob` + fooling):

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5
```

Минимальный HTTP-фейк:

```bash
--payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5
```

QUIC-фейк (UDP):

```bash
--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ip_ttl=1:ip6_ttl=1
```

Типовая боевая связка fake + [[multisplit]]:

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap \
  --lua-desync=multisplit:pos=1,midsld
```

---

## Как fake работает внутри

Логика функции `fake(ctx, desync)` в упрощённом виде:

1. Вызывает `direction_cutoff_opposite` — отсекает себя от противоположного направления (при `dir=out` не будет вызываться для входящих, и наоборот)
2. Проверяет, что пакет TCP **или** UDP (иначе — ничего не делает, но НЕ отсекается)
3. Проверяет направление (`direction_check`) и тип payload (`payload_check`)
4. Работает только на **первом** replay-куске (`replay_first`)
5. Требует `blob=...` — если не задан, вызывает `error()` (Lua exception)
6. Если задан `optional` и blob не существует — тихий пропуск
7. Загружает blob как `fake_payload`
8. Если есть `desync.reasm_data` **и** задан `tls_mod` — применяет TLS-модификации
9. Отправляет `fake_payload` через `rawsend_payload_segmented` (с учётом fooling, ip_id, reconstruct, ipfrag, rawsend)
10. **Не возвращает вердикт** — оригинальный пакет уходит как есть

---

## blob — источник фейковых данных

`blob` — обязательный аргумент `fake`. Он указывает, **что** именно отправить в качестве фейкового payload.

### Стандартные blob-ы

Zapret автоматически создаёт три стандартных blob-а при инициализации:

| Blob | Описание | Типичное использование |
|:-----|:---------|:-----------------------|
| `fake_default_tls` | Валидный TLS ClientHello с SNI `www.w3.org` | `--payload=tls_client_hello` |
| `fake_default_http` | Валидный HTTP GET запрос | `--payload=http_req` |
| `fake_default_quic` | QUIC Initial пакет | `--payload=quic_initial` |

Эти blob-ы содержат полноценные протокольные структуры, которые DPI может распознать и обработать. Именно поэтому `fake_default_tls` — самый частый выбор для TLS-фейков: DPI парсит его как настоящий ClientHello, видит `www.w3.org` вместо заблокированного домена.

### Пользовательские blob-ы

```bash
# Inline hex (произвольные байты)
--lua-desync=fake:blob=0xDEADBEEF:tcp_md5

# Нулевые байты (4 байта нулей)
--lua-desync=fake:blob=0x00000000:ip_ttl=6:ip6_ttl=6

# Из файла (предзагруженный)
--blob=my_fake_ch:@/path/to/custom_clienthello.bin
--lua-desync=fake:blob=my_fake_ch:tcp_md5

# Из Lua-переменной (например, клонированный ClientHello)
--lua-desync=tls_client_hello_clone:blob=cloned_ch:sni_del:sni_add=www.google.com
--lua-desync=fake:blob=cloned_ch:tcp_md5
```

Blob разрешается функцией `blob_exist()` / `blob()` в следующем порядке:

1. Если имя начинается с `0x` — inline hex, создаётся на лету
2. `desync[name]` — поле в текущем контексте desync (например, сгенерированное `tls_client_hello_clone`)
3. `_G[name]` — глобальная Lua-переменная (например, `fake_default_tls`)

---

## tls_mod — модификации TLS в фейке

`tls_mod` позволяет модифицировать содержимое blob-а перед отправкой, подстраивая фейковый ClientHello под текущее соединение. Это делает фейк более убедительным для DPI.

### Опции tls_mod

| Опция | Описание | Требования |
|:------|:---------|:-----------|
| `none` | Ничего не делать | — |
| `rnd` | Заполнить поля `Random` (32 байта) и `Session ID` случайными данными | blob должен содержать валидный TLS ClientHello |
| `rndsni` | Заменить SNI на случайный домен. Если длина оригинального SNI >= 7 символов — случайный поддомен из известных 3-буквенных TLD. Иначе — случайные символы `[a-z][a-z0-9]*` | blob должен содержать SNI extension |
| `sni=<domain>` | Заменить SNI на конкретный домен (изменяет длины внутри TLS-структур) | blob должен содержать SNI extension |
| `dupsid` | Скопировать Session ID из **оригинального** payload (из `desync.reasm_data`) в фейк. Выполняется после `rnd`. Требует совпадения длин session id | валидный TLS в `reasm_data` |
| `padencap` | Подкорректировать blob так, чтобы оригинальный payload стал частью padding extension. Увеличивает поля длины TLS record/handshake/extensions/padding на `len(original_payload)` | blob должен содержать padding extension (type 21) |

**Порядок применения модов:** они применяются в порядке перечисления, но `dupsid` всегда выполняется после `rnd` (чтобы рандомизированный Session ID был перезаписан реальным).

### Подстановка sni=%var

Внутри `tls_mod` поддерживается специальная запись `sni=%variable`:

```bash
# Подстановка из desync.target (устанавливается механизмом hostlist)
--lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=sni=%target

# Подстановка из глобальной Lua-переменной
--lua-init="my_domain='www.google.com'" \
--lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=sni=%my_domain
```

Порядок поиска переменной:
1. `desync[var]` — поле в текущем контексте desync
2. `_G[var]` — глобальная Lua-переменная

Если переменная не найдена — вызывается `error("tls_mod_shim: non-existent var 'varname'")`.

### Когда tls_mod применяется, а когда нет

В `fake` tls_mod вызывается **только если одновременно выполнены оба условия:**

1. `desync.reasm_data` существует (обычно есть при TLS ClientHello, который был реассемблирован)
2. Аргумент `tls_mod` задан

Если `reasm_data` отсутствует (например, маленький пакет, не потребовавший реассемблирования, или UDP) — `tls_mod` **молча пропускается**, без ошибок. Это отличие от [[syndata]], где `tls_mod` вызывается всегда (с `payload=nil`), потому что syndata работает на SYN-пакете, где никакого реального payload ещё нет.

**Обходной путь**, если tls_mod нужен без reasm_data:

```bash
# Заранее модифицировать blob через lua-init
--lua-init="fake_default_tls=tls_mod(fake_default_tls,'rnd,rndsni')"
```

### padencap — подробности

`padencap` — техника, при которой фейковый blob подготавливается так, чтобы **реальный payload**, отправленный следом, воспринимался DPI как продолжение padding extension в фейковом ClientHello. DPI, парсящий TLS, может объединить фейк и оригинал в один record, и реальный SNI окажется "внутри" padding — невидим для анализа.

Для этого в blob должна присутствовать padding extension (type 0x0015), а `padencap` увеличивает все поля длины (TLS record length, Handshake length, Extensions length, Padding extension length) на `len(original_payload)`.

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=fake[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`, `:tcp_md5`, `:badsum`.

### A) Собственные аргументы fake

#### `blob` (обязательный)

- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной (загружается через `--blob=<name>:@file|0xHEX`, через `desync[name]` или как глобальная Lua-переменная)
- **По умолчанию:** нет (обязательный аргумент)
- **Описание:** Blob, содержащий фейковый payload. Может быть любой длины — для TCP сегментация по MSS выполняется автоматически. Для UDP отправляется как есть
- **Ошибка:** если `blob` не указан, вызывается `error("fake: 'blob' arg required")` — Lua exception, останавливающий обработку пакета
- **Примеры:**
  - `blob=fake_default_tls` — стандартный TLS-фейк
  - `blob=fake_default_http` — стандартный HTTP-фейк
  - `blob=fake_default_quic` — стандартный QUIC-фейк
  - `blob=0xDEADBEEF` — inline hex
  - `blob=0x00000000` — четыре нулевых байта
  - `blob=my_custom_blob` — предзагруженный или сгенерированный blob

#### `optional`

- **Формат:** `optional` (флаг, без значения)
- **Описание:** Если blob отсутствует (не найден ни как inline hex, ни как `desync[name]`, ни как `_G[name]`) — тихий пропуск без ошибки. Без `optional` отсутствие blob-а вызывает `error()`
- **Использование:** защита от ошибок при использовании blob-ов, которые могут отсутствовать (например, генерируемых `tls_client_hello_clone` — если payload не TLS, clone не создаст blob)

#### `tls_mod`

- **Формат:** `tls_mod=<commaSeparatedList>`
- **Тип:** строка вида `opt1,opt2,...`
- **По умолчанию:** не задан (модификации не применяются)
- **Описание:** Список TLS-модификаций, применяемых к blob перед отправкой. Работает только при наличии `desync.reasm_data`
- **Опции:** `none`, `rnd`, `rndsni`, `sni=<domain>`, `dupsid`, `padencap`
- **Подстановка:** `sni=%variable` — подстановка из `desync[var]` или `_G[var]`
- **Примеры:**
  - `tls_mod=rnd` — рандомизировать Random и Session ID
  - `tls_mod=rnd,rndsni,dupsid` — рандомизировать + случайный SNI + скопировать реальный Session ID
  - `tls_mod=rnd,rndsni,dupsid,padencap` — полный набор модификаций
  - `tls_mod=sni=www.google.com` — конкретный домен в SNI
  - `tls_mod=sni=%target` — подстановка из переменной target

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `fake` по умолчанию работает только с исходящими (`out`).

- `dir=out` — только исходящие (от клиента к серверу)
- `dir=in` — только входящие (от сервера к клиенту)
- `dir=any` — оба направления

При первом вызове с указанным `dir` функция делает `direction_cutoff_opposite` — отсекает себя от противоположного направления.

---

### C) Standard payload

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `payload` | список типов через запятую | `known` |

Фильтр по типу payload на уровне Lua. Это **дополнительный** фильтр к `--payload=...` на уровне профиля.

- `payload=known` — только распознанные протоколы (`http_req`, `tls_client_hello`, `quic_initial` и т.д.)
- `payload=all` — любой payload, включая `unknown`
- `payload=tls_client_hello,http_req` — конкретные типы
- `payload=~unknown` — инверсия: всё кроме unknown

**Важно:** лучше ставить `--payload=...` на уровне профиля (C-код, быстрее), а не полагаться только на Lua-фильтр.

---

### D) Standard fooling

Модификации L3/L4 заголовков. В `fake` fooling применяется **только к фейковым пакетам** (а не к оригиналу — тот уходит без изменений). Это ключевое отличие от [[multisplit]], где fooling идёт на все сегменты.

| Параметр | Описание | Пример |
|:---------|:---------|:-------|
| `ip_ttl=N` | Установить IPv4 TTL | `ip_ttl=6` |
| `ip6_ttl=N` | Установить IPv6 Hop Limit | `ip6_ttl=6` |
| `ip_autottl=delta,min-max` | Автоматический TTL (delta от серверного TTL) | `ip_autottl=-2,40-64` |
| `ip6_autottl=delta,min-max` | Аналогично для IPv6 | `ip6_autottl=-2,40-64` |
| `ip6_hopbyhop[=HEX]` | Вставить extension header hop-by-hop (по умолчанию 6 нулей) | `ip6_hopbyhop` |
| `ip6_hopbyhop2[=HEX]` | Второй hop-by-hop header | `ip6_hopbyhop2` |
| `ip6_destopt[=HEX]` | Destination options header | `ip6_destopt` |
| `ip6_destopt2[=HEX]` | Второй destination options | `ip6_destopt2` |
| `ip6_routing[=HEX]` | Routing header | `ip6_routing` |
| `ip6_ah[=HEX]` | Authentication header | `ip6_ah` |
| `tcp_seq=N` | Сместить TCP sequence (+ или -) | `tcp_seq=-10000` |
| `tcp_ack=N` | Сместить TCP ack (+ или -) | `tcp_ack=-66000` |
| `tcp_ts=N` | Сместить TCP timestamp | `tcp_ts=-100` |
| `tcp_md5[=HEX]` | Добавить TCP MD5 option (16 байт; по умолчанию случайные) | `tcp_md5` |
| `tcp_flags_set=LIST` | Установить TCP-флаги | `tcp_flags_set=FIN,PUSH` |
| `tcp_flags_unset=LIST` | Снять TCP-флаги | `tcp_flags_unset=ACK` |
| `tcp_ts_up` | Поднять TCP timestamp option в начало заголовка | `tcp_ts_up` |
| `tcp_nop_del` | Удалить все TCP NOP опции | `tcp_nop_del` |
| `fool=<func>` | Кастомная Lua-функция fooling | `fool=my_fooler` |

**Типичные комбинации fooling для fake:**

- `tcp_md5` — самый популярный. Серверы (Linux) отбрасывают пакеты с TCP MD5 option, если MD5-аутентификация не настроена
- `ip_ttl=1:ip6_ttl=1` — TTL=1: фейк не дойдёт до сервера, но DPI на пути его увидит
- `badsum` — испорченная контрольная сумма: сервер отбросит, DPI может пропустить
- `tcp_flags_unset=ACK` — datanoack: убрать ACK-флаг, сервер отбросит пакет без ACK в установленном соединении
- `tcp_seq=-10000` — badseq: невалидный sequence number, сервер отбросит

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | — |
| `ip_id=zero` | Нулевые IP ID | — |
| `ip_id=none` | Не менять IP ID | — |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения (требует tracking) | — |

`ip_id` применяется к **каждому** отправляемому пакету (включая под-сегменты при MSS-сегментации для TCP).

---

### F) Standard ipfrag

IP-фрагментация фейковых пакетов. Каждый пакет дополнительно фрагментируется на уровне IP.

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ipfrag[=func]` | Включить IP-фрагментацию. Если без значения — `ipfrag2` | — |
| `ipfrag_disorder` | Отправить IP-фрагменты в обратном порядке | — |
| `ipfrag_pos_tcp=N` | Позиция фрагментации TCP (кратно 8) | `32` |
| `ipfrag_pos_udp=N` | Позиция фрагментации UDP (кратно 8). Актуально для QUIC-фейков | `8` |
| `ipfrag_next=N` | IPv6: next protocol во 2-м фрагменте (penetration атака на фаерволы) | — |

---

### G) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP/UDP) checksum при реконструкции raw-пакета. Сервер отбросит такой пакет |

---

### H) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить каждый пакет/сегмент N раз (идентичные повторы) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

---

## Автосегментация по MSS

Для TCP о размерах пакетов думать **не нужно**. Функция `rawsend_payload_segmented` из `zapret-lib.lua` автоматически:

1. Отслеживает MSS для каждого TCP-соединения
2. Если blob превышает MSS — автоматически режет по MSS
3. Каждый под-сегмент отправляется с корректным TCP sequence

**Пример:** blob из 10000 байт при MSS=1460 будет отправлен как 7 TCP-сегментов (6 x 1460 + 1 x 240).

Для UDP сегментации нет — blob отправляется как один UDP-пакет. Если blob больше MTU, пакет будет фрагментирован на уровне IP (или отброшен, если DF-бит установлен).

---

## Поведение при replay / reasm

`fake` работает **только на первом** replay-куске. При многопакетных payload (например, большой TLS ClientHello с post-quantum Kyber):

1. **Первая часть replay:** `replay_first(desync)` возвращает `true` — fake отправляет фейковый пакет
2. **Все последующие части replay:** `replay_first(desync)` возвращает `false` — fake логирует "not acting on further replay pieces" и ничего не делает

Так как fake **не выносит вердикт**, последующие части replay проходят насквозь (другие инстансы в цепочке могут их обработать — например, [[multisplit]] разрежет весь reasm).

---

## Псевдокод алгоритма

```lua
function fake(ctx, desync)
    -- 1. Cutoff противоположного направления
    direction_cutoff_opposite(ctx, desync)

    -- 2. Проверка: только TCP или UDP
    if not (desync.dis.tcp or desync.dis.udp) then return end

    -- 3. Проверки: направление OK, payload OK
    if not direction_check(desync) then return end
    if not payload_check(desync) then return end

    -- 4. Только первый replay
    if replay_first(desync) then

        -- 5. blob обязателен
        if not desync.arg.blob then
            error("fake: 'blob' arg required")
        end

        -- 6. optional: тихий пропуск если blob нет
        if optional and not blob_exist(desync, desync.arg.blob) then
            DLOG("fake: blob not found. skipped")
            return  -- НЕ error, просто return
        end

        -- 7. Загрузка blob
        fake_payload = blob(desync, desync.arg.blob)

        -- 8. tls_mod (только если есть reasm_data)
        if desync.reasm_data and desync.arg.tls_mod then
            fake_payload = tls_mod_shim(desync, fake_payload,
                                         desync.arg.tls_mod,
                                         desync.reasm_data)
        end

        -- 9. Отправка (с fooling, ipid, reconstruct, ipfrag, rawsend)
        rawsend_payload_segmented(desync, fake_payload)
        -- НЕ возвращает вердикт!
    else
        DLOG("fake: not acting on further replay pieces")
    end
    -- 10. Нет return VERDICT_DROP — оригинал уходит
end
```

**Ключевое отличие от [[multisplit]]**: multisplit возвращает `VERDICT_DROP` после успешной отправки (оригинал блокируется), а fake **ничего не возвращает** (оригинал проходит).

---

## Сравнение с syndata и fakedsplit

| Аспект | `fake` | `syndata` | `fakedsplit` |
|:-------|:-------|:----------|:-------------|
| Когда работает | На payload (после TCP handshake) | На SYN-пакете (до handshake) | На payload (после handshake) |
| Протоколы | TCP **и** UDP | Только TCP | Только TCP |
| Что делает | Шлёт отдельный фейковый пакет | Вкладывает payload в SYN | Режет payload + вставляет фейки между частями |
| Вердикт | **Нет** (оригинал проходит) | `VERDICT_DROP` (заменяет SYN) | `VERDICT_DROP` (заменяет оригинал) |
| blob обязателен | **Да** (error если нет) | Нет (дефолт: 16 нулевых байт) | Нет (фейки из `pattern`) |
| tls_mod условие | Нужен `reasm_data` | Всегда (payload=nil) | Нет tls_mod |
| fooling к чему | К фейковым пакетам | К SYN-пакету | Только к фейковым сегментам |
| Автосегментация | Да (TCP по MSS) | **Нет** (должен влезть в 1 пакет) | Да |
| Типичная позиция в цепочке | **Первый** (перед split) | **Самый первый** (на SYN) | Единственный (заменяет split) |

**Когда что использовать:**

- **fake** — когда нужен простой фейк перед реальным трафиком. Самый универсальный вариант, работает с TCP и UDP
- **syndata** — когда DPI анализирует уже SYN-пакет. Очень ранняя стадия, но ограничен размером одного пакета
- **fakedsplit** — когда нужно одновременно и нарезать, и подмешать фейки. Заменяет связку fake + [[multisplit]], но ограничен одной позицией разреза

---

## Нюансы и подводные камни

### 1. fake не делает DROP

Оригинальный пакет уйдёт следом (если другие инстансы не дропнут его). Это **ожидаемое поведение** — fake лишь добавляет фейковые пакеты перед оригиналом.

### 2. Без fooling фейк бесполезен или вреден

Если не задать fooling, сервер примет фейковый payload как настоящий. Для TCP это приведёт к рассинхронизации потока (данные с неверным seq будут интерпретированы неправильно). Для UDP сервер просто обработает фейковый пакет. **Всегда используйте fooling** (`tcp_md5`, `badsum`, `ip_ttl=1`, `tcp_flags_unset=ACK`, `tcp_seq=-10000` и т.д.).

### 3. fake работает только на первом replay-куске

При многопакетных payload (реассемблированных) fake срабатывает ровно один раз — на первом куске. На последующих частях он ничего не делает. Это правильно: фейк нужен один раз, перед началом реальных данных.

### 4. tls_mod молча пропускается без reasm_data

Если вы задали `tls_mod=rnd,rndsni`, но `reasm_data` отсутствует (например, payload влез в один пакет и реассемблирование не потребовалось для некоторых конфигураций) — tls_mod просто не применится. Фейк будет отправлен с немодифицированным blob. Для гарантированных модификаций используйте `--lua-init` для подготовки blob заранее.

### 5. blob обязателен — без optional будет Lua exception

Без `blob=...` функция вызывает `error()`. Это не тихий пропуск, а exception, который прервёт обработку всех инстансов для данного пакета. Если blob может отсутствовать — **всегда указывайте `optional`**.

### 6. Для UDP нет TCP-fooling

При использовании с UDP (QUIC) параметры `tcp_md5`, `tcp_seq`, `tcp_ack`, `tcp_flags_unset` и другие TCP-специфичные fooling не имеют смысла. Для UDP используйте IP-уровневые fooling: `ip_ttl`, `ip6_ttl`, `badsum`, `ipfrag`, IPv6 extension headers.

### 7. repeats может быть очень полезен

`repeats=N` отправляет каждый пакет/сегмент N раз. Для fake это означает N фейков подряд. Некоторые DPI сбрасывают состояние после N-го пакета, поэтому "заваливание" фейками (`repeats=11` или `repeats=20`) может быть эффективнее одного.

### 8. Порядок инстансов: fake всегда первый

В типичной конфигурации `fake` стоит **перед** [[multisplit]]/[[multidisorder]]. Порядок важен: сначала уходит фейк, затем (следующий инстанс) нарезает и отправляет реальный payload. Если поставить fake после split — фейк уйдёт после реальных данных, что может быть неэффективно.

### 9. fake не отсекается на не-TCP/не-UDP

В отличие от [[multisplit]] (который делает `instance_cutoff` на не-TCP), fake просто ничего не делает для пакетов, не являющихся TCP или UDP. Он **не отсекает** себя — будет продолжать проверять следующие пакеты в потоке.

### 10. padencap + реальный payload — тонкий трюк

`padencap` увеличивает длины в TLS-структуре фейка на размер реального payload. Идея: DPI увидит фейковый ClientHello с padding extension, длина которой "обещает" ещё N байт. Реальный ClientHello (следующий пакет) может быть воспринят DPI как продолжение padding, а не как отдельный ClientHello. Это работает только с DPI, которые реассемблируют TCP и парсят TLS record по полям длины.

---

## Миграция с nfqws1

### Соответствие параметров

| nfqws1 | nfqws2 |
|:-------|:-------|
| `--dpi-desync=fake` | `--lua-desync=fake:blob=<blob>` |
| `--dpi-desync-fake-http=<hex>` | `--payload=http_req --lua-desync=fake:blob=<hex>` |
| `--dpi-desync-fake-tls=<hex\|!>` | `--payload=tls_client_hello --lua-desync=fake:blob=<hex\|fake_default_tls>` |
| `--dpi-desync-fake-quic=<hex>` | `--payload=quic_initial --lua-desync=fake:blob=<hex>` |
| `--dpi-desync-fake-tls-mod=<list>` | `:tls_mod=<list>` |
| `--dpi-desync-fooling=md5sig` | `:tcp_md5` |
| `--dpi-desync-fooling=badseq` | `:tcp_seq=-10000` |
| `--dpi-desync-fooling=badack` | `:tcp_ack=-66000` |
| `--dpi-desync-fooling=datanoack` | `:tcp_flags_unset=ack` |
| `--dpi-desync-fooling=hopbyhop` | `:ip6_hopbyhop` |
| `--dpi-desync-fooling=hopbyhop2` | `:ip6_hopbyhop2` |
| `--dpi-desync-fooling=destopt` | `:ip6_destopt` |
| `--dpi-desync-fooling=ipfrag1` | `:ipfrag` |
| `--dpi-desync-ttl=N` | `:ip_ttl=N:ip6_ttl=N` |
| `--dpi-desync-autottl=...` | `:ip_autottl=...:ip6_autottl=...` |
| `--dpi-desync-repeats=N` | `:repeats=N` |
| `--dpi-desync-badseq-increment=N` | `:tcp_seq=N` |
| `--dpi-desync-badack-increment=N` | `:tcp_ack=N` |
| `--dpi-desync-any-protocol` | Не нужно; или `payload=all` в инстансе |

### Ключевое отличие: в nfqws1 fake был "глобальный"

В nfqws1 `--dpi-desync=fake` автоматически выбирал blob по типу payload: для TLS — `--dpi-desync-fake-tls`, для HTTP — `--dpi-desync-fake-http`, для QUIC — `--dpi-desync-fake-quic`. В nfqws2 blob задаётся вручную, и для разных payload нужны **отдельные инстансы**.

### Пример полной миграции: fake с TTL

```bash
# nfqws1:
nfqws --dpi-desync=fake \
  --dpi-desync-fake-http=0x00000000 \
  --dpi-desync-ttl=6

# nfqws2 (эквивалент):
nfqws2 \
  --payload=http_req \
    --lua-desync=fake:blob=0x00000000:ip_ttl=6:ip6_ttl=6
```

### Пример полной миграции: fake с tls_mod + datanoack

```bash
# nfqws1:
nfqws --dpi-desync=fake \
  --dpi-desync-fooling=datanoack \
  --dpi-desync-fake-tls=! \
  --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid

# nfqws2 (эквивалент):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fake:blob=fake_default_tls:tcp_flags_unset=ack:tls_mod=rnd,rndsni,dupsid,padencap
```

### Пример полной миграции: fake + multisplit

```bash
# nfqws1:
nfqws --dpi-desync=fake,multisplit \
  --dpi-desync-fooling=md5sig \
  --dpi-desync-split-pos=1,midsld \
  --dpi-desync-split-seqovl=5 \
  --dpi-desync-split-seqovl-pattern=0x1603030000 \
  --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid

# nfqws2 (эквивалент — отдельные инстансы):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --payload=http_req \
    --lua-desync=fake:blob=fake_default_http:tcp_md5 \
  --payload=tls_client_hello,http_req \
    --lua-desync=multisplit:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

---

## Практические примеры

### 1. Минимальный TLS-фейк (обязателен blob + fooling)

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5
```

Отправляет стандартный фейковый ClientHello с `www.w3.org`, сервер отбросит из-за TCP MD5 option.

### 2. Минимальный HTTP-фейк

```bash
--payload=http_req --lua-desync=fake:blob=fake_default_http:tcp_md5
```

### 3. QUIC (UDP) фейк с TTL

```bash
--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ip_ttl=1:ip6_ttl=1
```

Для UDP TCP-fooling невозможен, используем TTL=1 — фейк не дойдёт до сервера.

### 4. optional: тихо пропустить, если blob не загружен

```bash
--lua-desync=fake:blob=cloned_ch:optional:tcp_md5
```

Если blob `cloned_ch` не был создан предыдущим инстансом — пропуск без ошибки.

### 5. Множественные повторы фейка

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11
```

11 одинаковых фейков подряд. Эффективно против DPI, который "считает" пакеты.

### 6. rnd: рандомизировать Random и Session ID

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd
```

Каждый фейк будет с уникальным Random и Session ID.

### 7. rndsni: случайный SNI в фейке

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rndsni
```

SNI в фейке будет случайным доменом (DPI не увидит ни реальный, ни `www.w3.org`).

### 8. sni=domain: конкретный SNI в фейке

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=sni=www.google.com
```

DPI увидит `www.google.com` в фейке. Полезно, если DPI блокирует по whitelist.

### 9. sni=%var: подстановка SNI из переменной

```bash
--lua-init="target='www.google.com'" \
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=sni=%target
```

### 10. dupsid: копирование Session ID из реального ClientHello

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,dupsid
```

Session ID фейка совпадёт с реальным — DPI может привязать фейк к текущей сессии.

### 11. Полный набор tls_mod (типовой пресет)

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap
```

Максимальная маскировка фейка: случайные Random/SID, случайный SNI, скопированный реальный SID, padencap.

### 12. TTL-fooling (жёсткий фейк)

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:ip_ttl=1:ip6_ttl=1
```

Фейк умрёт на первом хопе. Работает, если DPI стоит ближе к клиенту, чем сервер.

### 13. datanoack + badsum (комбинированный fooling)

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:badsum:tcp_flags_unset=ack:tls_mod=rnd,dupsid,padencap
```

Два уровня защиты: испорченная контрольная сумма + снятый ACK.

### 14. IP-фрагментация фейка (TCP)

```bash
--payload=tls_client_hello --lua-desync=fake:blob=fake_default_tls:tcp_md5:ipfrag:ipfrag_pos_tcp=32
```

Фейк фрагментируется на IP-уровне. DPI может не уметь реассемблировать IP-фрагменты.

### 15. IP-фрагментация фейка (UDP/QUIC) в обратном порядке

```bash
--payload=quic_initial --lua-desync=fake:blob=fake_default_quic:ipfrag:ipfrag_pos_udp=8:ipfrag_disorder
```

### 16. Произвольный hex blob (нулевые байты)

```bash
--payload=http_req --lua-desync=fake:blob=0x00000000:ip_ttl=6:ip6_ttl=6
```

4 нулевых байта как фейк. DPI увидит "мусор" перед реальным HTTP.

### 17. Боевая связка: fake + multisplit для YouTube

```bash
--filter-tcp=443 --hostlist=youtube.txt \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11 \
  --lua-desync=multisplit:pos=1,midsld
```

11 фейков подряд (с MD5 fooling) + реальный payload разрезан на 3 части.

### 18. Боевая связка: fake + multisplit + seqovl

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --lua-desync=multisplit:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

Фейк с полным tls_mod, затем реальный payload нарезан с seqovl.

### 19. fake с клонированным ClientHello (двухинстансная схема)

```bash
--payload=tls_client_hello \
  --lua-desync=tls_client_hello_clone:blob=cloned_ch:sni_del:sni_add=www.google.com \
  --lua-desync=fake:blob=cloned_ch:optional:tcp_md5
```

Первый инстанс клонирует реальный ClientHello и подменяет SNI. Второй — отправляет клон как фейк.

### 20. fake для нескольких протоколов (отдельные профили)

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid,padencap \
  --lua-desync=multisplit:pos=1,midsld \
--payload=http_req \
  --lua-desync=fake:blob=fake_default_http:tcp_md5 \
  --lua-desync=multisplit:pos=host,midsld \
--payload=quic_initial \
  --lua-desync=fake:blob=fake_default_quic:ip_ttl=1:ip6_ttl=1
```

Для каждого протокола — свой blob и свой fooling.

---

> **Источники:** `lua/zapret-antidpi.lua:438-461`, `lua/zapret-lib.lua:625-636` (`tls_mod_shim`), `lua/zapret-lib.lua:1194-1203` (`rawsend_payload_segmented`), `docs/manual.md:3991-4009`, `docs/manual.md:2425-2442` из репозитория zapret2.

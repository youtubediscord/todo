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
  - fakedsplit
  - fake
  - seqovl
aliases:
  - fakedsplit
---

# `fakedsplit` — TCP-сегментация с замешиванием фейков (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:813`
**nfqws1 эквивалент:** `--dpi-desync=fakedsplit`
**Сигнатура:** `function fakedsplit(ctx, desync)`

`fakedsplit` разрезает TCP payload на **две** части по одной позиции и отправляет их вперемешку с **фейковыми** сегментами того же размера. Фейки содержат мусор (pattern), но имеют те же TCP sequence и размеры, что и оригиналы. Для DPI это выглядит как серия ретрансмиссий — он не может понять, какой сегмент настоящий, а какой — подделка. Для сервера фейки отбрасываются благодаря fooling (badseq, md5sig, badsum и т.д.).

Родственные функции: [[multisplit]] (простая сегментация), [[multidisorder]] (обратный порядок), [[fakeddisorder]] (фейки + обратный порядок), [[hostfakesplit]] (по hostname), [[tcpseg]] (диапазон), [[oob]] (urgent byte).

---

## Оглавление

- [Зачем нужен fakedsplit](#зачем-нужен-fakedsplit)
- [Быстрый старт](#быстрый-старт)
- [Откуда берутся данные для нарезки](#откуда-берутся-данные-для-нарезки)
- [Маркер позиции (pos)](#маркер-позиции-pos)
  - [Типы маркеров](#типы-маркеров)
  - [Относительные маркеры](#относительные-маркеры)
  - [Арифметика маркеров](#арифметика-маркеров)
  - [Как маркер разрешается в коде](#как-маркер-разрешается-в-коде)
  - [Важные нюансы pos](#важные-нюансы-pos)
- [Последовательность отправки (6 пакетов)](#последовательность-отправки-6-пакетов)
  - [ASCII-диаграмма](#ascii-диаграмма)
  - [Что видит DPI](#что-видит-dpi)
  - [Что видит сервер](#что-видит-сервер)
- [Два набора опций: opts_orig vs opts_fake](#два-набора-опций-opts_orig-vs-opts_fake)
- [seqovl — скрытый фейк внутри сегмента](#seqovl--скрытый-фейк-внутри-сегмента)
  - [Принцип работы seqovl](#принцип-работы-seqovl)
  - [seqovl_pattern](#seqovl_pattern)
- [pattern — заполнение фейков](#pattern--заполнение-фейков)
- [nofake1..nofake4 — отключение отдельных фейков](#nofake1nofake4--отключение-отдельных-фейков)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы fakedsplit](#a-собственные-аргументы-fakedsplit)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard reconstruct](#f-standard-reconstruct)
  - [G) Standard rawsend](#g-standard-rawsend)
- [Порядок отправки — подробно с seqovl](#порядок-отправки--подробно-с-seqovl)
- [Поведение при replay / reasm](#поведение-при-replay--reasm)
- [Автосегментация по MSS](#автосегментация-по-mss)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Отличия от других функций сегментации](#отличия-от-других-функций-сегментации)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен fakedsplit

Обычная сегментация ([[multisplit]]) разрезает payload, но DPI может просто реассемблировать поток. Отдельная отправка фейка ([[fake]]) работает, но DPI может отбросить фейк по эвристикам (слишком другой TTL, плохой sequence).

`fakedsplit` комбинирует оба подхода: он **одновременно** разрезает и замешивает фейки. При этом фейки:

1. **Совпадают по размеру** с реальными частями
2. **Имеют те же TCP sequence numbers** — выглядят как ретрансмиссии
3. **Окружают** каждую реальную часть с двух сторон (до и после)

Для DPI поток выглядит так: 6 TCP-сегментов, из которых по 3 пары — "ретрансмиссии" одного и того же. Какой из трёх сегментов каждой пары настоящий? DPI не знает. Сервер знает — потому что фейки имеют невалидные заголовки (fooling), и TCP-стек их молча отбросит.

---

## Быстрый старт

Минимально (разрез по позиции 2, payload=known, dir=out):

```bash
--lua-desync=fakedsplit:tcp_ack=-66000
```

Типовой TLS-разрез с badseq:

```bash
--payload=tls_client_hello --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

HTTP с разрезом по методу:

```bash
--payload=http_req --lua-desync=fakedsplit:pos=method+2:tcp_ack=-66000:tcp_ts_up
```

С seqovl для дополнительной маскировки:

```bash
--payload=tls_client_hello --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up:seqovl=5:seqovl_pattern=0x1603030000
```

---

## Откуда берутся данные для нарезки

Внутри `fakedsplit` данные (`data`) выбираются в следующем порядке приоритетов:

```
1. blob_or_def(desync, desync.arg.blob)    — если задан blob= и он существует
2. desync.reasm_data                        — если есть реассемблированные данные (multi-packet payload)
3. desync.dis.payload                       — текущий пакет (fallback)
```

**Следствие:** все маркеры `pos`, `seqovl` и прочие аргументы применяются именно к тем данным, которые реально выбраны. Если вы задали `blob=myblob`, маркеры вроде `midsld` будут работать только если `myblob` содержит валидный TLS/HTTP payload, который zapret может распознать.

---

## Маркер позиции (pos)

`pos` — главный аргумент `fakedsplit`. Определяет **где** внутри payload будет произведён разрез. В отличие от [[multisplit]], `pos` — это **один маркер**, а не список. Payload всегда делится ровно на **две части**.

### Типы маркеров

| Тип | Описание | Пример |
|:----|:---------|:-------|
| **Абсолютный положительный** | Смещение от начала payload. В Lua позиции начинаются с 1 | `2`, `5`, `100` |
| **Абсолютный отрицательный** | Смещение от конца payload. `-1` = последний байт | `-1`, `-10`, `-50` |
| **Относительный** | Логическая позиция внутри распознанного payload. Привязана к структуре протокола | `midsld`, `host`, `sniext` |

### Относительные маркеры

| Маркер | Описание | Для каких payload |
|:-------|:---------|:------------------|
| `method` | Начало HTTP-метода (`GET`, `POST`, `HEAD`, `PUT` и т.д.). Обычно позиция 0, но может стать 1-2 при использовании `http_methodeol` | `http_req` |
| `host` | Первый байт имени хоста (`Host:` в HTTP, SNI в TLS) | `http_req`, `tls_client_hello` |
| `endhost` | Байт, **следующий** за последним байтом имени хоста. Т.е. `host..endhost-1` = полный hostname | `http_req`, `tls_client_hello` |
| `sld` | Первый байт домена второго уровня (SLD). Для `www.example.com` — это `e` в `example` | `http_req`, `tls_client_hello` |
| `endsld` | Байт, следующий за последним байтом SLD. Для `example.com` — это `.` после `example` | `http_req`, `tls_client_hello` |
| `midsld` | Середина SLD (самый популярный маркер). Для `example` (7 символов) — позиция 3-го или 4-го символа | `http_req`, `tls_client_hello` |
| `sniext` | Начало поля данных SNI extension в TLS ClientHello. Extension состоит из type (2 байта) + length (2 байта) + **данные** — sniext указывает на начало данных | `tls_client_hello` |
| `extlen` | Поле длины всех TLS extensions | `tls_client_hello` |

### Арифметика маркеров

К любому маркеру можно прибавить (+) или вычесть (-) целое число:

```
midsld+1      — один байт ПОСЛЕ середины SLD
midsld-1      — один байт ДО середины SLD
endhost-2     — два байта до конца hostname
method+2      — два байта после начала метода (разрежет "GET " после "GE")
sniext+1      — один байт после начала SNI extension data
host+3        — три байта после начала hostname
-1            — последний байт payload (абсолютный, не относительный)
```

### Как маркер разрешается в коде

В отличие от [[multisplit]], который вызывает `resolve_multi_pos` (парсит список через запятую), `fakedsplit` вызывает **`resolve_pos`** напрямую — для одного маркера:

```lua
local pos = resolve_pos(data, desync.l7payload, spos)
```

Функция `resolve_pos`:

1. Разбирает маркер (имя + арифметика)
2. Если маркер не может быть разрешён (например, `midsld` для `unknown` payload) — возвращает `nil`
3. При успехе возвращает абсолютную позицию (1-based, как в Lua)

Далее проверяется:

```lua
if pos == 1 then
    DLOG("fakedsplit: split pos resolved to 0. cannot split.")
    -- ничего не делает
end
```

### Важные нюансы pos

- **Только ОДИН маркер.** `pos=midsld,endhost` НЕ работает. Запятая не парсится — это не список. Если нужно несколько точек разреза с фейками — используйте цепочку нескольких `fakedsplit`
- **Нельзя разрезать по позиции 1** (первый байт). Позиция 1 приводит к сообщению "cannot split" и функция ничего не делает. Для разреза "после 1-го байта" используйте `pos=2` (это дефолт)
- **Неразрешимый маркер => ничего не делается.** Если `resolve_pos` вернул `nil` (маркер не разрешился), fakedsplit логирует "cannot resolve pos" и пропускает
- **По умолчанию pos="2".** Если `pos` не задан, разрез по позиции 2 => payload делится на 2 части: 1-й байт отдельно, остальное отдельно

---

## Последовательность отправки (6 пакетов)

`fakedsplit` отправляет **до 6 пакетов** (при включённых всех фейках):

| # | Что | Тип | Отключение | Опции |
|:--|:----|:----|:-----------|:------|
| 1 | Фейк 1-й части | fake | `nofake1` | `opts_fake` (полный fooling + reconstruct + repeats) |
| 2 | Реальная 1-я часть (+seqovl) | orig | -- | `opts_orig` (только tcp_ts_up, без repeats) |
| 3 | Фейк 1-й части (повтор) | fake | `nofake2` | `opts_fake` |
| 4 | Фейк 2-й части | fake | `nofake3` | `opts_fake` |
| 5 | Реальная 2-я часть | orig | -- | `opts_orig` |
| 6 | Фейк 2-й части (повтор) | fake | `nofake4` | `opts_fake` |

**Ключевой момент:** каждая реальная часть **окружена** фейками того же размера и с тем же TCP sequence. DPI видит "тройки ретрансмиссий" и не может определить, какая из трёх — настоящая.

### ASCII-диаграмма

```
Payload: [=======ЧАСТЬ 1=======|=======ЧАСТЬ 2=======]
                               ^pos

Время отправки (сверху вниз):

  #1  FAKE1  [XXXXXXXXXXXXXXXXXXXXX]  seq=0       len=pos-1      opts_fake
  #2  REAL1  [=====================]  seq=-seqovl len=pos-1+sovl  opts_orig
  #3  FAKE1  [XXXXXXXXXXXXXXXXXXXXX]  seq=0       len=pos-1      opts_fake
  #4  FAKE2  [XXXXXXXXXXXXXXXXXXXXX]  seq=pos-1   len=#data-pos+1 opts_fake
  #5  REAL2  [=====================]  seq=pos-1   len=#data-pos+1 opts_orig
  #6  FAKE2  [XXXXXXXXXXXXXXXXXXXXX]  seq=pos-1   len=#data-pos+1 opts_fake

  X = мусор (pattern)
  = = реальные данные
```

### Что видит DPI

```
Поток TCP-сегментов на проводе:

  seq=0      [XXXXXXX]  ← fake 1  (мусор)
  seq=-sovl  [PPP|REAL1] ← real 1  (seqovl pattern + данные)
  seq=0      [XXXXXXX]  ← fake 1  (мусор, "ретрансмиссия")
  seq=pos    [XXXXXXX]  ← fake 2  (мусор)
  seq=pos    [==REAL2=]  ← real 2  (данные)
  seq=pos    [XXXXXXX]  ← fake 2  (мусор, "ретрансмиссия")

DPI видит: "3 сегмента с seq=0, 3 сегмента с seq=pos — похоже на ретрансмиссии.
           Какой из каждой тройки настоящий? Непонятно."
```

### Что видит сервер

```
Сервер (TCP-стек):

  seq=0,     данные=мусор   → fooling (badseq/md5/badsum) → ОТБРОШЕН
  seq=-sovl, данные=PPP+R1  → seqovl-часть за window → отброшена; R1 → ПРИНЯТ
  seq=0,     данные=мусор   → fooling → ОТБРОШЕН
  seq=pos,   данные=мусор   → fooling → ОТБРОШЕН
  seq=pos,   данные=REAL2   → нормальный пакет → ПРИНЯТ
  seq=pos,   данные=мусор   → fooling → ОТБРОШЕН

Результат: сервер собрал [REAL1][REAL2] = полный оригинальный payload
```

---

## Два набора опций: opts_orig vs opts_fake

Это ключевое отличие `fakedsplit` от [[multisplit]]. Внутри функции создаются **два набора** опций:

```lua
-- Для оригинальных частей:
local opts_orig = {
    rawsend    = rawsend_opts_base(desync),  -- БЕЗ repeats!
    reconstruct = {},                         -- пустой (без badsum)
    ipfrag     = {},                          -- пустой (без IP-фрагментации)
    ipid       = desync.arg,                  -- ip_id применяется
    fooling    = {tcp_ts_up = desync.arg.tcp_ts_up}  -- ТОЛЬКО tcp_ts_up
}

-- Для фейковых частей:
local opts_fake = {
    rawsend    = rawsend_opts(desync),        -- С repeats!
    reconstruct = reconstruct_opts(desync),    -- badsum если задан
    ipfrag     = {},                          -- пустой (без IP-фрагментации)
    ipid       = desync.arg,                  -- ip_id применяется
    fooling    = desync.arg                    -- ВСЁ fooling целиком
}
```

**Сводная таблица:**

| Что | opts_orig (оригиналы) | opts_fake (фейки) |
|:----|:----------------------|:-------------------|
| **fooling** | Только `tcp_ts_up` | Всё (tcp_ack, tcp_seq, tcp_md5, ip_ttl, badseq, ...) |
| **reconstruct** | Нет (пустой `{}`) | Да (`badsum` если задан) |
| **rawsend.repeats** | Нет (`rawsend_opts_base`) | Да (`rawsend_opts`) |
| **rawsend.ifout** | Да | Да |
| **rawsend.fwmark** | Да | Да |
| **ipid** | Да | Да |
| **ipfrag** | Нет (пустой `{}`) | Нет (пустой `{}`) |

**Почему так:**
- Оригиналы **должны** быть приняты сервером => никакого fooling (кроме безвредного tcp_ts_up), никакого badsum
- Фейки **должны** быть отброшены сервером => полный fooling + badsum
- `repeats` — множественная отправка имеет смысл только для фейков (больше шума для DPI)
- `ipfrag` **не используется** ни для чего — fakedsplit работает исключительно на уровне TCP-сегментов
- `ipid` и базовый `rawsend` (ifout, fwmark) нужны обоим — это уровень IP/маршрутизации

---

## seqovl — скрытый фейк внутри сегмента

**seqovl** (Sequence Overlap) — техника скрытого замешивания фейковых данных в реальный TCP-сегмент через манипуляцию TCP sequence number. В `fakedsplit` seqovl применяется **только к первому реальному сегменту** (пакет #2).

### Принцип работы seqovl

```
Без seqovl:
  TCP seq: 0
  Данные:  [РЕАЛЬНАЯ_ЧАСТЬ_1]
  Сервер:  принимает [РЕАЛЬНАЯ_ЧАСТЬ_1] целиком

С seqovl=10:
  TCP seq: -10            (уменьшен на 10)
  Данные:  [PATTERN_10_БАЙТ][РЕАЛЬНАЯ_ЧАСТЬ_1]

  Что видит DPI:
    Единый TCP-сегмент начиная с seq -10.
    DPI анализирует весь блок, включая PATTERN.
    Если PATTERN содержит ложный SNI — DPI может принять его за настоящий.

  Что видит сервер (TCP-стек):
    TCP window начинается с seq 0.
    Байты -10..-1 выходят за левую границу window => отбрасываются.
    Байты с 0 (РЕАЛЬНАЯ_ЧАСТЬ_1) => принимаются.
```

**Визуализация:**

```
           TCP window boundary
                 |
  |  ОТБРОСИТЬ  | ПРИНЯТЬ          |
  | PATTERN(10) | РЕАЛЬНАЯ_ЧАСТЬ_1 |
  ^seq=-10       ^seq=0
```

**seqovl в fakedsplit — дополнительный уровень защиты** поверх фейков. Даже если DPI научился отбрасывать фейковые сегменты, seqovl-данные внутри реального сегмента он может не распознать.

**Важно:** в `fakedsplit` `seqovl` — только **число** (не маркер). Маркеры поддерживаются в [[fakeddisorder]] и [[multidisorder]], но не здесь.

### seqovl_pattern

Паттерн, которым заполняется seqovl-область (N байт слева от реальных данных). По умолчанию — `0x00` (нули).

В `fakedsplit` `seqovl_pattern` — это **имя blob**. Паттерн повторяется до нужной длины `seqovl`.

```bash
# Inline hex blob (маскировка под начало TLS record)
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:seqovl=5:seqovl_pattern=0x1603030000

# Предзагруженный blob
--blob=tlspat:0x1603030100 \
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:seqovl=8:seqovl_pattern=tlspat
```

Если `optional` задан и blob `seqovl_pattern` отсутствует — используется нулевой паттерн (seqovl не отменяется).

---

## pattern — заполнение фейков

Аргумент `pattern` задаёт содержимое фейковых сегментов. Это имя blob, из которого генерируется паттерн для заполнения фейков.

```lua
fakepat = desync.arg.pattern and blob(desync, desync.arg.pattern) or "\x00"
```

- По умолчанию: `\x00` (нулевые байты)
- Фейк первой части: `pattern(fakepat, 1, pos-1)` — паттерн со смещением 1, длиной pos-1
- Фейк второй части: `pattern(fakepat, pos, #data-pos+1)` — паттерн со смещением pos, длиной остатка

Смещение паттерна (`pos`) соответствует смещению TCP sequence отсылаемой части. Это значит, что если DPI сравнивает байты фейка и оригинала побайтово — он увидит разные данные в одних и тех же позициях. Но если он просто реассемблирует поток — паттерн не сможет "обмануть" конкретную сигнатуру (для этого нужен осмысленный blob).

```bash
# Фейки заполнены случайными данными из blob
--blob=rndpat:0xDEADBEEFCAFEBABE \
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:pattern=rndpat

# Фейки заполнены нулями (по умолчанию)
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000
```

---

## nofake1..nofake4 — отключение отдельных фейков

Каждый из 4 фейковых пакетов можно отключить индивидуально:

| Флаг | Отключает | Позиция в потоке |
|:-----|:----------|:-----------------|
| `nofake1` | Фейк 1-й части (до реальной 1-й) | #1 |
| `nofake2` | Фейк 1-й части (после реальной 1-й) | #3 |
| `nofake3` | Фейк 2-й части (до реальной 2-й) | #4 |
| `nofake4` | Фейк 2-й части (после реальной 2-й) | #6 |

Минимально необходимые пакеты — только два реальных (#2, #5). Все 4 фейка можно отключить:

```bash
# Без фейков вообще (по сути = multisplit с одной позицией)
--lua-desync=fakedsplit:pos=midsld:nofake1:nofake2:nofake3:nofake4
```

Типичные комбинации:

```bash
# Только "передние" фейки (до реальных частей)
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:nofake2:nofake4

# Только "задние" фейки (после реальных частей)
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:nofake1:nofake3

# Фейки только для 1-й части
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:nofake3:nofake4
```

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=fakedsplit[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`, `:nodrop`, `:tcp_ts_up`.

### A) Собственные аргументы fakedsplit

#### `pos`

- **Формат:** `pos=<marker>`
- **Тип:** строка — **один** маркер (НЕ список!)
- **По умолчанию:** `"2"`
- **Описание:** Точка разреза. Payload делится на 2 части: `data[1..pos-1]` и `data[pos..#data]`
- **Примеры:**
  - `pos=2` — разрез после 1-го байта (дефолт)
  - `pos=midsld` — разрез посередине SLD
  - `pos=method+2` — после первых 2 символов HTTP-метода
  - `pos=host` — перед началом hostname
  - `pos=sniext+1` — после начала SNI extension data

#### `pattern`

- **Формат:** `pattern=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** `\x00` (нулевой байт)
- **Описание:** Данные для заполнения фейковых сегментов. Blob повторяется функцией `pattern()` до нужного размера
- **Примеры:**
  - `pattern=0xDEADBEEF` — inline hex
  - `pattern=my_fake_pattern` — предзагруженный blob

#### `seqovl`

- **Формат:** `seqovl=N` (где N > 0)
- **Тип:** только число (маркеры **не поддерживаются** — в отличие от [[fakeddisorder]])
- **По умолчанию:** не задан (нет seqovl)
- **Описание:** Применяется **только к первому реальному сегменту** (пакет #2). К данным первого сегмента слева добавляется N байт `seqovl_pattern`, а TCP `th_seq` уменьшается на N. Сервер отбросит левую часть, DPI — может не отбросить
- **Примеры:**
  - `seqovl=5` — 5 байт фейка слева
  - `seqovl=13` — 13 байт фейка слева

#### `seqovl_pattern`

- **Формат:** `seqovl_pattern=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** один байт `0x00`, повторяемый до длины `seqovl`
- **Описание:** Данные для заполнения seqovl-области. Blob повторяется функцией `pattern()` до нужного размера
- **Поведение с `optional`:** если `optional` задан и blob отсутствует — используется нулевой паттерн, seqovl не отменяется
- **Примеры:**
  - `seqovl_pattern=0x1603030000` — inline hex (маскировка под TLS)
  - `seqovl_pattern=my_pattern_blob` — предзагруженный blob

#### `blob`

- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** не задан
- **Описание:** Заменить текущий payload/reasm на указанный blob и резать/слать его. Используется для отправки произвольных данных (фейковых payload, модифицированных ClientHello и т.д.)
- **Примеры:**
  - `blob=fake_default_tls` — стандартный TLS-фейк
  - `blob=0xDEADBEEF` — inline hex
  - `blob=my_custom_ch` — предзагруженный blob

#### `optional`

- **Формат:** `optional` (флаг, без значения)
- **Описание:** Мягкий режим:
  - Если задан `blob=...` и blob отсутствует => fakedsplit **ничего не делает** (тихий skip, без ошибок)
  - Если задан `seqovl_pattern=...` и blob отсутствует => используется нулевой паттерн (seqovl не отменяется)
- **Использование:** защита от ошибок при использовании blob, которые могут отсутствовать

#### `nodrop`

- **Формат:** `nodrop` (флаг, без значения)
- **Описание:** После успешной отправки сегментов **не выносить** `VERDICT_DROP` (вместо этого вернуть `VERDICT_PASS`). Это означает, что оригинальный пакет тоже будет отправлен (наряду с нарезанными сегментами и фейками)
- **Использование:** для отладки
- **Предупреждение:** в боевых профилях `nodrop` обычно нежелателен

#### `nofake1`

- **Формат:** `nofake1` (флаг, без значения)
- **Описание:** Не отправлять фейк 1-й части **до** реальной 1-й части (пакет #1)

#### `nofake2`

- **Формат:** `nofake2` (флаг, без значения)
- **Описание:** Не отправлять фейк 1-й части **после** реальной 1-й части (пакет #3)

#### `nofake3`

- **Формат:** `nofake3` (флаг, без значения)
- **Описание:** Не отправлять фейк 2-й части **до** реальной 2-й части (пакет #4)

#### `nofake4`

- **Формат:** `nofake4` (флаг, без значения)
- **Описание:** Не отправлять фейк 2-й части **после** реальной 2-й части (пакет #6)

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `fakedsplit` по умолчанию работает только с исходящими (`out`).

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

Модификации L3/L4 заголовков. В `fakedsplit` применяются **только к фейкам** (opts_fake). К оригиналам из всего fooling идёт **только tcp_ts_up**.

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

**Важно для fakedsplit:** `tcp_ts_up` — единственный параметр fooling, который применяется и к оригиналам. Все остальные — только к фейкам. Это значит, что `tcp_ack=-66000` безопасен — оригиналы будут иметь валидный ACK, а фейки — невалидный.

**Заметка про tcp_ts_up:** На Linux-серверах пакеты с инвалидным ACK стабильно отбрасываются **только если** TCP timestamp option идёт первой в заголовке. `tcp_ts_up` перемещает её в начало, обеспечивая корректную работу badseq-fooling. Поскольку `tcp_ts_up` безвреден (не портит данные, просто переупорядочивает опции), он применяется и к оригиналам.

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | -- |
| `ip_id=zero` | Нулевые IP ID | -- |
| `ip_id=none` | Не менять IP ID | -- |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения (требует tracking) | -- |

`ip_id` применяется **и к фейкам, и к оригиналам** (оба набора опций содержат `ipid = desync.arg`).

---

### F) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета. Сервер отбросит такой пакет |

В `fakedsplit` `badsum` применяется **только к фейкам** (`opts_fake`). Оригиналы имеют пустой `reconstruct = {}`.

---

### G) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить каждый сегмент N раз (идентичные повторы) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

**Важная деталь:** `repeats` применяется **только к фейкам**. Оригиналы используют `rawsend_opts_base`, который не включает `repeats`. `ifout` и `fwmark` применяются к обоим.

---

## Порядок отправки — подробно с seqovl

### Без seqovl

```
Payload "ABCDEFGHIJ" (10 байт), pos=4, pattern=0xFF

Пакет #1 (fake1):   seq=0  data=[FF FF FF]     len=3   opts_fake
Пакет #2 (real1):   seq=0  data=[A  B  C ]     len=3   opts_orig
Пакет #3 (fake1'):  seq=0  data=[FF FF FF]     len=3   opts_fake
Пакет #4 (fake2):   seq=3  data=[FF FF FF FF FF FF FF]  len=7  opts_fake
Пакет #5 (real2):   seq=3  data=[D  E  F  G  H  I  J]  len=7  opts_orig
Пакет #6 (fake2'):  seq=3  data=[FF FF FF FF FF FF FF]  len=7  opts_fake
```

### С seqovl=5

```
Payload "ABCDEFGHIJ" (10 байт), pos=4, pattern=0xFF, seqovl=5, seqovl_pattern=0x00

Пакет #1 (fake1):   seq=0   data=[FF FF FF]                  len=3   opts_fake
Пакет #2 (real1):   seq=-5  data=[00 00 00 00 00 A  B  C ]   len=8   opts_orig
Пакет #3 (fake1'):  seq=0   data=[FF FF FF]                  len=3   opts_fake
Пакет #4 (fake2):   seq=3   data=[FF FF FF FF FF FF FF]      len=7   opts_fake
Пакет #5 (real2):   seq=3   data=[D  E  F  G  H  I  J]      len=7   opts_orig
Пакет #6 (fake2'):  seq=3   data=[FF FF FF FF FF FF FF]      len=7   opts_fake

Сервер:
  Пакет #2: seq=-5, байты -5..-1 за window => отброшены; байты 0..2 = [A B C] => приняты
  Пакет #5: seq=3, байты 3..9 = [D E F G H I J] => приняты
  Итого: [A B C D E F G H I J] = полный payload
```

---

## Поведение при replay / reasm

При многопакетных payload (например, большой TLS ClientHello с post-quantum Kyber, который не влезает в один TCP-сегмент) zapret собирает все части в `reasm_data`. При перепроигрывании (replay):

1. **Первая часть replay:** fakedsplit берёт **весь** `reasm_data`, нарезает и отправляет с фейками. Устанавливает флаг `replay_drop_set`
2. **Все последующие части replay:** fakedsplit видит, что отправка уже произошла, логирует "not acting on further replay pieces" и выносит `VERDICT_DROP` (если не `nodrop`)

**Исключение:** если первая отправка неуспешна (rawsend вернул false), флаг не устанавливается и последующие части проходят как есть.

---

## Автосегментация по MSS

О размерах TCP-сегментов думать **не нужно**. Функция `rawsend_payload_segmented` из `zapret-lib.lua` автоматически:

1. Отслеживает MSS для каждого TCP-соединения
2. Если часть payload превышает MSS — дополнительно режет по MSS
3. Каждый под-сегмент отправляется с корректным TCP sequence

Это относится и к фейкам, и к оригиналам.

---

## Псевдокод алгоритма

```lua
function fakedsplit(ctx, desync)
    -- 1. Проверка: только TCP
    if not desync.dis.tcp then
        if not desync.dis.icmp then instance_cutoff_shim() end
        return
    end

    -- 2. Cutoff противоположного направления
    direction_cutoff_opposite(ctx, desync)

    -- 3. Проверка optional blob
    if optional and blob specified and blob not exists then
        DLOG("blob not found. skipped")
        return
    end

    -- 4. Выбор данных
    data = blob_or_def(blob) or reasm_data or dis.payload

    -- 5. Проверки: данные не пусты, направление OK, payload OK
    if #data > 0 and direction_check() and payload_check() then

        -- 6. Только первый replay
        if replay_first() then

            -- 7. Разрешение ОДНОГО маркера
            pos = resolve_pos(data, l7payload, pos_arg or "2")

            if pos == nil then
                DLOG("cannot resolve pos")
            elseif pos == 1 then
                DLOG("split pos resolved to 0. cannot split.")
            else
                -- 8. Создание двух наборов опций
                opts_orig = {rawsend=base, reconstruct={}, ipfrag={},
                             ipid=arg, fooling={tcp_ts_up=arg.tcp_ts_up}}
                opts_fake = {rawsend=full, reconstruct=reconstruct_opts,
                             ipfrag={}, ipid=arg, fooling=arg}

                -- 9. Паттерн для фейков
                fakepat = arg.pattern blob or "\x00"

                -- 10. ФЕЙК 1-й части
                fake = pattern(fakepat, 1, pos-1)
                if not nofake1 then
                    rawsend_payload_segmented(fake, 0, opts_fake)
                end

                -- 11. РЕАЛЬНАЯ 1-я часть (+seqovl)
                part = data:sub(1, pos-1)
                seqovl = 0
                if arg.seqovl and tonumber(arg.seqovl) > 0 then
                    seqovl = tonumber(arg.seqovl)
                    pat = "\x00"
                    if arg.seqovl_pattern then
                        if optional and blob not exists then
                            pat = "\x00"  -- fallback
                        else
                            pat = blob(seqovl_pattern)
                        end
                    end
                    part = pattern(pat, 1, seqovl) .. part
                end
                rawsend_payload_segmented(part, -seqovl, opts_orig)

                -- 12. ФЕЙК 1-й части (повтор)
                if not nofake2 then
                    rawsend_payload_segmented(fake, 0, opts_fake)
                end

                -- 13. ФЕЙК 2-й части
                fake = pattern(fakepat, pos, #data-pos+1)
                if not nofake3 then
                    rawsend_payload_segmented(fake, pos-1, opts_fake)
                end

                -- 14. РЕАЛЬНАЯ 2-я часть
                part = data:sub(pos)
                rawsend_payload_segmented(part, pos-1, opts_orig)

                -- 15. ФЕЙК 2-й части (повтор)
                if not nofake4 then
                    rawsend_payload_segmented(fake, pos-1, opts_fake)
                end

                -- 16. Пометить как отправленное
                replay_drop_set()
                return nodrop and VERDICT_PASS or VERDICT_DROP
            end
        else
            -- 17. Не первый replay
            DLOG("not acting on further replay pieces")
        end

        -- 18. Drop replayed packets если ранее успешно отправлено
        if replay_drop() then
            return nodrop and VERDICT_PASS or VERDICT_DROP
        end
    end
end
```

---

## Нюансы и подводные камни

### 1. Работает только с TCP

Если текущий пакет не TCP (UDP, ICMP и т.д.), `fakedsplit` делает `instance_cutoff_shim` — отключает себя для этого потока навсегда. Исключение: ICMP-пакеты (связанные с TCP) не вызывают cutoff.

### 2. Только ОДНА позиция разреза

В отличие от [[multisplit]], `fakedsplit` принимает **один** маркер, не список. `pos=midsld,endhost` не будет работать как два разреза — строка целиком передастся в `resolve_pos`, который не умеет парсить запятые. Если нужно несколько точек разреза с фейками — используйте цепочку инстансов или [[fakeddisorder]].

### 3. Позиция 1 не работает

Если `resolve_pos` возвращает 1, fakedsplit логирует "split pos resolved to 0. cannot split." и ничего не делает. `pos=1` бесполезна.

### 4. Fooling ОБЯЗАТЕЛЕН для фейков

Без fooling фейки будут приняты сервером как валидные данные, что сломает TCP-поток. Всегда указывайте хотя бы один метод fooling:

```bash
# НЕПРАВИЛЬНО — фейки будут приняты сервером!
--lua-desync=fakedsplit:pos=midsld

# ПРАВИЛЬНО — фейки отброшены по невалидному ACK
--lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

### 5. tcp_ts_up рекомендуется вместе с tcp_ack/tcp_seq

На Linux-серверах `tcp_ack=-66000` надёжно отбрасывает пакеты только если TCP timestamp option идёт первой. `tcp_ts_up` обеспечивает это. Всегда комбинируйте:

```bash
:tcp_ack=-66000:tcp_ts_up
```

### 6. repeats применяются ТОЛЬКО к фейкам

Если задать `repeats=5`, каждый фейк отправится 5 раз, а каждый оригинал — 1 раз. Это сделано специально: больше фейков => больше шума для DPI, но данные не дублируются.

### 7. ipfrag НЕ используется

В отличие от [[multisplit]] и [[multidisorder]], `fakedsplit` не поддерживает IP-фрагментацию. Оба набора опций имеют пустой `ipfrag = {}`. Если нужна IP-фрагментация поверх фейков — это не поддерживается напрямую.

### 8. badsum идёт только на фейки

`badsum` — часть `reconstruct`, который применяется только к фейкам. Оригиналы всегда имеют валидный checksum. Это безопасно и является ещё одним методом fooling.

### 9. nodrop создаёт сильное дублирование

С `nodrop` fakedsplit отправляет до 6 сегментов (фейки + оригиналы) И пропускает оригинальный пакет. Сервер получит данные как минимум дважды. Используйте `nodrop` только для отладки.

### 10. Порядок инстансов важен

Если перед `fakedsplit` стоит `pktmod` с модификацией — pktmod изменит payload, и fakedsplit порежет уже изменённые данные. Если после fakedsplit стоит ещё один инстанс — он увидит VERDICT_DROP и не получит оригинальный payload.

### 11. Неразрешённый маркер != ошибка

Если `resolve_pos` не смог разрешить маркер (например, `midsld` для `unknown` payload), fakedsplit логирует "cannot resolve pos" и **ничего не делает** — ни фейков, ни разреза. Оригинальный пакет проходит как есть.

---

## Отличия от других функций сегментации

| Аспект | `multisplit` | `multidisorder` | `fakedsplit` | `fakeddisorder` |
|:-------|:-------------|:----------------|:-------------|:----------------|
| Количество позиций | Список (любое кол-во) | Список (любое кол-во) | **Одна** | **Одна** |
| Резолвер позиций | `resolve_multi_pos` | `resolve_multi_pos` | **`resolve_pos`** | **`resolve_pos`** |
| Порядок отправки | Прямой (1->2->3) | Обратный (3->2->1) | Прямой (с фейками) | Обратный (с фейками) |
| Фейковые сегменты | **Нет** | **Нет** | Да (до 4 шт.) | Да (до 4 шт.) |
| Пакетов на выходе | N+1 (N позиций) | N+1 (N позиций) | До 6 (2 реальных + 4 фейка) | До 6 (2 реальных + 4 фейка) |
| seqovl тип | Только число | **Маркер** | Только число | **Маркер** |
| seqovl к какому сегменту | 1-й | 2-й (предпоследний) | 1-й реальный | 2-й реальный |
| Fooling к | Всем сегментам | Всем сегментам | **Только к фейкам** | **Только к фейкам** |
| reconstruct к | Всем сегментам | Всем сегментам | **Только к фейкам** | **Только к фейкам** |
| repeats к | Всем сегментам | Всем сегментам | **Только к фейкам** | **Только к фейкам** |
| ipfrag | Да | Да | **Нет** | **Нет** |
| ipid к | Всем сегментам | Всем сегментам | И фейкам, и оригиналам | И фейкам, и оригиналам |
| tcp_ts_up к оригиналам | Да (как часть fooling) | Да (как часть fooling) | **Да (единственный fooling)** | **Да (единственный fooling)** |

---

## Миграция с nfqws1

### Соответствие параметров

| nfqws1 | nfqws2 |
|:-------|:-------|
| `--dpi-desync=fakedsplit` | `--lua-desync=fakedsplit` |
| `--dpi-desync-split-pos=midsld` | `:pos=midsld` |
| `--dpi-desync-split-pos=method+2` | `:pos=method+2` |
| `--dpi-desync-fooling=badseq` | `:tcp_ack=-66000:tcp_ts_up` (или другой fooling) |
| `--dpi-desync-badseq-increment=0` | `:tcp_seq=0` (если нужен нулевой seq инкремент) |
| `--dpi-desync-split-seqovl=5` | `:seqovl=5` |
| `--dpi-desync-split-seqovl-pattern=0x1603030000` | `:seqovl_pattern=0x1603030000` |
| `--dpi-desync-any-protocol` | Не нужно; или `payload=all` в инстансе |

### Пример полной миграции

```bash
# nfqws1:
nfqws --dpi-desync=fakedsplit \
  --dpi-desync-fooling=badseq \
  --dpi-desync-badseq-increment=0 \
  --dpi-desync-split-pos=method+2

# nfqws2 (эквивалент):
nfqws2 \
  --payload=http_req \
    --lua-desync=fakedsplit:pos=method+2:tcp_ack=-66000:tcp_ts_up
```

```bash
# nfqws1:
nfqws --dpi-desync=fakedsplit \
  --dpi-desync-fooling=md5sig \
  --dpi-desync-split-pos=midsld \
  --dpi-desync-split-seqovl=5 \
  --dpi-desync-split-seqovl-pattern=0x1603030000

# nfqws2 (эквивалент):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fakedsplit:pos=midsld:tcp_md5:tcp_ts_up:seqovl=5:seqovl_pattern=0x1603030000
```

```bash
# nfqws1 с несколькими protocol:
nfqws --dpi-desync=fakedsplit \
  --dpi-desync-fooling=badseq \
  --dpi-desync-split-pos=2

# nfqws2 (разделяем по payload):
nfqws2 \
  --payload=tls_client_hello,http_req \
    --lua-desync=fakedsplit:pos=2:tcp_ack=-66000:tcp_ts_up
```

---

## Практические примеры

### 1. Минимальный (дефолт: pos=2, fooling=badseq)

```bash
--lua-desync=fakedsplit:tcp_ack=-66000:tcp_ts_up
```

Разрезает payload после 1-го байта => 2 реальных + 4 фейка = 6 пакетов. Фейки отбрасываются по невалидному ACK.

### 2. TLS: разрез посередине SNI

```bash
--payload=tls_client_hello --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

SNI разрезан пополам. В каждом фейке — нули вместо реальных данных. DPI не может собрать hostname ни из одного отдельного сегмента.

### 3. HTTP: разрез после метода

```bash
--payload=http_req --lua-desync=fakedsplit:pos=method+2:tcp_ack=-66000:tcp_ts_up
```

Для `GET /path...` разрежет после `GE`. DPI видит 6 сегментов — 3 "ретрансмиссии" для `GE*` и 3 для `T /path...`.

### 4. С seqovl (двойная защита)

```bash
--payload=tls_client_hello \
  --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up:seqovl=5:seqovl_pattern=0x1603030000
```

Фейки + seqovl в первом реальном сегменте. Даже если DPI отбросит фейки, seqovl-данные (выглядящие как начало TLS record) могут его сбить.

### 5. С кастомным паттерном для фейков

```bash
--blob=fakepat:0x474554202F HTTP --payload=http_req \
  --lua-desync=fakedsplit:pos=host:tcp_ack=-66000:tcp_ts_up:pattern=fakepat
```

Фейки заполнены данными, похожими на HTTP-запрос. DPI ещё больше запутывается.

### 6. С badsum вместо badseq

```bash
--payload=tls_client_hello --lua-desync=fakedsplit:pos=midsld:badsum:tcp_ts_up
```

Фейки отбрасываются сервером из-за невалидного TCP checksum. Не все DPI проверяют checksum, поэтому для многих этого достаточно.

### 7. С TCP MD5 signature

```bash
--payload=tls_client_hello --lua-desync=fakedsplit:pos=midsld:tcp_md5:tcp_ts_up
```

Фейки содержат TCP MD5 option. Сервер без настроенного MD5 отбросит такие пакеты.

### 8. Без "задних" фейков (оптимизация трафика)

```bash
--payload=tls_client_hello \
  --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up:nofake2:nofake4
```

Только 4 пакета вместо 6. Фейки идут только **до** реальных частей. Для многих DPI этого достаточно.

### 9. С повторами фейков (максимальный шум)

```bash
--payload=tls_client_hello \
  --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up:repeats=3
```

Каждый фейк отправляется 3 раза => 4*3 + 2 = 14 пакетов. Оригиналы — по 1 разу. Максимальное замусоривание потока для DPI.

### 10. С TTL-fooling (вместо badseq)

```bash
--payload=tls_client_hello \
  --lua-desync=fakedsplit:pos=midsld:ip_ttl=4:tcp_ts_up
```

Фейки имеют TTL=4 — не доживут до сервера, но DPI на пути их увидит. Менее надёжно, чем badseq (зависит от числа хопов).

### 11. Цепочка: fake + fakedsplit

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

Сначала отправляется полноценный TLS-фейк (поддельный ClientHello), затем реальный payload нарезается с замешиванием фейков. Двойной удар по DPI.

### 12. Комбинация с wssize и syndata

```bash
--lua-desync=wssize:wsize=1:scale=6 \
--lua-desync=syndata \
--payload=tls_client_hello \
  --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up:seqovl=5
```

Window size manipulation + SYN data + fakedsplit с seqovl. Многоуровневая защита.

### 13. Защита от отсутствующего blob

```bash
--lua-desync=fakedsplit:blob=maybe_missing:optional:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

Если blob не существует — тихий пропуск, без ошибок и без VERDICT_DROP.

### 14. Отладка: не блокировать оригинал

```bash
--payload=http_req --lua-desync=fakedsplit:pos=method+2:tcp_ack=-66000:tcp_ts_up:nodrop
```

Отправляет нарезанные сегменты с фейками И пропускает оригинальный пакет (для экспериментов).

### 15. Боевой пример для YouTube (TLS)

```bash
--filter-tcp=443 --hostlist=youtube.txt \
  --payload=tls_client_hello \
    --lua-desync=fakedsplit:pos=midsld:tcp_ack=-66000:tcp_ts_up:seqovl=5:seqovl_pattern=0x1603030000
```

Разрез SNI пополам + seqovl маскировка + badseq fooling. Оптимальная комбинация для TLS-трафика.

### 16. Боевой пример для HTTP

```bash
--filter-tcp=80 --hostlist=blocked.txt \
  --payload=http_req \
    --lua-desync=fakedsplit:pos=host:tcp_ack=-66000:tcp_ts_up
```

Разрез перед hostname в HTTP Host header. Ни один сегмент не содержит полный `Host: blocked.example.com`.

---

> **Источники:** `lua/zapret-antidpi.lua:803-906`, `lua/zapret-lib.lua:385-422`, `docs/manual.md:4122-4164` из репозитория zapret2.

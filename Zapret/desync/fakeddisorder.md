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
  - fakeddisorder
  - fakedsplit
  - disorder
  - seqovl
aliases:
  - fakeddisorder
---

# `fakeddisorder` — TCP-сегментация с фейками в обратном порядке (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:918`
**nfqws1 эквивалент:** `--dpi-desync=fakeddisorder`
**Сигнатура:** `function fakeddisorder(ctx, desync)`

`fakeddisorder` — функция TCP-десинхронизации с **двойным запутыванием** DPI: по содержимому (реальные vs фейковые сегменты) и по порядку (обратная последовательность — disorder). Payload разрезается по **одной** позиции на 2 части, и каждая часть обрамляется фейковыми сегментами. Отправка идёт в обратном порядке: сначала вторая часть (с фейками), затем первая (с фейками). Итого — 6 пакетов. После успешной отправки выносит `VERDICT_DROP`, чтобы оригинальный пакет не ушёл.

Родственные функции: [[multisplit]] (прямой порядок, без фейков), [[multidisorder]] (обратный порядок, без фейков), [[fakedsplit]] (с фейками, прямой порядок), [[hostfakesplit]] (по hostname), [[tcpseg]] (диапазон), [[oob]] (urgent byte).

---

## Оглавление

- [Зачем нужен fakeddisorder](#зачем-нужен-fakeddisorder)
- [Быстрый старт](#быстрый-старт)
- [Откуда берутся данные для нарезки](#откуда-берутся-данные-для-нарезки)
- [Маркер позиции (pos)](#маркер-позиции-pos)
  - [Типы маркеров](#типы-маркеров)
  - [Относительные маркеры](#относительные-маркеры)
  - [Арифметика маркеров](#арифметика-маркеров)
  - [Как маркер разрешается в коде](#как-маркер-разрешается-в-коде)
  - [Важные нюансы pos](#важные-нюансы-pos)
- [seqovl — скрытый фейк внутри реального сегмента](#seqovl--скрытый-фейк-внутри-реального-сегмента)
  - [Принцип работы seqovl в fakeddisorder](#принцип-работы-seqovl-в-fakeddisorder)
  - [seqovl — маркер, а не число](#seqovl--маркер-а-не-число)
  - [Зачем seqovl лучше обычного fooling](#зачем-seqovl-лучше-обычного-fooling)
  - [seqovl_pattern](#seqovl_pattern)
- [Фейковые сегменты и pattern](#фейковые-сегменты-и-pattern)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы fakeddisorder](#a-собственные-аргументы-fakeddisorder)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard reconstruct](#f-standard-reconstruct)
  - [G) Standard rawsend](#g-standard-rawsend)
- [Порядок отправки сегментов (6 пакетов)](#порядок-отправки-сегментов-6-пакетов)
  - [ASCII-диаграмма полной последовательности](#ascii-диаграмма-полной-последовательности)
  - [Пример с seqovl](#пример-с-seqovl)
  - [Пример с nofake-флагами](#пример-с-nofake-флагами)
- [Применение fooling и reconstruct](#применение-fooling-и-reconstruct)
- [Поведение при replay / reasm](#поведение-при-replay--reasm)
- [Автосегментация по MSS](#автосегментация-по-mss)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Отличия от fakedsplit, multisplit и multidisorder](#отличия-от-fakedsplit-multisplit-и-multidisorder)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен fakeddisorder

DPI анализирует TCP-поток, пытаясь собрать полный payload и найти в нём сигнатуры (hostname в HTTP, SNI в TLS). `fakeddisorder` атакует DPI двумя способами одновременно:

1. **Запутывание по содержимому (fake).** Между реальными сегментами посылаются фейковые, содержащие мусорные данные. DPI должен отличить настоящие сегменты от поддельных. Фейки отбрасываются сервером благодаря [[fooling]] (badseq, badsum, TTL и т.д.), но DPI может их проглотить.

2. **Запутывание по порядку (disorder).** Сегменты отправляются в **обратном порядке**: сначала вторая часть payload, затем первая. DPI, ожидающий последовательного потока, может быть сбит с толку.

**Двойное запутывание** (содержимое + порядок) эффективнее, чем каждый приём по отдельности:

```
multisplit:       [часть 1] → [часть 2]                    — только разрез
multidisorder:    [часть 2] → [часть 1]                    — разрез + обратный порядок
fakedsplit:       [F1][часть 1][F2] → [F3][часть 2][F4]    — разрез + фейки
fakeddisorder:    [F1][часть 2][F2] → [F3][часть 1][F4]    — разрез + фейки + обратный порядок
```

Сервер при этом корректно собирает поток — TCP-стек гарантирует это через sequence numbers, а фейки отбрасываются благодаря fooling.

---

## Быстрый старт

Минимально (разрез по позиции 2, payload=known, dir=out):

```bash
--lua-desync=fakeddisorder:tcp_ack=-66000
```

Типовой TLS-разрез посередине SNI:

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

TLS с seqovl для тройного запутывания:

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:seqovl=5:seqovl_pattern=0x1603030000:tcp_ack=-66000:tcp_ts_up
```

HTTP с кастомным паттерном фейков:

```bash
--payload=http_req --lua-desync=fakeddisorder:pos=host:pattern=0x474554202F:tcp_ack=-66000
```

---

## Откуда берутся данные для нарезки

Внутри `fakeddisorder` данные (`data`) выбираются в следующем порядке приоритетов:

```
1. blob_or_def(desync, desync.arg.blob)    — если задан blob= и он существует
2. desync.reasm_data                        — если есть реассемблированные данные (multi-packet payload)
3. desync.dis.payload                       — текущий пакет (fallback)
```

**Следствие:** все маркеры `pos`, `seqovl` и прочие аргументы применяются именно к тем данным, которые реально выбраны. Если вы задали `blob=myblob`, маркеры вроде `midsld` будут работать только если `myblob` содержит валидный TLS/HTTP payload, который zapret может распознать.

---

## Маркер позиции (pos)

`pos` — главный аргумент `fakeddisorder`. Определяет **где** внутри payload будет произведён разрез. В отличие от [[multisplit]] и [[multidisorder]], `pos` — это **один маркер**, а не список. Payload всегда разрезается на **ровно 2 части**.

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
method+2      — два байта после начала метода
sniext+1      — один байт после начала SNI extension data
host+3        — три байта после начала hostname
-1            — последний байт payload (абсолютный, не относительный)
```

### Как маркер разрешается в коде

В отличие от [[multisplit]] (который использует `resolve_multi_pos` для списка маркеров), `fakeddisorder` использует `resolve_pos` — функцию для **одного** маркера:

```lua
local spos = desync.arg.pos or "2"
local pos = resolve_pos(data, desync.l7payload, spos)
```

`resolve_pos` возвращает одно число (абсолютную Lua-позицию, 1-based) или `nil`, если маркер не может быть разрешён.

### Важные нюансы pos

- **Только ОДИН маркер.** `pos=midsld,endhost` — невалидно (в отличие от multisplit/multidisorder, которые принимают списки). Если вам нужно несколько позиций разреза с фейками — используйте несколько инстансов `fakeddisorder` в цепочке.
- **Позиция 1 запрещена.** Если маркер разрешается в позицию 1, fakeddisorder логирует `"split pos resolved to 0. cannot split."` и ничего не делает. Для разреза "после 1-го байта" используйте `pos=2` (дефолт).
- **Неразрешимый маркер = ничего не делает.** Если маркер не может быть разрешён (например, `midsld` для `unknown` payload), fakeddisorder логирует `"cannot resolve pos"` и пропускает операцию.
- **По умолчанию pos="2".** Если `pos` не задан, разрез по позиции 2 — payload делится на 1-й байт и остальное.

---

## seqovl — скрытый фейк внутри реального сегмента

**seqovl** (Sequence Overlap) — техника скрытого замешивания фейковых данных в реальный TCP-сегмент через манипуляцию TCP sequence number. В `fakeddisorder` seqovl применяется **только ко второму реальному сегменту** (real part 2 — первый реальный пакет в порядке отправки).

### Принцип работы seqovl в fakeddisorder

```
Без seqovl:
  Пакет 2 (real part 2):
    TCP seq: pos-1
    Данные:  [РЕАЛЬНАЯ_ЧАСТЬ_2]
    Сервер:  принимает [РЕАЛЬНАЯ_ЧАСТЬ_2] целиком

С seqovl=10:
  Пакет 2 (real part 2):
    TCP seq: pos-1-10           (уменьшен на 10)
    Данные:  [PATTERN_10_БАЙТ][РЕАЛЬНАЯ_ЧАСТЬ_2]

  Что видит DPI:
    Единый TCP-сегмент начиная с seq pos-1-10.
    DPI анализирует весь блок, включая PATTERN.
    PATTERN содержит мусор → DPI может не распознать SNI.

  Что видит сервер (TCP-стек):
    Байты до pos-1 выходят за левую границу window → отбрасываются.
    Байты с pos-1 (РЕАЛЬНАЯ_ЧАСТЬ_2) → принимаются.
```

**Визуализация:**

```
           TCP window boundary (= pos-1)
                 ↓
  |  ОТБРОСИТЬ  | ПРИНЯТЬ              |
  | PATTERN(10) | РЕАЛЬНАЯ_ЧАСТЬ_2     |
  ^seq=pos-11    ^seq=pos-1
```

### seqovl — маркер, а не число

**Критическое отличие от [[multisplit]] и [[fakedsplit]]:** в `fakeddisorder` (как и в [[multidisorder]]) `seqovl` — это **маркер**, а не просто число. Он разрешается через `resolve_pos`:

```lua
seqovl = resolve_pos(data, desync.l7payload, desync.arg.seqovl)
seqovl = seqovl - 1  -- Lua→0-based
```

Это значит, что можно использовать:
- `seqovl=5` — абсолютное число (разрешится в 5, станет 4 после `-1`)
- `seqovl=host` — относительный маркер (разрешится в позицию начала hostname, `-1`)
- `seqovl=midsld-2` — маркер с арифметикой

**Ограничение:** результат `seqovl` (после `-1`) должен быть **строго меньше** `pos-1`. Иначе seqovl отменяется с логом:

```
fakeddisorder: seqovl cancelled because seqovl N is not less than the split pos M
```

Если маркер не разрешается, seqovl тоже отменяется:

```
fakeddisorder: seqovl cancelled because could not resolve marker 'xxx'
```

### Зачем seqovl лучше обычного fooling

| Критерий | Обычный fooling (TTL, badseq, md5sig) | seqovl |
|:---------|:---------------------------------------|:-------|
| Заголовки | Модифицируются (TTL, seq, ack, md5) | **Не модифицируются** — пакет выглядит полностью легитимным |
| Обнаружение | DPI может детектировать подозрительные заголовки | DPI видит "честный" сегмент с правильными заголовками |
| Механизм отбрасывания | Сервер отбрасывает весь пакет из-за невалидных заголовков | Сервер отбрасывает только часть, выходящую за TCP window |
| Надёжность | Зависит от поведения конкретного стека | Основан на фундаментальном свойстве TCP |

**Вывод:** seqovl добавляет третий уровень запутывания (к фейкам и disorder), причём реальный сегмент с seqovl выглядит абсолютно легитимно для DPI.

### seqovl_pattern

Паттерн, которым заполняется seqovl-область. По умолчанию — `0x00` (нули).

В `fakeddisorder` `seqovl_pattern` — это **имя blob**. Паттерн повторяется до нужной длины `seqovl`.

```bash
# Inline hex blob (маскировка под начало TLS record)
--lua-desync=fakeddisorder:pos=midsld:seqovl=5:seqovl_pattern=0x1603030000:tcp_ack=-66000

# Предзагруженный blob
--blob=tlspat:0x1603030100 \
--lua-desync=fakeddisorder:pos=midsld:seqovl=8:seqovl_pattern=tlspat:tcp_ack=-66000
```

Если `optional` задан и blob `seqovl_pattern` отсутствует — используется нулевой паттерн (seqovl не отменяется).

---

## Фейковые сегменты и pattern

Фейковые сегменты генерируются функцией `pattern()`:

```lua
fakepat = desync.arg.pattern and blob(desync, desync.arg.pattern) or "\x00"
fake_part2 = pattern(fakepat, pos, #data - pos + 1)   -- фейк для части 2
fake_part1 = pattern(fakepat, 1, pos - 1)             -- фейк для части 1
```

**Ключевые свойства:**

- Фейк **совпадает по размеру** с реальной частью, которую он имитирует
- `pattern()` принимает смещение (`pos` или `1`), что означает, что фейк заполняется так, как будто он начинается с той же позиции в payload. Это делает его TCP sequence корректным для DPI
- По умолчанию `pattern` = `\x00` (нули). Можно задать свой blob через `pattern=<blob>`
- Blob повторяется до нужной длины

**Важно:** фейки **отправляются с полным fooling** (badseq, TTL и т.д.), чтобы сервер их отбросил. Без fooling сервер примет фейки как реальные данные и поток будет повреждён.

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=fakeddisorder[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`, `:nodrop`, `:tcp_ts_up`.

### A) Собственные аргументы fakeddisorder

#### `pos`

- **Формат:** `pos=<marker>`
- **Тип:** строка с **одним** маркером (НЕ список!)
- **По умолчанию:** `"2"`
- **Описание:** Точка разреза. Payload делится на 2 части: `data[1..pos-1]` и `data[pos..#data]`
- **Примеры:**
  - `pos=2` — разрез после 1-го байта (дефолт)
  - `pos=midsld` — разрез посередине SLD
  - `pos=host` — разрез в начале hostname
  - `pos=sniext+1` — один байт после начала SNI extension data
  - `pos=endhost-2` — два байта до конца hostname

#### `seqovl`

- **Формат:** `seqovl=<marker>`
- **Тип:** **маркер** (не только число — в отличие от multisplit/fakedsplit!)
- **По умолчанию:** не задан (нет seqovl)
- **Описание:** Применяется ко **второму реальному сегменту** (real part 2). К данным слева добавляется `seqovl` байт `seqovl_pattern`, а TCP `th_seq` уменьшается на `seqovl`. Маркер разрешается через `resolve_pos`, затем результат уменьшается на 1 (Lua→0-based). Результат должен быть строго меньше `pos-1`
- **Примеры:**
  - `seqovl=5` — 4 байта фейка слева (5→resolve→5, 5-1=4)
  - `seqovl=host` — seqovl равен позиции начала hostname (минус 1)
  - `seqovl=sld-2` — маркер с арифметикой

#### `seqovl_pattern`

- **Формат:** `seqovl_pattern=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** один байт `0x00`, повторяемый до длины `seqovl`
- **Описание:** Данные для заполнения seqovl-области. Blob повторяется функцией `pattern()` до нужного размера
- **Поведение с `optional`:** если `optional` задан и blob отсутствует — используется нулевой паттерн, seqovl не отменяется
- **Примеры:**
  - `seqovl_pattern=0x1603030000` — inline hex (маскировка под TLS)
  - `seqovl_pattern=my_pattern_blob` — предзагруженный blob

#### `pattern`

- **Формат:** `pattern=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** один байт `0x00`
- **Описание:** Данные для заполнения **фейковых** сегментов. Blob повторяется до размера соответствующей реальной части
- **Примеры:**
  - `pattern=0x474554202F` — inline hex (маскировка под начало HTTP GET)
  - `pattern=fake_tls_pat` — предзагруженный blob

#### `blob`

- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** не задан
- **Описание:** Заменить текущий payload/reasm на указанный blob и резать/слать его. Используется для отправки произвольных данных (фейковых payload, модифицированных ClientHello и т.д.)
- **Примеры:**
  - `blob=fake_default_tls` — стандартный TLS-фейк
  - `blob=0xDEADBEEF` — inline hex
  - `blob=my_custom_ch` — предзагруженный blob

#### `nofake1`

- **Формат:** `nofake1` (флаг, без значения)
- **Описание:** Не отправлять **первый** фейковый пакет (fake part 2, первый по порядку отправки)

#### `nofake2`

- **Формат:** `nofake2` (флаг, без значения)
- **Описание:** Не отправлять **третий** пакет (fake part 2 повторно, после реального part 2)

#### `nofake3`

- **Формат:** `nofake3` (флаг, без значения)
- **Описание:** Не отправлять **четвёртый** пакет (fake part 1, перед реальным part 1)

#### `nofake4`

- **Формат:** `nofake4` (флаг, без значения)
- **Описание:** Не отправлять **шестой** пакет (fake part 1 повторно, после реального part 1)

#### `optional`

- **Формат:** `optional` (флаг, без значения)
- **Описание:** Мягкий режим:
  - Если задан `blob=...` и blob отсутствует — fakeddisorder **ничего не делает** (тихий skip, без ошибок)
  - Если задан `seqovl_pattern=...` и blob отсутствует — используется нулевой паттерн (seqovl не отменяется)

#### `nodrop`

- **Формат:** `nodrop` (флаг, без значения)
- **Описание:** После успешной отправки **не выносить** `VERDICT_DROP` (вместо этого вернуть `VERDICT_PASS`). Оригинальный пакет тоже будет отправлен (наряду с 6 нарезанными пакетами)
- **Предупреждение:** в боевых профилях `nodrop` обычно нежелателен — оригинал ещё раз уйдёт, что создаст дублирование

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `fakeddisorder` по умолчанию работает только с исходящими (`out`).

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

Модификации L3/L4 заголовков. В `fakeddisorder` fooling применяется **только к фейковым сегментам**. К реальным применяется **только** `tcp_ts_up`.

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

**Ключевое:** `tcp_ts_up` — единственный параметр fooling, который применяется и к реальным, и к фейковым сегментам. Все остальные fooling-параметры применяются **только к фейкам**.

**Заметка про tcp_ts_up:** На Linux-серверах пакеты с инвалидным ACK стабильно отбрасываются **только если** TCP timestamp option идёт первой в заголовке. `tcp_ts_up` перемещает её в начало, обеспечивая корректную работу badseq-fooling. Поэтому `tcp_ts_up` рекомендуется включать всегда вместе с `tcp_ack`.

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | — |
| `ip_id=zero` | Нулевые IP ID | — |
| `ip_id=none` | Не менять IP ID | — |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения (требует tracking) | — |

`ip_id` применяется **и к фейкам, и к оригиналам**.

---

### F) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета |

`reconstruct` применяется **только к фейкам**. К оригиналам reconstruct не применяется.

---

### G) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить каждый пакет N раз (применяется **только к фейкам**) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

**Важно:** `repeats` в `fakeddisorder` применяется **только к фейковым** сегментам (через `rawsend_opts`), а не ко всем. Реальные сегменты отправляются через `rawsend_opts_base`, где repeats не задействуется.

**Важно:** `ipfrag` **не задействуется** в fakeddisorder — ни для фейков, ни для оригиналов. Объект `ipfrag` установлен в пустую таблицу `{}` для обоих типов пакетов.

---

## Порядок отправки сегментов (6 пакетов)

`fakeddisorder` всегда отправляет **6 пакетов** (если все nofake-флаги не установлены). Порядок **обратный** по отношению к [[fakedsplit]]: сначала идёт вторая часть (с фейками), затем первая (с фейками).

### ASCII-диаграмма полной последовательности

```
Payload (100 байт), pos=midsld (разрешился в позицию 40):

  Часть 1: data[1..39]     (39 байт, seq offset = 0)
  Часть 2: data[40..100]   (61 байт, seq offset = 39)

Порядок отправки (хронологический):

  №  Пакет              Тип      seq offset  Размер  Opts         nofake
  ─────────────────────────────────────────────────────────────────────────
  1  fake  part 2       ФЕЙК     39          61      opts_fake    nofake1
  2  real  part 2       РЕАЛ     39 (-seqovl) 61(+ovl) opts_orig    —
  3  fake  part 2       ФЕЙК     39          61      opts_fake    nofake2
  4  fake  part 1       ФЕЙК     0           39      opts_fake    nofake3
  5  real  part 1       РЕАЛ     0           39      opts_orig    —
  6  fake  part 1       ФЕЙК     0           39      opts_fake    nofake4
  ─────────────────────────────────────────────────────────────────────────

opts_orig: только tcp_ts_up из fooling, пустой reconstruct, пустой ipfrag
opts_fake: полный fooling + полный reconstruct, пустой ipfrag
```

**Визуализация на временной оси:**

```
Время ──────────────────────────────────────────────────────────────────→

  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
  │ FAKE P2  │  │ REAL P2  │  │ FAKE P2  │  │ FAKE P1  │  │ REAL P1  │  │ FAKE P1  │
  │ nofake1  │  │ (+seqovl)│  │ nofake2  │  │ nofake3  │  │          │  │ nofake4  │
  │ seq=39   │  │ seq=39-N │  │ seq=39   │  │ seq=0    │  │ seq=0    │  │ seq=0    │
  │ [МУСОР]  │  │[PAT][DAT]│  │ [МУСОР]  │  │ [МУСОР]  │  │ [ДАННЫЕ] │  │ [МУСОР]  │
  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
  ^^^^ФЕЙК^^^^  ^^РЕАЛЬНЫЙ^^  ^^^^ФЕЙК^^^^  ^^^^ФЕЙК^^^^  ^^РЕАЛЬНЫЙ^^  ^^^^ФЕЙК^^^^
       ↓              ↓             ↓             ↓              ↓             ↓
   сервер            сервер      сервер       сервер          сервер       сервер
   ОТБРОСИТ          ПРИМЕТ      ОТБРОСИТ     ОТБРОСИТ        ПРИМЕТ       ОТБРОСИТ
  (fooling)                     (fooling)    (fooling)                    (fooling)
```

**Сравнение с fakedsplit (прямой порядок):**

```
fakedsplit:      [F1_P1] [REAL_P1] [F2_P1] → [F3_P2] [REAL_P2] [F4_P2]
fakeddisorder:   [F1_P2] [REAL_P2] [F2_P2] → [F3_P1] [REAL_P1] [F4_P1]
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^   ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                 Сначала ВТОРАЯ часть            Потом ПЕРВАЯ часть
```

### Пример с seqovl

```
Payload (100 байт), pos=midsld (40), seqovl=10:

  №  Пакет              seq offset   Данные
  ──────────────────────────────────────────────────────────────────────────
  1  fake  part 2       39           [PATTERN 61 байт]
  2  real  part 2       29           [SEQOVL_PAT 10 байт][data[40..100] 61 байт]
  3  fake  part 2       39           [PATTERN 61 байт]
  4  fake  part 1       0            [PATTERN 39 байт]
  5  real  part 1       0            [data[1..39] 39 байт]
  6  fake  part 1       0            [PATTERN 39 байт]

  Сервер для пакета 2:
    TCP window начинается с seq=39
    Байты 29-38 (SEQOVL_PAT) → отбрасываются
    Байты 39-99 (data[40..100]) → принимаются
```

### Пример с nofake-флагами

```
fakeddisorder:pos=midsld:tcp_ack=-66000:nofake2:nofake4

Отправляется 4 пакета вместо 6:

  №  Пакет              Тип
  ────────────────────────────
  1  fake  part 2       ФЕЙК
  2  real  part 2       РЕАЛ
  —  (пропущен nofake2)
  3  fake  part 1       ФЕЙК
  4  real  part 1       РЕАЛ
  —  (пропущен nofake4)
```

Можно отключить все фейки кроме одного, или вообще все:

```
# Только 2 реальных пакета (все фейки отключены) = multidisorder с одной позицией
fakeddisorder:pos=midsld:nofake1:nofake2:nofake3:nofake4
```

---

## Применение fooling и reconstruct

Это ключевое отличие от [[multisplit]] и [[multidisorder]], где fooling применяется ко всем сегментам.

```
                          opts_orig                      opts_fake
                    (реальные сегменты)            (фейковые сегменты)
  ───────────────────────────────────────────────────────────────────
  fooling           ТОЛЬКО tcp_ts_up               ВСЁ (tcp_ack, tcp_seq,
                                                    ip_ttl, tcp_md5, ...)
  reconstruct       пусто ({})                     ВСЁ (badsum и т.д.)
  ipfrag            пусто ({})                     пусто ({})
  ipid              desync.arg (полный)            desync.arg (полный)
  rawsend           rawsend_opts_base              rawsend_opts (с repeats)
  ───────────────────────────────────────────────────────────────────
```

**Почему так:** реальные сегменты должны дойти до сервера в неповреждённом виде. Fooling вроде `tcp_ack=-66000` сделал бы их невалидными для сервера. Поэтому fooling идёт только на фейки — чтобы сервер их отбросил, а DPI — запутался.

Исключение — `tcp_ts_up`. Он не портит пакет, а лишь перемещает TCP timestamp в начало заголовка. Это полезно для обеспечения корректной работы badseq/badack на принимающей стороне и применяется ко всем сегментам.

---

## Поведение при replay / reasm

При многопакетных payload (например, большой TLS ClientHello с post-quantum Kyber, который не влезает в один TCP-сегмент) zapret собирает все части в `reasm_data`. При перепроигрывании (replay):

1. **Первая часть replay:** fakeddisorder берёт **весь** `reasm_data`, нарезает и отправляет 6 пакетов. Устанавливает флаг `replay_drop_set`
2. **Все последующие части replay:** fakeddisorder видит, что отправка уже произошла, и выносит `VERDICT_DROP` (если не `nodrop`) — потому что весь reasm уже отправлен нарезанным, нет смысла отправлять оригинальные части

**Исключение:** если первая отправка неуспешна (`rawsend_payload_segmented` вернул `false`), флаг не устанавливается и последующие части проходят как есть.

---

## Автосегментация по MSS

О размерах TCP-сегментов думать **не нужно**. Функция `rawsend_payload_segmented` из `zapret-lib.lua` автоматически:

1. Отслеживает MSS для каждого TCP-соединения
2. Если часть payload превышает MSS — дополнительно режет по MSS
3. Каждый под-сегмент отправляется с корректным TCP sequence

---

## Псевдокод алгоритма

```lua
function fakeddisorder(ctx, desync)
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
            -- 7. Разрешение маркера (ОДИН, не список!)
            spos = desync.arg.pos or "2"
            pos = resolve_pos(data, l7payload, spos)

            if pos == nil then
                DLOG("cannot resolve pos")
            elseif pos == 1 then
                DLOG("split pos resolved to 0. cannot split.")
            else
                -- 8. Подготовка opts
                opts_orig = {
                    fooling = {tcp_ts_up = desync.arg.tcp_ts_up},  -- ТОЛЬКО tcp_ts_up
                    reconstruct = {},                                -- пусто
                    ipfrag = {},                                     -- пусто
                    ipid = desync.arg,
                    rawsend = rawsend_opts_base(desync)
                }
                opts_fake = {
                    fooling = desync.arg,           -- ПОЛНЫЙ fooling
                    reconstruct = reconstruct_opts(desync),  -- ПОЛНЫЙ reconstruct
                    ipfrag = {},                     -- пусто
                    ipid = desync.arg,
                    rawsend = rawsend_opts(desync)   -- с repeats
                }

                fakepat = pattern_blob or "\x00"

                -- ============ ЧАСТЬ 2 (ОБРАТНЫЙ ПОРЯДОК!) ============

                -- 9. Fake part 2 (пакет 1)
                fake2 = pattern(fakepat, pos, #data - pos + 1)
                if not nofake1 then
                    rawsend_payload_segmented(fake2, pos-1, opts_fake)
                end

                -- 10. Real part 2 + seqovl (пакет 2)
                part2 = data:sub(pos)
                seqovl = 0
                if desync.arg.seqovl then
                    seqovl = resolve_pos(data, l7payload, desync.arg.seqovl)
                    if seqovl then
                        seqovl = seqovl - 1    -- Lua→0-based
                        if seqovl >= (pos-1) then
                            DLOG("seqovl cancelled: not less than split pos")
                            seqovl = 0
                        else
                            pat = seqovl_pattern_blob or "\x00"
                            part2 = pattern(pat, 1, seqovl) .. part2
                        end
                    else
                        DLOG("seqovl cancelled: cannot resolve marker")
                        seqovl = 0
                    end
                end
                rawsend_payload_segmented(part2, pos-1-seqovl, opts_orig)

                -- 11. Fake part 2 again (пакет 3)
                if not nofake2 then
                    rawsend_payload_segmented(fake2, pos-1, opts_fake)
                end

                -- ============ ЧАСТЬ 1 ============

                -- 12. Fake part 1 (пакет 4)
                fake1 = pattern(fakepat, 1, pos-1)
                if not nofake3 then
                    rawsend_payload_segmented(fake1, 0, opts_fake)
                end

                -- 13. Real part 1 (пакет 5)
                part1 = data:sub(1, pos-1)
                rawsend_payload_segmented(part1, 0, opts_orig)

                -- 14. Fake part 1 again (пакет 6)
                if not nofake4 then
                    rawsend_payload_segmented(fake1, 0, opts_fake)
                end

                -- 15. Пометить как отправленное
                replay_drop_set()
                return nodrop and VERDICT_PASS or VERDICT_DROP
            end
        else
            -- 16. Не первый replay
            DLOG("not acting on further replay pieces")
        end
        -- 17. Дропнуть если ранее успешно отправлено
        if replay_drop() then
            return nodrop and VERDICT_PASS or VERDICT_DROP
        end
    end
end
```

---

## Нюансы и подводные камни

### 1. Работает только с TCP

Если текущий пакет не TCP (UDP, ICMP и т.д.), `fakeddisorder` делает `instance_cutoff_shim` — отключает себя для этого потока навсегда. Исключение — ICMP-пакеты (related), для которых cutoff не выполняется (просто return).

### 2. Только ОДИН маркер в pos

В отличие от [[multisplit]] и [[multidisorder]], `fakeddisorder` принимает **один** маркер, а не список. `pos=midsld,endhost` не будет работать как два разреза. Если нужно несколько разрезов с фейками, используйте цепочку инстансов (хотя это нетривиально из-за VERDICT_DROP).

### 3. Позиция 1 не работает

Если маркер разрешается в позицию 1 (Lua 1-based), fakeddisorder логирует `"split pos resolved to 0. cannot split."` и ничего не делает. Используйте `pos=2` (дефолт).

### 4. Fooling ОБЯЗАТЕЛЕН для фейков

Без fooling-параметров (tcp_ack, tcp_seq, ip_ttl, tcp_md5, badsum и т.д.) сервер **примет фейковые сегменты** как реальные данные. Это повредит TCP-поток. Всегда указывайте хотя бы один fooling-параметр:

```bash
# ПЛОХО: фейки без fooling — сервер их примет!
--lua-desync=fakeddisorder:pos=midsld

# ХОРОШО: фейки с badseq
--lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

### 5. tcp_ts_up рекомендуется с tcp_ack

На Linux-серверах пакеты с инвалидным ACK стабильно отбрасываются **только если** TCP timestamp option идёт первой в заголовке. Без `tcp_ts_up` есть риск, что сервер примет фейк с `tcp_ack=-66000`.

### 6. ipfrag НЕ задействуется

В отличие от [[multisplit]] и [[multidisorder]], `fakeddisorder` не поддерживает IP-фрагментацию. Объект `ipfrag` установлен в `{}` и для фейков, и для оригиналов. Если нужна IP-фрагментация — используйте `multidisorder` (без фейков, но с ipfrag).

### 7. seqovl — маркер, а не число

В [[multisplit]] и [[fakedsplit]] seqovl — просто `tonumber(desync.arg.seqovl)`. В `fakeddisorder` (как и в [[multidisorder]]) seqovl разрешается через `resolve_pos`. Это значит:
- `seqovl=5` работает (разрешится в абсолютную позицию 5, затем -1 = 4)
- `seqovl=host` тоже работает
- Но результат должен быть < pos-1

### 8. seqovl применяется только к real part 2

В отличие от [[fakedsplit]] (где seqovl к real part 1 — первому реальному), в `fakeddisorder` seqovl применяется к real part 2 — первому реальному по порядку отправки (но второму по порядку в payload). Это логично: в disorder-порядке сначала отправляется вторая часть, и именно она получает seqovl.

### 9. nodrop создаёт дублирование

С `nodrop` fakeddisorder отправляет 6 нарезанных пакетов И пропускает оригинальный. Сервер получит данные дважды. Используйте `nodrop` только для отладки.

### 10. Ошибка rawsend прерывает цепочку

Если любой из 6 вызовов `rawsend_payload_segmented` возвращает `false`, fakeddisorder немедленно возвращает `VERDICT_PASS` (оригинальный пакет пропускается). Остальные пакеты из 6 не отправляются, `replay_drop_set` не вызывается.

### 11. Порядок инстансов важен

Если перед `fakeddisorder` стоит `fake` — он отправит свой фейк до того, как fakeddisorder начнёт свою последовательность. Если после fakeddisorder стоит ещё один инстанс — он увидит VERDICT_DROP и не получит оригинальный payload.

---

## Отличия от fakedsplit, multisplit и multidisorder

| Аспект | `multisplit` | `multidisorder` | `fakedsplit` | `fakeddisorder` |
|:-------|:-------------|:----------------|:-------------|:----------------|
| Количество позиций | Список (любое кол-во) | Список (любое кол-во) | **Одна** | **Одна** |
| Порядок отправки | Прямой (1-2-3) | Обратный (3-2-1) | Прямой (1-2) | **Обратный (2-1)** |
| Фейковые сегменты | **Нет** | **Нет** | Да (до 4 шт.) | **Да (до 4 шт.)** |
| Всего пакетов (max) | N+1 (по кол-ву позиций) | N+1 | **6** | **6** |
| seqovl тип | Только число | **Маркер** | Только число | **Маркер** |
| seqovl к какому сегменту | 1-й (прямой) | 2-й (предпоследний) | 1-й реальный (part 1) | **2-й реальный (part 2)** |
| Fooling к | **Всем** сегментам | **Всем** сегментам | Только к фейкам | **Только к фейкам** |
| reconstruct к | **Всем** | **Всем** | Только к фейкам | **Только к фейкам** |
| repeats к | **Всем** | **Всем** | Только к фейкам | **Только к фейкам** |
| ipfrag | Да | Да | **Нет** | **Нет** |
| Уровень запутывания | Один (разрез) | Два (разрез + порядок) | Два (разрез + фейки) | **Три (разрез + фейки + порядок)** |

### Когда что использовать

| Сценарий | Рекомендация |
|:---------|:-------------|
| DPI не реассемблирует TCP, достаточно разрезать | [[multisplit]] |
| DPI реассемблирует, но не проверяет порядок | [[multidisorder]] |
| DPI проверяет порядок, но не отличает фейки | [[fakedsplit]] |
| DPI проверяет и порядок, и содержимое | **`fakeddisorder`** |
| Нужна IP-фрагментация поверх TCP | [[multisplit]] или [[multidisorder]] |
| Нужно несколько позиций разреза с фейками | Цепочка [[fakedsplit]] / `fakeddisorder` |

---

## Миграция с nfqws1

### Соответствие параметров

| nfqws1 | nfqws2 |
|:-------|:-------|
| `--dpi-desync=fakeddisorder` | `--lua-desync=fakeddisorder` |
| `--dpi-desync-split-pos=midsld` | `:pos=midsld` |
| `--dpi-desync-fooling=badseq` | `:tcp_ack=-66000:tcp_ts_up` |
| `--dpi-desync-fooling=badack` | `:tcp_ack=-66000:tcp_ts_up` |
| `--dpi-desync-fooling=md5sig` | `:tcp_md5` |
| `--dpi-desync-fooling=datanoack` | `:tcp_flags_unset=ACK` |
| `--dpi-desync-fooling=hopbyhop` | `:ip6_hopbyhop` |
| `--dpi-desync-fooling=hopbyhop2` | `:ip6_hopbyhop2` |
| `--dpi-desync-split-seqovl=N` | `:seqovl=N` |
| `--dpi-desync-split-seqovl-pattern=HEX` | `:seqovl_pattern=HEX` |
| `--dpi-desync-fake-tls=FILE` | `:pattern=<blobname>` (предзагрузить через `--blob=`) |
| `--dpi-desync-any-protocol` | Не нужно; или `payload=all` в инстансе |

### Пример полной миграции

```bash
# nfqws1:
nfqws --dpi-desync=fakeddisorder \
  --dpi-desync-fooling=badseq \
  --dpi-desync-split-pos=midsld

# nfqws2 (эквивалент):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

```bash
# nfqws1 (комплексный):
nfqws --dpi-desync=fakeddisorder \
  --dpi-desync-fooling=md5sig \
  --dpi-desync-split-pos=midsld \
  --dpi-desync-split-seqovl=5 \
  --dpi-desync-split-seqovl-pattern=0x1603030000

# nfqws2 (эквивалент):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fakeddisorder:pos=midsld:tcp_md5:seqovl=5:seqovl_pattern=0x1603030000
```

```bash
# nfqws1 (фулл):
nfqws --dpi-desync=fake,fakeddisorder \
  --dpi-desync-fooling=badseq \
  --dpi-desync-split-pos=midsld \
  --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid

# nfqws2 (эквивалент — fake отдельным инстансом):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fake:blob=fake_default_tls:tcp_ack=-66000:tcp_ts_up:tls_mod=rnd,rndsni,dupsid \
    --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

---

## Практические примеры

### 1. Минимальный (с fooling)

```bash
--lua-desync=fakeddisorder:tcp_ack=-66000:tcp_ts_up
```

Разрезает payload после 1-го байта (pos=2 по умолчанию) с badseq fooling для фейков. 6 пакетов.

### 2. TLS: разрез посередине SNI

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

SNI разрезан пополам. DPI видит 6 пакетов с перемешанными фейковыми и реальными сегментами в обратном порядке — двойное запутывание.

### 3. TLS: разрез + seqovl (тройное запутывание)

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:seqovl=5:seqovl_pattern=0x1603030000:tcp_ack=-66000:tcp_ts_up
```

Три уровня: фейки + disorder + seqovl. Real part 2 имеет 4-байтовый TLS-фейк слева (5→resolve→5, 5-1=4), который DPI может принять за начало TLS record.

### 4. TLS: seqovl как маркер

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:seqovl=sld:tcp_ack=-66000:tcp_ts_up
```

seqovl разрешается в позицию начала SLD. Фейковая часть слева от real part 2 — от начала SLD до позиции разреза.

### 5. HTTP: разрез в начале hostname

```bash
--payload=http_req --lua-desync=fakeddisorder:pos=host:tcp_ack=-66000:tcp_ts_up
```

Для `GET / HTTP/1.1\r\nHost: example.com\r\n...` разрежет так, что часть 1 содержит заголовки до hostname, а часть 2 — hostname и далее.

### 6. HTTP: кастомный паттерн для фейков

```bash
--payload=http_req --lua-desync=fakeddisorder:pos=host:pattern=0x474554202F20485454502F312E310D0A:tcp_ack=-66000:tcp_ts_up
```

Фейки заполняются паттерном, похожим на начало HTTP-запроса (`GET / HTTP/1.1\r\n`). DPI может принять фейк за реальный запрос к другому хосту.

### 7. С tcp_md5 fooling

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_md5:tcp_ts_up
```

Вместо badseq используется TCP MD5 signature option. Сервер отбрасывает пакеты с неверной MD5 подписью.

### 8. С badsum reconstruct

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:badsum
```

Фейки отправляются с испорченным TCP checksum. Двойная защита: и badseq, и badsum.

### 9. Без первого и последнего фейка (4 пакета)

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:nofake1:nofake4
```

Отключены фейки "снаружи" (первый и последний). Остаётся: real part 2, fake part 2 (после), fake part 1 (перед), real part 1. 4 пакета.

### 10. Только внутренние фейки (4 пакета)

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:nofake1:nofake2
```

Вся часть 2 — только реальная (без обрамления фейками). Часть 1 — с фейками. Полезно, когда DPI анализирует только начало потока.

### 11. Без всех фейков (эквивалент disorder)

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:nofake1:nofake2:nofake3:nofake4
```

Отключены все 4 фейка. Остаются только 2 реальных пакета в обратном порядке. Фактически — [[multidisorder]] с одной позицией. Fooling не нужен (применяется только к фейкам, которых нет).

### 12. Цепочка: fake + fakeddisorder

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:repeats=5:tcp_md5 \
  --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

Сначала 5 фейковых TLS ClientHello (с md5sig fooling), затем fakeddisorder с 6 пакетами. Итого 11 пакетов. Массированная атака на DPI.

### 13. С произвольным blob вместо payload

```bash
--blob=mydata:@custom_payload.bin \
--lua-desync=fakeddisorder:blob=mydata:pos=50:tcp_ack=-66000:tcp_ts_up
```

Режет и отправляет произвольные данные из файла вместо реального payload.

### 14. С optional для необязательного blob

```bash
--lua-desync=fakeddisorder:blob=maybe_missing:optional:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

Если blob `maybe_missing` не существует — тихий пропуск, без ошибок.

### 15. Боевой пример для YouTube

```bash
--filter-tcp=443 --hostlist=youtube.txt \
  --payload=tls_client_hello \
    --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up
```

Разрезает TLS ClientHello посередине SNI домена YouTube с фейками в обратном порядке.

### 16. Комбинация fooling + repeats для фейков

```bash
--payload=tls_client_hello \
  --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:repeats=3
```

Каждый из 4 фейковых пакетов отправляется 3 раза. Реальные — по 1 разу. Итого 14 пакетов (4*3 + 2).

### 17. IPv6: hop-by-hop fooling

```bash
--payload=tls_client_hello \
  --lua-desync=fakeddisorder:pos=midsld:ip6_hopbyhop:tcp_ts_up
```

Для IPv6: фейки отправляются с extension header hop-by-hop, который сбрасывается на первом маршрутизаторе. Реальные сегменты — без hop-by-hop.

### 18. Отладка: не блокировать оригинал

```bash
--payload=tls_client_hello --lua-desync=fakeddisorder:pos=midsld:tcp_ack=-66000:tcp_ts_up:nodrop
```

Отправляет 6 нарезанных пакетов И пропускает оригинальный (для экспериментов/отладки).

---

> **Источники:** `lua/zapret-antidpi.lua:908-1021`, `docs/manual.md:4165-4206`, `docs/manual.en.md:3984-4025` из репозитория zapret2.

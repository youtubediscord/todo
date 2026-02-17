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
  - multisplit
  - seqovl
aliases:
  - multisplit
---

# `multisplit` — последовательная TCP-сегментация (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:471`
**nfqws1 эквивалент:** `--dpi-desync=multisplit`
**Сигнатура:** `function multisplit(ctx, desync)`

`multisplit` — базовая функция TCP-сегментации в zapret2. Она берёт текущий payload (или reasm, или blob), разрезает его на несколько TCP-сегментов по заданным позициям и отправляет их **последовательно** (от первого к последнему). После успешной отправки выносит `VERDICT_DROP`, чтобы оригинальный пакет не ушёл.

Родственные функции: [[multidisorder]] (обратный порядок), [[fakedsplit]] (с фейками), [[fakeddisorder]] (фейки + обратный порядок), [[hostfakesplit]] (по hostname), [[tcpseg]] (диапазон), [[oob]] (urgent byte).

---

## Оглавление

- [Зачем нужен multisplit](#зачем-нужен-multisplit)
- [Быстрый старт](#быстрый-старт)
- [Откуда берутся данные для нарезки](#откуда-берутся-данные-для-нарезки)
- [Маркеры позиций (pos)](#маркеры-позиций-pos)
  - [Типы маркеров](#типы-маркеров)
  - [Относительные маркеры](#относительные-маркеры)
  - [Арифметика маркеров](#арифметика-маркеров)
  - [Как маркеры разрешаются в коде](#как-маркеры-разрешаются-в-коде)
  - [Важные нюансы pos](#важные-нюансы-pos)
- [seqovl — скрытый фейк внутри сегмента](#seqovl--скрытый-фейк-внутри-сегмента)
  - [Принцип работы seqovl](#принцип-работы-seqovl)
  - [Зачем seqovl лучше обычного fooling](#зачем-seqovl-лучше-обычного-fooling)
  - [seqovl_pattern](#seqovl_pattern)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы multisplit](#a-собственные-аргументы-multisplit)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard ipfrag](#f-standard-ipfrag)
  - [G) Standard reconstruct](#g-standard-reconstruct)
  - [H) Standard rawsend](#h-standard-rawsend)
- [Порядок отправки сегментов](#порядок-отправки-сегментов)
- [Поведение при replay / reasm](#поведение-при-replay--reasm)
- [Автосегментация по MSS](#автосегментация-по-mss)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Отличия от других функций сегментации](#отличия-от-других-функций-сегментации)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен multisplit

DPI анализирует TCP-поток, пытаясь собрать полный payload и найти в нём сигнатуры (hostname в HTTP, SNI в TLS). Если мы разрежем пакет на несколько TCP-сегментов, DPI может:

1. **Не собрать данные:** некоторые DPI работают попакетно и не реассемблируют TCP
2. **Не найти сигнатуру:** если разрез проходит через `Host:` или SNI, ни в одном отдельном сегменте полного hostname нет
3. **Принять фейк за реальные данные:** с помощью `seqovl` можно замешать ложную информацию, которую DPI проглотит, а сервер — нет

Сервер при этом корректно собирает поток — TCP-стек гарантирует это через sequence numbers.

**multisplit** — самый простой вариант: режем и шлём **по порядку**. Для обратного порядка есть [[multidisorder]], для замешивания фейковых сегментов — [[fakedsplit]]/[[fakeddisorder]].

---

## Быстрый старт

Минимально (разрез по позиции 2, payload=known, dir=out):

```bash
--lua-desync=multisplit
```

Типовой TLS-разрез:

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld
```

TLS с seqovl:

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=5:seqovl_pattern=0x1603030000
```

HTTP с разрезом по hostname:

```bash
--payload=http_req --lua-desync=multisplit:pos=host,midsld,endhost
```

---

## Откуда берутся данные для нарезки

Внутри `multisplit` данные (`data`) выбираются в следующем порядке приоритетов:

```
1. blob_or_def(desync, desync.arg.blob)    — если задан blob= и он существует
2. desync.reasm_data                        — если есть реассемблированные данные (multi-packet payload)
3. desync.dis.payload                       — текущий пакет (fallback)
```

**Следствие:** все маркеры `pos`, `seqovl` и прочие аргументы применяются именно к тем данным, которые реально выбраны. Если вы задали `blob=myblob`, маркеры вроде `midsld` будут работать только если `myblob` содержит валидный TLS/HTTP payload, который zapret может распознать.

---

## Маркеры позиций (pos)

`pos` — главный аргумент `multisplit`. Определяет **где** внутри payload будет произведён разрез. Задаётся как строка со списком маркеров через запятую.

### Типы маркеров

| Тип | Описание | Пример |
|:----|:---------|:-------|
| **Абсолютный положительный** | Смещение от начала payload. В Lua позиции начинаются с 1 | `1`, `5`, `100` |
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

Арифметика работает и с абсолютными маркерами, хотя это избыточно (`5+3` = `8`).

### Пример списка маркеров

```
pos=100,midsld,sniext+1,endhost-2,-10
```

Здесь 5 маркеров → payload разрежется максимум на 6 частей (если все маркеры успешно разрешатся и дадут различные позиции).

### Как маркеры разрешаются в коде

Внутри `multisplit` вызывается:

```lua
local pos = resolve_multi_pos(data, desync.l7payload, spos)
```

Функция `resolve_multi_pos`:

1. Разбивает строку `spos` по запятым
2. Для каждого маркера вызывает `resolve_pos(blob, l7payload_type, marker)`
3. Если маркер не может быть разрешён (например, `midsld` для `unknown` payload) — он **молча пропускается**
4. Результаты дедуплицируются и сортируются
5. Возвращается массив **уникальных** абсолютных позиций (1-based, как в Lua)

Затем вызывается:

```lua
delete_pos_1(pos)  -- удалить позицию 1 (нельзя разрезать на самом первом байте)
```

### Важные нюансы pos

- **Нельзя разрезать по позиции 1** (первый байт). Позиция 1 автоматически удаляется из списка. Это означает, что `pos=1` по факту не создаст разреза — вместо этого данные отправятся целиком. Для разреза "после 1-го байта" используйте `pos=2` (это дефолт)
- **Дублирующиеся позиции объединяются.** `pos=5,5,5` = `pos=5`
- **Неразрешимые маркеры пропускаются.** Если `midsld` не разрешается (payload = unknown), он просто исчезает из списка. Если все маркеры не разрешились — multisplit ничего не делает (логирует "no valid split positions")
- **Позиции сортируются.** Независимо от порядка записи, `pos=100,5,50` будет обработано как `5,50,100`
- **По умолчанию pos="2".** Если `pos` не задан, разрез по позиции 2 → payload делится на 2 части: 1-й байт отдельно, остальное отдельно

---

## seqovl — скрытый фейк внутри сегмента

**seqovl** (Sequence Overlap) — техника скрытого замешивания фейковых данных в реальный TCP-сегмент через манипуляцию TCP sequence number. В `multisplit` seqovl применяется **только к первому** отправляемому сегменту.

### Принцип работы seqovl

```
Без seqovl:
  TCP seq: 1000
  Данные:  [РЕАЛЬНАЯ_ЧАСТЬ_1]
  Сервер:  принимает [РЕАЛЬНАЯ_ЧАСТЬ_1] целиком

С seqovl=10:
  TCP seq: 990             (уменьшен на 10)
  Данные:  [PATTERN_10_БАЙТ][РЕАЛЬНАЯ_ЧАСТЬ_1]

  Что видит DPI:
    Единый TCP-сегмент начиная с seq 990.
    DPI анализирует весь блок, включая PATTERN.
    Если PATTERN содержит ложный SNI — DPI может принять его за настоящий.

  Что видит сервер (TCP-стек):
    TCP window начинается с seq 1000.
    Байты 990-999 выходят за левую границу window → отбрасываются.
    Байты с 1000 (РЕАЛЬНАЯ_ЧАСТЬ_1) → принимаются.
```

**Визуализация:**

```
           TCP window boundary
                 ↓
  |  ОТБРОСИТЬ  | ПРИНЯТЬ          |
  | PATTERN(10) | РЕАЛЬНАЯ_ЧАСТЬ_1 |
  ^seq=990       ^seq=1000
```

### Зачем seqovl лучше обычного fooling

| Критерий | Обычный fooling (TTL, badseq, md5sig) | seqovl |
|:---------|:---------------------------------------|:-------|
| Заголовки | Модифицируются (TTL, seq, ack, md5) | **Не модифицируются** — пакет выглядит полностью легитимным |
| Обнаружение | DPI может детектировать подозрительные заголовки | DPI видит "честный" сегмент с правильными заголовками |
| Механизм отбрасывания | Сервер отбрасывает весь пакет из-за невалидных заголовков | Сервер отбрасывает только часть, выходящую за TCP window |
| Надёжность | Зависит от поведения конкретного стека | Основан на фундаментальном свойстве TCP |

**Вывод:** seqovl — средство создания скрытых фейков, не требующее fooling. Это его ключевое преимущество.

### seqovl_pattern

Паттерн, которым заполняется seqovl-область (N байт слева от реальных данных). По умолчанию — `0x00` (нули).

В `multisplit` `seqovl_pattern` — это **имя blob**. Паттерн повторяется до нужной длины `seqovl`.

```bash
# Inline hex blob (маскировка под начало TLS record)
--lua-desync=multisplit:pos=1:seqovl=5:seqovl_pattern=0x1603030000

# Предзагруженный blob
--blob=tlspat:0x1603030100 \
--lua-desync=multisplit:pos=1:seqovl=8:seqovl_pattern=tlspat
```

Если `optional` задан и blob `seqovl_pattern` отсутствует — используется нулевой паттерн (операция не отменяется).

**Важно в multisplit:** `seqovl` — только **число**, маркеры не поддерживаются (в отличие от `multidisorder` и `fakeddisorder`, где seqovl может быть маркером).

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=multisplit[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`, `:nodrop`, `:tcp_ts_up`.

### A) Собственные аргументы multisplit

#### `pos`

- **Формат:** `pos=<marker[,marker2,...]>`
- **Тип:** строка со списком маркеров через запятую
- **По умолчанию:** `"2"`
- **Описание:** Точки разреза. Каждый маркер определяет позицию, по которой payload будет разрезан. N маркеров → до N+1 сегментов
- **Примеры:**
  - `pos=2` — разрез после 1-го байта (дефолт)
  - `pos=midsld` — разрез посередине SLD
  - `pos=1,midsld` — два разреза: после 1-го байта и посередине SLD → 3 сегмента
  - `pos=host,midsld,endhost-2,-10` — четыре разреза → до 5 сегментов
  - `pos=method+2` — после первых 2 символов HTTP-метода

#### `seqovl`

- **Формат:** `seqovl=N` (где N > 0)
- **Тип:** только число (маркеры **не поддерживаются** — в отличие от multidisorder)
- **По умолчанию:** не задан (нет seqovl)
- **Описание:** Применяется **только к первому** отправляемому сегменту. К данным первого сегмента слева добавляется N байт `seqovl_pattern`, а TCP `th_seq` уменьшается на N. Сервер отбросит левую часть, DPI — может не отбросить
- **Примеры:**
  - `seqovl=5` — 5 байт фейка слева
  - `seqovl=13` — 13 байт фейка слева
  - `seqovl=10000` — 10000 байт (если превысит MSS — автосегментация разобьёт на несколько TCP-сегментов)

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
  - Если задан `blob=...` и blob отсутствует → multisplit **ничего не делает** (тихий skip, без ошибок)
  - Если задан `seqovl_pattern=...` и blob отсутствует → используется нулевой паттерн (seqovl не отменяется)
- **Использование:** защита от ошибок при использовании blob, которые могут отсутствовать (например, если blob генерируется другой функцией)

#### `nodrop`

- **Формат:** `nodrop` (флаг, без значения)
- **Описание:** После успешной отправки сегментов **не выносить** `VERDICT_DROP` (вместо этого вернуть `VERDICT_PASS`). Это означает, что оригинальный пакет тоже будет отправлен (наряду с нарезанными сегментами)
- **Использование:** для отладки, для отправки произвольных данных без блокировки оригинала
- **Предупреждение:** в боевых профилях `nodrop` обычно нежелателен — оригинал ещё раз уйдёт, что создаст дублирование и может ухудшить обход

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `multisplit` по умолчанию работает только с исходящими (`out`).

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

Модификации L3/L4 заголовков. В `multisplit` применяются **ко всем** отправляемым сегментам (в отличие от fakedsplit, где fooling идёт только на фейки).

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

**Заметка про tcp_ts_up:** На Linux-серверах пакеты с инвалидным ACK стабильно отбрасываются **только если** TCP timestamp option идёт первой в заголовке. `tcp_ts_up` перемещает её в начало, обеспечивая корректную работу badseq-fooling.

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | — |
| `ip_id=zero` | Нулевые IP ID | — |
| `ip_id=none` | Не менять IP ID | — |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения (требует tracking) | — |

`ip_id` применяется к **каждому** отправляемому сегменту (включая под-сегменты при MSS-сегментации).

---

### F) Standard ipfrag

IP-фрагментация **поверх** TCP-сегментации. Каждый TCP-сегмент дополнительно фрагментируется на уровне IP.

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ipfrag[=func]` | Включить IP-фрагментацию. Если без значения → `ipfrag2` | — |
| `ipfrag_disorder` | Отправить IP-фрагменты в обратном порядке | — |
| `ipfrag_pos_tcp=N` | Позиция фрагментации TCP (кратно 8) | `32` |
| `ipfrag_pos_udp=N` | Позиция фрагментации UDP (кратно 8). Для multisplit бесполезно — он только TCP | `8` |
| `ipfrag_next=N` | IPv6: next protocol во 2-м фрагменте (penetration атака на фаерволы) | — |

---

### G) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета. Сервер отбросит такой пакет |

---

### H) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить каждый сегмент N раз (идентичные повторы) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

---

## Порядок отправки сегментов

`multisplit` всегда отправляет сегменты **последовательно** — от первого к последнему (в порядке возрастания TCP sequence).

### Пример с 3 позициями разреза

```
Payload (600 байт):
[AAA...100 байт...AAA][BBB...200 байт...BBB][CCC...150 байт...CCC][DDD...150 байт...DDD]
                      ^pos=100               ^pos=300               ^pos=450

Отправка:
  Сегмент 1: [AAA...100] seq=0          len=100
  Сегмент 2: [BBB...200] seq=100        len=200
  Сегмент 3: [CCC...150] seq=300        len=150
  Сегмент 4: [DDD...150] seq=450        len=150
```

### Пример с seqovl=10

```
Payload (600 байт), pos=100, seqovl=10:

  Сегмент 1: [PATTERN(10)][AAA...100] seq=-10    len=110  (сервер отбросит PATTERN)
  Сегмент 2: [BBB...500]              seq=100    len=500
```

---

## Поведение при replay / reasm

При многопакетных payload (например, большой TLS ClientHello с post-quantum Kyber, который не влезает в один TCP-сегмент) zapret собирает все части в `reasm_data`. При перепроигрывании (replay):

1. **Первая часть replay:** multisplit берёт **весь** `reasm_data`, нарезает и отправляет. Устанавливает флаг `replay_drop_set`
2. **Все последующие части replay:** multisplit видит, что отправка уже произошла, и выносит `VERDICT_DROP` (если не `nodrop`) — потому что весь reasm уже отправлен нарезанным, нет смысла отправлять оригинальные части

**Исключение:** если первая отправка неуспешна (rawsend вернул false), флаг не устанавливается и последующие части проходят как есть.

---

## Автосегментация по MSS

О размерах TCP-сегментов думать **не нужно**. Функция `rawsend_payload_segmented` из `zapret-lib.lua` автоматически:

1. Отслеживает MSS для каждого TCP-соединения
2. Если часть payload превышает MSS — дополнительно режет по MSS
3. Каждый под-сегмент отправляется с корректным TCP sequence

**Пример:** если вы задали `seqovl=10000`, это не вызовет ошибку. `rawsend_payload_segmented` отправит несколько TCP-сегментов с начальным sequence -10000, общим размером 10000 байт seqovl-pattern, и в последнем сегменте — начало реальных данных.

---

## Псевдокод алгоритма

```lua
function multisplit(ctx, desync)
    -- 1. Проверка: только TCP
    if not desync.dis.tcp then cutoff; return end

    -- 2. Cutoff противоположного направления
    direction_cutoff_opposite(ctx, desync)

    -- 3. Проверка optional blob
    if optional and blob specified and blob not exists then return end

    -- 4. Выбор данных
    data = blob_or_def(blob) or reasm_data or dis.payload

    -- 5. Проверки: данные не пусты, направление OK, payload OK
    if #data > 0 and direction_check() and payload_check() then

        -- 6. Только первый replay
        if replay_first() then

            -- 7. Разрешение маркеров
            pos = resolve_multi_pos(data, l7payload, pos_arg or "2")
            delete_pos_1(pos)  -- нельзя резать по позиции 1

            if #pos > 0 then
                -- 8. Цикл по частям (i=0 до #pos)
                for i = 0, #pos do
                    pos_start = pos[i] or 1
                    pos_end   = (i < #pos) and pos[i+1]-1 or #data
                    part      = data:sub(pos_start, pos_end)

                    -- 9. seqovl для первого сегмента
                    seqovl = 0
                    if i == 0 and arg.seqovl > 0 then
                        seqovl = tonumber(arg.seqovl)
                        pat = seqovl_pattern_blob or "\x00"
                        part = pattern(pat, 1, seqovl) .. part
                    end

                    -- 10. Отправка с автосегментацией
                    rawsend_payload_segmented(part, pos_start - 1 - seqovl)
                end

                -- 11. Пометить как отправленное
                replay_drop_set()
                return nodrop and VERDICT_PASS or VERDICT_DROP
            end
        else
            -- 12. Не первый replay — дропнуть если ранее успешно отправлено
            if replay_drop() then
                return nodrop and VERDICT_PASS or VERDICT_DROP
            end
        end
    end
end
```

---

## Нюансы и подводные камни

### 1. Работает только с TCP

Если текущий пакет не TCP (UDP, ICMP и т.д.), `multisplit` делает `instance_cutoff` — отключает себя для этого потока навсегда.

### 2. Позиция 1 удаляется

`delete_pos_1(pos)` убирает позицию 1 из списка. Если после этого не осталось ни одной позиции — multisplit ничего не делает. Это значит, что `pos=1` **бесполезна** как единственная позиция.

### 3. Все маркеры могут не разрешиться

Если вы указали `pos=midsld,sniext` для HTTP-payload, оба маркера (специфичные для TLS) не разрешатся. Multisplit напишет в лог "no valid split positions" и ничего не сделает.

### 4. nodrop создаёт дублирование

С `nodrop` multisplit отправляет нарезанные сегменты И пропускает оригинальный пакет. Сервер получит данные дважды. Используйте `nodrop` только для отладки или когда это осознанно нужно.

### 5. seqovl=10000 не вызовет ошибку

В отличие от nfqws1, где большие значения seqovl вызывали ошибку, nfqws2 автоматически сегментирует по MSS. Большой seqovl просто создаст много под-сегментов.

### 6. Fooling применяется ко ВСЕМ сегментам

В отличие от `fakedsplit`/`fakeddisorder`, где fooling идёт только на фейки, в `multisplit` все сегменты получают fooling. Если задать `tcp_ack=-66000`, **все** сегменты получат инвалидный ack — сервер их отбросит, и ничего не заработает. Fooling в multisplit имеет смысл только для специфических вещей (например, `tcp_ts_up`, `ip_id`, IPv6 extension headers).

### 7. Порядок инстансов важен

Если перед `multisplit` стоит `pktmod` с fooling — fooling применится к диссекту, и multisplit порежет уже модифицированный пакет. Если после multisplit стоит ещё один инстанс — он увидит VERDICT_DROP и не получит оригинальный payload.

---

## Отличия от других функций сегментации

| Аспект | `multisplit` | `multidisorder` | `fakedsplit` | `fakeddisorder` |
|:-------|:-------------|:----------------|:-------------|:----------------|
| Количество позиций | Список (любое кол-во) | Список (любое кол-во) | **Одна** | **Одна** |
| Порядок отправки | Прямой (1→2→3) | Обратный (3→2→1) | Прямой | Обратный |
| Фейковые сегменты | **Нет** | **Нет** | Да (до 4 шт.) | Да (до 4 шт.) |
| seqovl тип | Только число | **Маркер** | Только число | **Маркер** |
| seqovl к какому сегменту | 1-й | 2-й (предпоследний) | 1-й реальный | 2-й реальный |
| Fooling к | Всем сегментам | Всем сегментам | Только к фейкам | Только к фейкам |
| ipfrag | Да | Да | **Нет** | **Нет** |

---

## Миграция с nfqws1

### Соответствие параметров

| nfqws1 | nfqws2 |
|:-------|:-------|
| `--dpi-desync=multisplit` | `--lua-desync=multisplit` |
| `--dpi-desync-split-pos=midsld` | `:pos=midsld` |
| `--dpi-desync-split-pos=1,midsld` | `:pos=1,midsld` |
| `--dpi-desync-split-seqovl=5` | `:seqovl=5` |
| `--dpi-desync-split-seqovl-pattern=0x1603030000` | `:seqovl_pattern=0x1603030000` |
| `--dpi-desync-any-protocol` | Не нужно; или `payload=all` в инстансе |

### Пример полной миграции

```bash
# nfqws1:
nfqws --dpi-desync=fake,multisplit \
  --dpi-desync-fooling=md5sig \
  --dpi-desync-split-pos=1,midsld \
  --dpi-desync-split-seqovl=5 \
  --dpi-desync-split-seqovl-pattern=0x1603030000 \
  --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid

# nfqws2 (эквивалент):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --payload=http_req \
    --lua-desync=fake:blob=fake_default_http:tcp_md5 \
  --payload=tls_client_hello,http_req \
    --lua-desync=multisplit:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

```bash
# nfqws1:
nfqws --dpi-desync=syndata,multisplit --dpi-desync-split-pos=midsld --wssize 1:6

# nfqws2 (порядок инстансов важен!):
nfqws2 \
  --lua-desync=wssize:wsize=1:scale=6 \
  --lua-desync=syndata \
  --lua-desync=multisplit:pos=midsld
```

---

## Практические примеры

### Минимальный (дефолт: pos=2, dir=out, payload=known)

```bash
--lua-desync=multisplit
```

Разрезает payload после 1-го байта → 2 сегмента.

### HTTP: разрез после метода

```bash
--payload=http_req --lua-desync=multisplit:pos=method+2
```

Для `GET /path...` разрежет после `GE` → DPI не увидит полный метод.

### HTTP: несколько разрезов вокруг hostname

```bash
--payload=http_req --lua-desync=multisplit:pos=host,midsld,endhost
```

Разрезает: до hostname | первая половина | вторая половина | после hostname → 4 сегмента.

### TLS: разрез посередине SNI

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=midsld
```

SNI разрезан пополам — ни в одном сегменте нет полного домена.

### TLS: два разреза + seqovl

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

3 сегмента: первый с 5-байтовым TLS-фейком слева (DPI может принять за начало TLS record).

### Произвольный blob вместо payload

```bash
--blob=mydata:@custom_payload.bin \
--lua-desync=multisplit:blob=mydata:pos=10,100,-20
```

Режет и отправляет произвольные данные из файла вместо реального payload.

### Защита от отсутствующего blob

```bash
--lua-desync=multisplit:blob=maybe_missing:optional:pos=2
```

Если blob не существует — тихий пропуск, без ошибок и без VERDICT_DROP.

### Отладка: не блокировать оригинал

```bash
--payload=http_req --lua-desync=multisplit:pos=method+2:nodrop
```

Отправляет нарезанные сегменты И пропускает оригинальный пакет (для экспериментов).

### С TCP timestamp + IP ID

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:tcp_ts_up:ip_id=seq:ip_id_conn
```

### Повторы отправки

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:repeats=2
```

Каждый сегмент отправляется 2 раза (бинарные повторы).

### IP-фрагментация поверх TCP-сегментации

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1,midsld:ipfrag:ipfrag_disorder:ipfrag_pos_tcp=32
```

Каждый TCP-сегмент дополнительно фрагментируется на IP-уровне в обратном порядке.

### Комбинация: fake → multisplit

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --lua-desync=multisplit:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

Сначала отправляется фейковый TLS ClientHello (с fooling), затем реальный — нарезанный на 3 сегмента с seqovl.

### Боевой пример для YouTube

```bash
--filter-tcp=443 --hostlist=youtube.txt \
  --lua-desync=fake:blob=fake_default_tls:repeats=11:tcp_md5 \
  --lua-desync=multisplit:pos=1,midsld
```

11 фейков подряд + реальный payload разрезан на 3 части.

---

> **Источники:** `lua/zapret-antidpi.lua:471-527`, `lua/zapret-lib.lua`, `docs/manual.md:4031-4066`, `docs/readme.md` из репозитория zapret2.

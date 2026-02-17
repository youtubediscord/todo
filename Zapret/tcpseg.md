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
  - tcpseg
  - seqovl
aliases:
  - tcpseg
---

# `tcpseg` -- отправка TCP-сегмента из диапазона (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:1030`
**nfqws1 эквивалент:** отсутствует (NEW функция в nfqws2)
**Сигнатура:** `function tcpseg(ctx, desync)`

`tcpseg` -- функция отправки **части** текущего payload (или reasm, или blob), ограниченной **двумя** маркерами позиций (диапазоном), в виде TCP-сегмента. В отличие от [[multisplit]], которая разрезает весь payload на множество сегментов по списку позиций, `tcpseg` вырезает и отправляет **один** конкретный диапазон данных. При этом `tcpseg` **не выносит вердикт** (ни `VERDICT_DROP`, ни `VERDICT_PASS`) -- для замещения оригинального пакета необходимо комбинировать с функцией `drop`.

Родственные функции: [[multisplit]] (множественная сегментация), [[multidisorder]] (обратный порядок), [[fakedsplit]] (с фейками), [[fakeddisorder]] (фейки + обратный порядок), [[hostfakesplit]] (по hostname), [[oob]] (urgent byte).

---

## Оглавление

- [Зачем нужен tcpseg](#зачем-нужен-tcpseg)
- [Быстрый старт](#быстрый-старт)
- [Откуда берутся данные](#откуда-берутся-данные)
- [Маркеры позиций (pos) -- диапазон из двух маркеров](#маркеры-позиций-pos--диапазон-из-двух-маркеров)
  - [Отличие от multisplit: resolve_range vs resolve_multi_pos](#отличие-от-multisplit-resolve_range-vs-resolve_multi_pos)
  - [Типы маркеров](#типы-маркеров)
  - [Относительные маркеры](#относительные-маркеры)
  - [Арифметика маркеров](#арифметика-маркеров)
  - [Поведение resolve_range при неразрешённых маркерах](#поведение-resolve_range-при-неразрешённых-маркерах)
  - [Важные нюансы pos](#важные-нюансы-pos)
- [seqovl -- скрытый фейк внутри сегмента](#seqovl--скрытый-фейк-внутри-сегмента)
  - [Принцип работы seqovl](#принцип-работы-seqovl)
  - [Зачем seqovl лучше обычного fooling](#зачем-seqovl-лучше-обычного-fooling)
  - [seqovl_pattern](#seqovl_pattern)
- [Вердикт и комбинация с drop](#вердикт-и-комбинация-с-drop)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы tcpseg](#a-собственные-аргументы-tcpseg)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard ipfrag](#f-standard-ipfrag)
  - [G) Standard reconstruct](#g-standard-reconstruct)
  - [H) Standard rawsend](#h-standard-rawsend)
- [Порядок отправки](#порядок-отправки)
- [Поведение при replay / reasm](#поведение-при-replay--reasm)
- [Автосегментация по MSS](#автосегментация-по-mss)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Отличия от других функций сегментации](#отличия-от-других-функций-сегментации)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен tcpseg

`tcpseg` решает задачу, которую не решает [[multisplit]]: отправить **конкретный фрагмент** payload (или весь payload целиком) как отдельный TCP-сегмент, с опциональным seqovl, **без автоматического вынесения вердикта**.

Основные сценарии использования:

1. **seqovl без сегментации.** Отправить весь payload целиком с seqovl-префиксом, подменяющим начало потока для DPI. Маркеры `pos=0,-1` задают диапазон "от начала до конца" -- весь payload
2. **Повторная отправка начала потока.** Отправить первые N байт payload многократно (`repeats=N`), чтобы забить буфер DPI мусором. Маркеры `pos=0,method+2` или `pos=0,midsld` отправляют только начало
3. **Модульная композиция.** Поскольку `tcpseg` не выносит вердикт, его можно комбинировать с другими инстансами (например, `drop`, `luaexec`) в цепочке

**Ключевое отличие от multisplit:** [[multisplit]] разрезает и отправляет **весь** payload, затем дропает оригинал. `tcpseg` отправляет **часть** (или весь) payload и **не** дропает оригинал -- нужна отдельная команда `drop`.

---

## Быстрый старт

Минимальный seqovl (весь payload + 1 байт нулевого seqovl, dir=out, payload=known):

```bash
--lua-desync=tcpseg:pos=0,-1:seqovl=1 --lua-desync=drop
```

seqovl с кастомным паттерном (TLS):

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=0,-1:seqovl=5:seqovl_pattern=0x1603030000 \
  --lua-desync=drop
```

Повторная отправка начала HTTP-запроса:

```bash
--payload=http_req --lua-desync=tcpseg:pos=0,method+2:ip_id=rnd:repeats=20
```

Динамический seqovl со случайным паттерном:

```bash
--lua-desync=luaexec:code='desync.rnd=brandom_az(math.random(5,10))' \
--lua-desync=tcpseg:pos=0,-1:seqovl=#rnd:seqovl_pattern=rnd \
--lua-desync=drop:payload=known
```

---

## Откуда берутся данные

Внутри `tcpseg` данные (`data`) выбираются в следующем порядке приоритетов:

```
1. blob_or_def(desync, desync.arg.blob)    -- если задан blob= и он существует
2. desync.reasm_data                        -- если есть реассемблированные данные (multi-packet payload)
3. desync.dis.payload                       -- текущий пакет (fallback)
```

**Следствие:** маркеры `pos` и `seqovl` применяются именно к тем данным, которые реально выбраны. Если вы задали `blob=myblob`, маркеры вроде `midsld` будут работать только если `myblob` содержит валидный TLS/HTTP payload, который zapret может распознать.

---

## Маркеры позиций (pos) -- диапазон из двух маркеров

`pos` -- **обязательный** аргумент `tcpseg`. Если `pos` не задан, функция вызовет `error("tcpseg: no pos specified")`. Это отличает `tcpseg` от [[multisplit]], где `pos` по умолчанию `"2"`.

Задаётся как строка с **ровно двумя** маркерами через запятую. Первый маркер -- начало диапазона, второй -- конец.

### Отличие от multisplit: resolve_range vs resolve_multi_pos

| Аспект | `tcpseg` | `multisplit` |
|:-------|:---------|:-------------|
| Функция разрешения | `resolve_range` (C-код) | `resolve_multi_pos` (C-код) |
| Количество маркеров | **Ровно 2** (ошибка, если не 2) | Любое количество |
| Семантика маркеров | Начало и конец **диапазона** | Точки **разреза** |
| Результат | Таблица из 2 позиций `{start, end}` или `nil` | Массив уникальных позиций |
| Что отправляется | `data:sub(pos[1], pos[2])` -- данные **между** маркерами | Весь payload, разрезанный по позициям |

### Типы маркеров

| Тип | Описание | Пример |
|:----|:---------|:-------|
| **Абсолютный положительный** | Смещение от начала payload. `0` = первый байт (в resolve_range используется zero-based нумерация на входе, но внутренне конвертируется в 1-based Lua) | `0`, `5`, `100` |
| **Абсолютный отрицательный** | Смещение от конца payload. `-1` = последний байт | `-1`, `-10`, `-50` |
| **Относительный** | Логическая позиция внутри распознанного payload. Привязана к структуре протокола | `midsld`, `host`, `sniext` |

### Относительные маркеры

| Маркер | Описание | Для каких payload |
|:-------|:---------|:------------------|
| `method` | Начало HTTP-метода (`GET`, `POST`, `HEAD`, `PUT` и т.д.). Обычно позиция 0, но может стать 1-2 при использовании `http_methodeol` | `http_req` |
| `host` | Первый байт имени хоста (`Host:` в HTTP, SNI в TLS) | `http_req`, `tls_client_hello` |
| `endhost` | Байт, **следующий** за последним байтом имени хоста. Т.е. `host..endhost-1` = полный hostname | `http_req`, `tls_client_hello` |
| `sld` | Первый байт домена второго уровня (SLD). Для `www.example.com` -- это `e` в `example` | `http_req`, `tls_client_hello` |
| `endsld` | Байт, следующий за последним байтом SLD. Для `example.com` -- это `.` после `example` | `http_req`, `tls_client_hello` |
| `midsld` | Середина SLD (самый популярный маркер). Для `example` (7 символов) -- позиция 3-го или 4-го символа | `http_req`, `tls_client_hello` |
| `sniext` | Начало поля данных SNI extension в TLS ClientHello. Extension состоит из type (2 байта) + length (2 байта) + **данные** -- sniext указывает на начало данных | `tls_client_hello` |
| `extlen` | Поле длины всех TLS extensions | `tls_client_hello` |

### Арифметика маркеров

К любому маркеру можно прибавить (+) или вычесть (-) целое число:

```
midsld+1      -- один байт ПОСЛЕ середины SLD
midsld-1      -- один байт ДО середины SLD
endhost-2     -- два байта до конца hostname
method+2      -- два байта после начала метода (для "GET /" -> диапазон 0..method+2 захватит "GE")
sniext+1      -- один байт после начала SNI extension data
host+3        -- три байта после начала hostname
0             -- начало payload
-1            -- последний байт payload
```

### Поведение resolve_range при неразрешённых маркерах

`resolve_range` реализована в C-коде (`nfq2/lua.c:3281`). Поведение при неразрешённых маркерах:

| Ситуация | Поведение (non-strict режим) |
|:---------|:-----------------------------|
| Оба маркера разрешены | Возвращает `{pos[0], pos[1]}` -- нормальный диапазон |
| Первый маркер не разрешён, второй разрешён | Первый маркер заменяется на `0` (начало данных) |
| Первый маркер разрешён, второй не разрешён | Второй маркер заменяется на `len-1` (конец данных) |
| Оба маркера не разрешены | Возвращает `nil` -- диапазон не может быть определён |
| `pos[0] > pos[1]` (начало после конца) | Возвращает `nil` -- невалидный диапазон |

**Важно:** `tcpseg` вызывает `resolve_range` **без** флага `strict`. Это означает, что если один из маркеров не разрешается, он расширяется до границы данных. Если нужна строгая логика -- используйте абсолютные маркеры.

### Важные нюансы pos

- **pos обязателен.** В отличие от [[multisplit]], где `pos` по умолчанию `"2"`, в `tcpseg` отсутствие `pos` вызывает `error()`. Это жёсткое требование
- **Ровно 2 маркера.** Если передать 1 или 3+ маркера, `resolve_range` вызовет `luaL_error("resolve_range require 2 markers")`
- **Маркер `0` -- начало данных.** В отличие от [[multisplit]], где позиция 1 удаляется (`delete_pos_1`), в `tcpseg` маркер `0` -- это валидное начало диапазона
- **Маркеры `0,-1` -- весь payload.** Самый частый паттерн: `pos=0,-1` означает "от начала до конца" -- весь payload целиком. Используется для seqovl без сегментации

---

## seqovl -- скрытый фейк внутри сегмента

**seqovl** (Sequence Overlap) -- техника скрытого замешивания фейковых данных в реальный TCP-сегмент через манипуляцию TCP sequence number. В `tcpseg` seqovl применяется к отправляемому сегменту (он всегда один).

### Принцип работы seqovl

```
Без seqovl (pos=0,-1):
  TCP seq: 1000
  Данные:  [ВЕСЬ_PAYLOAD]
  Сервер:  принимает [ВЕСЬ_PAYLOAD] целиком

С seqovl=10 (pos=0,-1):
  TCP seq: 990             (уменьшен на 10)
  Данные:  [PATTERN_10_БАЙТ][ВЕСЬ_PAYLOAD]

  Что видит DPI:
    Единый TCP-сегмент начиная с seq 990.
    DPI анализирует весь блок, включая PATTERN.
    Если PATTERN содержит ложный SNI -- DPI может принять его за настоящий.

  Что видит сервер (TCP-стек):
    TCP window начинается с seq 1000.
    Байты 990-999 выходят за левую границу window -> отбрасываются.
    Байты с 1000 (ВЕСЬ_PAYLOAD) -> принимаются.
```

**Визуализация:**

```
           TCP window boundary
                 |
  |  ОТБРОСИТЬ  | ПРИНЯТЬ             |
  | PATTERN(10) | ВЕСЬ_PAYLOAD        |
  ^seq=990       ^seq=1000
```

**Визуализация с pos=0,midsld (частичная отправка):**

```
  Payload: [====НАЧАЛО====|====midsld====|====КОНЕЦ====]
                           ^pos[1]

  Отправляется только [====НАЧАЛО====|====midsld====]
  (от начала до midsld включительно)

  С seqovl=5:
  TCP seq: -5 (относительно начала отправляемого куска)
  Данные:  [PAT 5][====НАЧАЛО====|====midsld====]
```

### Зачем seqovl лучше обычного fooling

| Критерий | Обычный fooling (TTL, badseq, md5sig) | seqovl |
|:---------|:---------------------------------------|:-------|
| Заголовки | Модифицируются (TTL, seq, ack, md5) | **Не модифицируются** -- пакет выглядит полностью легитимным |
| Обнаружение | DPI может детектировать подозрительные заголовки | DPI видит "честный" сегмент с правильными заголовками |
| Механизм отбрасывания | Сервер отбрасывает весь пакет из-за невалидных заголовков | Сервер отбрасывает только часть, выходящую за TCP window |
| Надёжность | Зависит от поведения конкретного стека | Основан на фундаментальном свойстве TCP |

**Вывод:** seqovl -- средство создания скрытых фейков, не требующее fooling. Это его ключевое преимущество. В `tcpseg` seqovl особенно силён в комбинации с `pos=0,-1`, где весь payload отправляется с фейковым префиксом.

### seqovl_pattern

Паттерн, которым заполняется seqovl-область (N байт слева от реальных данных). По умолчанию -- `0x00` (нули).

В `tcpseg` `seqovl_pattern` -- это **имя blob**. Паттерн повторяется до нужной длины `seqovl`.

```bash
# Inline hex blob (маскировка под начало TLS record)
--lua-desync=tcpseg:pos=0,-1:seqovl=5:seqovl_pattern=0x1603030000

# Предзагруженный blob
--blob=tlspat:0x1603030100 \
--lua-desync=tcpseg:pos=0,-1:seqovl=8:seqovl_pattern=tlspat

# Динамически сгенерированный blob через luaexec
--lua-desync=luaexec:code='desync.rnd=brandom_az(math.random(5,10))' \
--lua-desync=tcpseg:pos=0,-1:seqovl=#rnd:seqovl_pattern=rnd
```

Если `optional` задан и blob `seqovl_pattern` отсутствует -- используется нулевой паттерн (операция не отменяется).

**Важно в tcpseg:** `seqovl` -- только **число**, маркеры не поддерживаются (как и в [[multisplit]], в отличие от [[multidisorder]] и [[fakeddisorder]], где seqovl может быть маркером).

---

## Вердикт и комбинация с drop

**Ключевая особенность `tcpseg`:** функция **не выносит вердикт**. Она не возвращает ни `VERDICT_DROP`, ни `VERDICT_PASS`. Это означает:

1. После выполнения `tcpseg` оригинальный пакет **не блокируется**
2. Следующие инстансы в цепочке **продолжают обработку**
3. Если после `tcpseg` нет других инстансов -- оригинальный пакет уйдёт как есть

Для замещения оригинального пакета `tcpseg` нужно комбинировать с `drop`:

```bash
# tcpseg отправляет payload с seqovl, drop блокирует оригинал
--lua-desync=tcpseg:pos=0,-1:seqovl=5 --lua-desync=drop
```

**Нюанс с payload-фильтрами:** по умолчанию `tcpseg` работает только с `known` payload, а `drop` -- с `all`. Если вы хотите дропать только известные payload (чтобы неизвестные проходили без изменений), укажите:

```bash
--lua-desync=tcpseg:pos=0,-1:seqovl=5 --lua-desync=drop:payload=known
```

**Диаграмма прохождения пакета:**

```
Пакет приходит
    |
    v
[tcpseg] -- отправляет TCP-сегмент (часть payload с seqovl)
    |       НЕ выносит вердикт
    v
[drop]   -- выносит VERDICT_DROP, блокируя оригинальный пакет
    |
    v
Оригинальный пакет заблокирован.
Сервер получает только то, что отправил tcpseg.
```

**Без drop:**

```
Пакет приходит
    |
    v
[tcpseg] -- отправляет TCP-сегмент
    |       НЕ выносит вердикт
    v
Нет больше инстансов -> VERDICT_PASS (по умолчанию)
    |
    v
Оригинальный пакет тоже уходит!
Сервер получает данные ДВАЖДЫ (tcpseg + оригинал).
```

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=tcpseg[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`.

### A) Собственные аргументы tcpseg

#### `pos`

- **Формат:** `pos=<marker1,marker2>`
- **Тип:** строка с **ровно двумя** маркерами через запятую
- **По умолчанию:** нет (обязательный параметр; если не задан -- `error()`)
- **Описание:** Диапазон данных для отправки. Первый маркер -- начало, второй -- конец (включительно). Из данных вырезается `data:sub(pos[1], pos[2])` и отправляется как TCP-сегмент
- **Примеры:**
  - `pos=0,-1` -- весь payload (от начала до конца)
  - `pos=0,midsld` -- от начала до середины SLD
  - `pos=0,method+2` -- от начала до 2 байт после начала HTTP-метода
  - `pos=host,endhost` -- только hostname
  - `pos=0,1` -- только первый байт (для TLS: первый байт TLS record)
  - `pos=sniext,endhost` -- от начала SNI extension data до конца hostname

#### `seqovl`

- **Формат:** `seqovl=N` (где N > 0)
- **Тип:** только число (маркеры **не поддерживаются** -- как и в [[multisplit]])
- **По умолчанию:** не задан (нет seqovl)
- **Описание:** К данным сегмента слева добавляется N байт `seqovl_pattern`, а TCP `th_seq` уменьшается на N. Сервер отбросит левую часть, DPI -- может не отбросить
- **Примеры:**
  - `seqovl=1` -- 1 байт фейка слева (минимальный)
  - `seqovl=5` -- 5 байт фейка слева
  - `seqovl=#rnd` -- размер blob `rnd` (C-подстановка через `#`)
  - `seqovl=10000` -- 10000 байт (автосегментация по MSS разобьёт на несколько TCP-сегментов)

#### `seqovl_pattern`

- **Формат:** `seqovl_pattern=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** один байт `0x00`, повторяемый до длины `seqovl`
- **Описание:** Данные для заполнения seqovl-области. Blob повторяется функцией `pattern()` до нужного размера
- **Поведение с `optional`:** если `optional` задан и blob отсутствует -- используется нулевой паттерн, seqovl не отменяется
- **Примеры:**
  - `seqovl_pattern=0x1603030000` -- inline hex (маскировка под TLS)
  - `seqovl_pattern=rnd` -- динамически сгенерированный blob
  - `seqovl_pattern=fake_default_tls` -- стандартный TLS-фейк как паттерн

#### `blob`

- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** не задан
- **Описание:** Заменить текущий payload/reasm на указанный blob и отправить из него диапазон pos. Используется для отправки произвольных данных
- **Примеры:**
  - `blob=fake_default_tls` -- стандартный TLS-фейк
  - `blob=0xDEADBEEF` -- inline hex
  - `blob=my_custom_data` -- предзагруженный blob

#### `optional`

- **Формат:** `optional` (флаг, без значения)
- **Описание:** Мягкий режим:
  - Если задан `blob=...` и blob отсутствует -- tcpseg **ничего не делает** (тихий skip, без ошибок)
  - Если задан `seqovl_pattern=...` и blob отсутствует -- используется нулевой паттерн (seqovl не отменяется)
- **Использование:** защита от ошибок при использовании blob, которые могут отсутствовать (например, если blob генерируется другой функцией)

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `tcpseg` по умолчанию работает только с исходящими (`out`).

- `dir=out` -- только исходящие (от клиента к серверу)
- `dir=in` -- только входящие (от сервера к клиенту)
- `dir=any` -- оба направления

При первом вызове с указанным `dir` функция делает `direction_cutoff_opposite` -- отсекает себя от противоположного направления.

---

### C) Standard payload

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `payload` | список типов через запятую | `known` |

Фильтр по типу payload на уровне Lua. Это **дополнительный** фильтр к `--payload=...` на уровне профиля.

- `payload=known` -- только распознанные протоколы (`http_req`, `tls_client_hello`, `quic_initial` и т.д.)
- `payload=all` -- любой payload, включая `unknown`
- `payload=tls_client_hello,http_req` -- конкретные типы
- `payload=~unknown` -- инверсия: всё кроме unknown

**Важно:** лучше ставить `--payload=...` на уровне профиля (C-код, быстрее), а не полагаться только на Lua-фильтр.

---

### D) Standard fooling

Модификации L3/L4 заголовков. В `tcpseg` применяются к отправляемому сегменту.

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

**Предупреждение:** fooling в `tcpseg` применяется к **реальному** сегменту (не к фейку). Если задать `tcp_ack=-66000`, сервер отбросит сегмент. Fooling в tcpseg имеет смысл только для безопасных вещей: `tcp_ts_up`, `ip_id`, IPv6 extension headers.

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | -- |
| `ip_id=zero` | Нулевые IP ID | -- |
| `ip_id=none` | Не менять IP ID | -- |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения (требует tracking) | -- |

`ip_id` применяется к отправляемому сегменту (включая под-сегменты при MSS-сегментации).

---

### F) Standard ipfrag

IP-фрагментация **поверх** TCP-сегмента. Отправленный TCP-сегмент дополнительно фрагментируется на уровне IP.

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ipfrag[=func]` | Включить IP-фрагментацию. Если без значения -- `ipfrag2` | -- |
| `ipfrag_disorder` | Отправить IP-фрагменты в обратном порядке | -- |
| `ipfrag_pos_tcp=N` | Позиция фрагментации TCP (кратно 8) | `32` |
| `ipfrag_pos_udp=N` | Позиция фрагментации UDP (кратно 8). Для tcpseg бесполезно -- он только TCP | `8` |
| `ipfrag_next=N` | IPv6: next protocol во 2-м фрагменте (penetration атака на фаерволы) | -- |

---

### G) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета. Сервер отбросит такой пакет |

---

### H) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить сегмент N раз (идентичные повторы) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

---

## Порядок отправки

`tcpseg` отправляет **один** сегмент (диапазон данных между двумя маркерами), опционально с seqovl-префиксом.

### Пример без seqovl (pos=host,endhost)

```
Payload (600 байт):
[===ЗАГОЛОВКИ===][example.com][===ОСТАЛЬНОЕ===]
                 ^pos[1]=host  ^pos[2]=endhost

Отправляется:
  Сегмент: [example.com]  seq=host_offset  len=(endhost-host)

Оригинальный пакет: НЕ блокируется (нет вердикта)
```

### Пример с seqovl=10 (pos=0,-1)

```
Payload (600 байт), pos=0,-1, seqovl=10:

  Сегмент: [PATTERN(10)][ВЕСЬ_PAYLOAD_600_БАЙТ]
           seq=-10   len=610

  Сервер: отбросит первые 10 байт, примет 600
  DPI: проанализирует все 610 байт
```

### Пример с частичной отправкой и seqovl (pos=0,midsld, seqovl=5)

```
Payload: [====ДО_MIDSLD====][====ПОСЛЕ_MIDSLD====]
                             ^midsld

Отправляется:
  Сегмент: [PAT(5)][====ДО_MIDSLD====]
           seq=-5   len=(midsld+5)

Оригинальный пакет: НЕ блокируется (нужен drop)
```

---

## Поведение при replay / reasm

При многопакетных payload (например, большой TLS ClientHello с post-quantum Kyber, который не влезает в один TCP-сегмент) zapret собирает все части в `reasm_data`. При перепроигрывании (replay):

1. **Первая часть replay:** `tcpseg` берёт `reasm_data`, вырезает диапазон и отправляет. Функция `replay_first(desync)` возвращает `true`
2. **Все последующие части replay:** `tcpseg` логирует "not acting on further replay pieces" и **ничего не делает** -- просто возвращает `nil` (без вердикта)

**Важный нюанс:** поскольку `tcpseg` не выносит вердикт, на последующих частях replay оригинальные пакеты **пройдут без изменений**. Если `drop` стоит после `tcpseg` -- он заблокирует все пакеты (и первую часть, и последующие). Поэтому связка `tcpseg` + `drop` корректно обрабатывает reasm: tcpseg отправляет весь reasm при первой части, drop блокирует все оригинальные части.

---

## Автосегментация по MSS

О размерах TCP-сегментов думать **не нужно**. Функция `rawsend_payload_segmented` из `zapret-lib.lua` автоматически:

1. Отслеживает MSS для каждого TCP-соединения
2. Если отправляемая часть (включая seqovl) превышает MSS -- дополнительно режет по MSS
3. Каждый под-сегмент отправляется с корректным TCP sequence

**Пример:** если вы задали `pos=0,-1:seqovl=10000`, это не вызовет ошибку. `rawsend_payload_segmented` отправит несколько TCP-сегментов с начальным sequence -(10000), общим размером 10000 байт seqovl-pattern, и в последних сегментах -- реальные данные payload.

---

## Псевдокод алгоритма

```lua
function tcpseg(ctx, desync)
    -- 1. Проверка: только TCP
    if not desync.dis.tcp then
        if not desync.dis.icmp then instance_cutoff_shim(ctx, desync) end
        return   -- без вердикта
    end

    -- 2. Cutoff противоположного направления
    direction_cutoff_opposite(ctx, desync)

    -- 3. pos ОБЯЗАТЕЛЕН
    if not desync.arg.pos then
        error("tcpseg: no pos specified")
    end

    -- 4. Проверка optional blob
    if optional and blob specified and blob not exists then
        DLOG("tcpseg: blob not found. skipped")
        return   -- без вердикта, тихий skip
    end

    -- 5. Выбор данных
    data = blob_or_def(blob) or reasm_data or dis.payload

    -- 6. Проверки: данные не пусты, направление OK, payload OK
    if #data > 0 and direction_check() and payload_check() then

        -- 7. Только первый replay
        if replay_first(desync) then

            -- 8. Разрешение ДИАПАЗОНА (ровно 2 маркера)
            pos = resolve_range(data, l7payload, pos_arg)
            -- pos = {start, end} или nil

            if pos then
                -- 9. Вырезать диапазон
                part = data:sub(pos[1], pos[2])

                -- 10. seqovl
                seqovl = 0
                if arg.seqovl and tonumber(arg.seqovl) > 0 then
                    seqovl = tonumber(arg.seqovl)
                    pat = "\x00"
                    if arg.seqovl_pattern then
                        if optional and not blob_exist(seqovl_pattern) then
                            -- используем нулевой паттерн
                        else
                            pat = blob(seqovl_pattern)
                        end
                    end
                    part = pattern(pat, 1, seqovl) .. part
                end

                -- 11. Отправка с автосегментацией
                rawsend_payload_segmented(desync, part, pos[1]-1-seqovl)

            else
                DLOG("tcpseg: range cannot be resolved")
            end
        else
            -- 12. Не первый replay -- ничего не делаем
            DLOG("tcpseg: not acting on further replay pieces")
        end
    end

    -- 13. ВЕРДИКТ НЕ ВЫНОСИТСЯ -- return без значения
end
```

**Ключевые отличия от псевдокода [[multisplit]]:**
- Шаг 3: `error()` при отсутствии `pos` (в multisplit -- дефолт `"2"`)
- Шаг 8: `resolve_range` вместо `resolve_multi_pos` (2 маркера, не список)
- Шаг 9: `data:sub(pos[1], pos[2])` -- диапазон, не цикл по частям
- Шаг 11: одна отправка (не цикл)
- Шаг 13: **нет return VERDICT_DROP / VERDICT_PASS** -- нет `replay_drop_set()`, нет `nodrop`

---

## Нюансы и подводные камни

### 1. Работает только с TCP

Если текущий пакет не TCP (UDP, ICMP и т.д.), `tcpseg` делает `instance_cutoff_shim` -- отключает себя для этого потока навсегда. Исключение: связанные ICMP-пакеты (related icmp) не вызывают cutoff.

### 2. pos обязателен -- нет дефолта

В отличие от [[multisplit]] (дефолт `"2"`), `tcpseg` без `pos` вызовет `error()`. Всегда указывайте `pos`.

### 3. Ровно 2 маркера -- не больше и не меньше

`resolve_range` в C-коде проверяет `ctm != 2` и вызывает `luaL_error`. Один маркер или три маркера -- ошибка.

### 4. Не выносит вердикт -- нужен drop

Самая частая ошибка: забыть `drop` после `tcpseg`. Без `drop` оригинальный пакет уйдёт, и сервер получит данные дважды. Это может работать (TCP-стек дедуплицирует), но неоптимально и может путать DPI.

### 5. drop по умолчанию дропает ВСЕ payload

Функция `drop` по умолчанию работает с `payload=all`. Если `tcpseg` работает только с `known`, то `drop` без ограничений заблокирует и `unknown` payload. Решение:

```bash
--lua-desync=tcpseg:pos=0,-1:seqovl=5 --lua-desync=drop:payload=known
```

### 6. Маркер 0 -- это начало, не "нулевая позиция Lua"

В `resolve_range` маркер `0` -- это абсолютный маркер начала данных. Внутри C-кода `pos[0]=0` соответствует первому байту. При возврате в Lua конвертируется в 1-based (`pos[0]+1`).

### 7. Fooling применяется к реальному сегменту

В отличие от [[fakedsplit]], где fooling идёт только на фейки, в `tcpseg` fooling модифицирует **реальный** отправляемый сегмент. Использование `tcp_ack=-66000` приведёт к тому, что сервер отбросит сегмент. Безопасные fooling-опции: `ip_id=rnd`, `tcp_ts_up`, IPv6 extension headers.

### 8. seqovl=10000 не вызовет ошибку

В отличие от nfqws1, где большие значения seqovl вызывали ошибку, nfqws2 автоматически сегментирует по MSS. Большой seqovl просто создаст много под-сегментов.

### 9. Нет nodrop -- потому что нет drop

В `tcpseg` нет параметра `nodrop`, потому что функция и так никогда не дропает. Для управления вердиктом используйте отдельный инстанс `drop`.

### 10. При неразрешённом диапазоне -- тихий пропуск

Если оба маркера не разрешаются (например, `pos=midsld,endhost` для `unknown` payload), `resolve_range` вернёт `nil`, и `tcpseg` залогирует "range cannot be resolved" и ничего не сделает. Без ошибки, без вердикта.

### 11. Повторная отправка (repeats) без drop -- атака повторами

`tcpseg` с `repeats=N` без `drop` отправит N копий сегмента, а затем оригинальный пакет тоже уйдёт. Это осознанная стратегия для забивания буфера DPI (см. blockcheck2/15-misc.sh).

---

## Отличия от других функций сегментации

| Аспект | `tcpseg` | `multisplit` | `multidisorder` | `fakedsplit` | `fakeddisorder` |
|:-------|:---------|:-------------|:----------------|:-------------|:----------------|
| Количество маркеров | **Ровно 2** (диапазон) | Список (любое кол-во) | Список (любое кол-во) | **Одна** | **Одна** |
| Что отправляется | **Часть** payload (диапазон) | **Весь** payload (разрезанный) | **Весь** payload (разрезанный) | **Весь** payload | **Весь** payload |
| Функция разрешения pos | `resolve_range` | `resolve_multi_pos` | `resolve_multi_pos` | `resolve_pos` | `resolve_pos` |
| pos обязателен | **Да** (error если нет) | Нет (дефолт "2") | Нет (дефолт "2") | Нет (дефолт "2") | Нет (дефолт "2") |
| Вердикт | **Нет** (не выносит) | `VERDICT_DROP` | `VERDICT_DROP` | `VERDICT_DROP` | `VERDICT_DROP` |
| nodrop | Нет (не нужен) | Да | Да | Да | Да |
| Порядок отправки | Один сегмент | Прямой (1->2->3) | Обратный (3->2->1) | Прямой | Обратный |
| Фейковые сегменты | **Нет** | **Нет** | **Нет** | Да (до 4 шт.) | Да (до 4 шт.) |
| seqovl тип | Только число | Только число | **Маркер** | Только число | **Маркер** |
| Fooling к | Реальному сегменту | Всем сегментам | Всем сегментам | Только к фейкам | Только к фейкам |
| ipfrag | Да | Да | Да | **Нет** | **Нет** |
| Нужен отдельный drop | **Да** | Нет (встроен) | Нет (встроен) | Нет (встроен) | Нет (встроен) |

---

## Практические примеры

### 1. Минимальный seqovl без сегментации (TLS)

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=0,-1:seqovl=1 \
  --lua-desync=drop
```

Отправляет весь payload с 1 нулевым байтом seqovl слева. Drop блокирует оригинал.

### 2. seqovl с TLS-фейковым паттерном

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=0,-1:seqovl=5:seqovl_pattern=0x1603030000 \
  --lua-desync=drop
```

5-байтовый TLS record header как seqovl-prefix. DPI видит начало "нового" TLS record перед настоящим ClientHello.

### 3. seqovl с предзагруженным фейком и tls_mod

```bash
--payload=tls_client_hello \
  --blob=seqovl_pat:@fake_tls.bin \
  --lua-init=seqovl_pat=tls_mod(seqovl_pat,'rnd') \
  --lua-desync=tcpseg:pos=0,-1:seqovl=#seqovl_pat:seqovl_pattern=seqovl_pat \
  --lua-desync=drop
```

Blob загружается из файла, рандомизируется через `tls_mod`, используется как seqovl_pattern с размером blob в качестве seqovl.

### 4. Динамический случайный seqovl через luaexec

```bash
--lua-desync=luaexec:code='desync.rnd=brandom_az(math.random(5,10))' \
--lua-desync=tcpseg:pos=0,-1:seqovl=#rnd:seqovl_pattern=rnd \
--lua-desync=drop:payload=known
```

На каждый пакет генерируется случайная строка из букв a-z длиной 5-10 символов. Используется как seqovl_pattern, а её размер -- как значение seqovl. Drop только для known payload.

### 5. seqovl с padencap и tls_mod (продвинутый)

```bash
--payload=tls_client_hello \
  --blob=seqovl_pat:@fake_tls.bin \
  --lua-desync=luaexec:code="desync.patmod=tls_mod(seqovl_pat,'rnd,dupsid,padencap',desync.reasm_data)" \
  --lua-desync=tcpseg:pos=0,-1:seqovl=#patmod:seqovl_pattern=patmod \
  --lua-desync=drop
```

Динамическая модификация фейка с учётом реального payload (через `desync.reasm_data`). Паттерн маскируется под TLS с padding, рандомизацией и дублированием session ID.

### 6. Повторная отправка начала HTTP-запроса (без drop)

```bash
--payload=http_req \
  --lua-desync=tcpseg:pos=0,method+2:ip_id=rnd:repeats=20
```

Отправляет первые 2 байта HTTP-метода (например, `GE` из `GET`) 20 раз со случайными IP ID. Оригинальный пакет тоже уходит (нет drop). Стратегия забивания буфера DPI.

### 7. Повторная отправка до midsld (TLS)

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=0,midsld:ip_id=rnd:repeats=100
```

Отправляет начало ClientHello до середины SNI 100 раз. DPI может переполнить свой буфер и перестать анализировать поток.

### 8. Отправка только hostname

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=host,endhost
```

Вырезает и отправляет **только** hostname из SNI. Без drop и без seqovl -- чисто для экспериментов или в составе сложной цепочки.

### 9. seqovl без сегментации + IP-фрагментация

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=0,-1:seqovl=5:ipfrag:ipfrag_disorder:ipfrag_pos_tcp=32 \
  --lua-desync=drop
```

Весь payload с seqovl отправляется, TCP-сегмент дополнительно фрагментируется на IP-уровне в обратном порядке.

### 10. Только первый байт TLS record (повторы)

```bash
--payload=tls_client_hello \
  --lua-desync=tcpseg:pos=0,1:ip_id=rnd:repeats=260
```

Отправляет только первый байт TLS record 260 раз. Используется в blockcheck2 для тестирования misc-стратегий.

### 11. Комбинация: fake + tcpseg + drop (полная стратегия)

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --lua-desync=tcpseg:pos=0,-1:seqovl=5:seqovl_pattern=0x1603030000 \
  --lua-desync=drop
```

1. `fake` отправляет фейковый TLS ClientHello с md5sig fooling
2. `tcpseg` отправляет настоящий payload с seqovl
3. `drop` блокирует оригинальный пакет

### 12. Защита от отсутствующего blob

```bash
--lua-desync=tcpseg:pos=0,-1:blob=maybe_missing:optional:seqovl=5
```

Если blob `maybe_missing` не существует -- tcpseg тихо пропускает. Без ошибок.

### 13. HTTP: seqovl=1 + drop (минимальный рабочий пример)

```bash
--payload=http_req \
  --lua-desync=tcpseg:pos=0,-1:seqovl=1 \
  --lua-desync=drop
```

Один нулевой байт seqovl перед HTTP-запросом. Минимальная модификация, но может обмануть DPI, который ожидает HTTP-метод с первого байта TCP-потока.

### 14. wssize + tcpseg + drop (контроль TCP window)

```bash
--payload=tls_client_hello \
  --lua-desync=wssize:wsize=1:scale=6 \
  --lua-desync=tcpseg:pos=0,-1:seqovl=5:seqovl_pattern=fake_default_tls \
  --lua-desync=drop
```

Сначала `wssize` устанавливает маленький TCP window, затем `tcpseg` отправляет payload с seqovl, и `drop` блокирует оригинал.

---

> **Источники:** `lua/zapret-antidpi.lua:1030-1076`, `nfq2/lua.c:3281-3328` (resolve_range), `docs/manual.md:4248-4274`, `docs/readme.md:394-412`, `blockcheck2.d/standard/15-misc.sh`, `blockcheck2.d/standard/23-seqovl.sh` из репозитория zapret2.

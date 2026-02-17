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
  - hostfakesplit
  - fake
  - hostname
aliases:
  - hostfakesplit
---

# `hostfakesplit` — TCP-сегментация с фейковым hostname (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:695`
**nfqws1 эквивалент:** `--dpi-desync=hostfakesplit`
**Сигнатура:** `function hostfakesplit(ctx, desync)`

`hostfakesplit` — специализированная функция TCP-сегментации с замешиванием фейковых hostname-сегментов. Она предназначена **исключительно** для payload, содержащих имя хоста (`http_req` и `tls_client_hello`). Функция автоматически определяет границы hostname в payload, генерирует фейковый hostname той же длины (через [[genhost]]), и отправляет последовательность из реальных и фейковых TCP-сегментов. После успешной отправки выносит `VERDICT_DROP`, чтобы оригинальный пакет не ушёл.

Родственные функции: [[multisplit]] (базовая сегментация), [[multidisorder]] (обратный порядок), [[fakedsplit]] (фейки по произвольной позиции), [[fakeddisorder]] (фейки + обратный порядок), [[tcpseg]] (диапазон), [[oob]] (urgent byte).

---

## Оглавление

- [Зачем нужен hostfakesplit](#зачем-нужен-hostfakesplit)
- [Быстрый старт](#быстрый-старт)
- [Откуда берутся данные](#откуда-берутся-данные)
- [Основные точки разреза: host и endhost](#основные-точки-разреза-host-и-endhost)
- [Генерация фейкового hostname (genhost)](#генерация-фейкового-hostname-genhost)
- [Дополнительные точки разреза](#дополнительные-точки-разреза)
  - [midhost — разрез внутри hostname](#midhost--разрез-внутри-hostname)
  - [disorder_after — обратный порядок хвоста](#disorder_after--обратный-порядок-хвоста)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы hostfakesplit](#a-собственные-аргументы-hostfakesplit)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard reconstruct](#f-standard-reconstruct)
  - [G) Standard rawsend](#g-standard-rawsend)
- [Порядок отправки сегментов](#порядок-отправки-сегментов)
- [Разделение opts: оригиналы vs фейки](#разделение-opts-оригиналы-vs-фейки)
- [Поведение при replay / reasm](#поведение-при-replay--reasm)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Отличия от других функций сегментации](#отличия-от-других-функций-сегментации)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен hostfakesplit

DPI ищет hostname в TCP-потоке: заголовок `Host:` в HTTP, поле SNI в TLS ClientHello. Если DPI работает попакетно (не реассемблирует TCP), достаточно разрезать payload по границам hostname. Но продвинутые DPI умеют реассемблировать поток и собрать hostname из нескольких сегментов.

`hostfakesplit` решает обе проблемы одновременно:

1. **Разрез по границам hostname:** payload разрезается точно по маркерам `host` и `endhost`, так что ни один сегмент не содержит полный hostname в "чистом" виде
2. **Замешивание фейков:** между реальными сегментами вставляются фейковые TCP-сегменты с тем же TCP sequence, но с **другим** hostname (сгенерированным [[genhost]]). DPI, пытающийся реассемблировать поток, может принять фейковый hostname за настоящий
3. **Fooling на фейках:** фейковые сегменты отправляются с fooling-опциями (TTL, md5sig, badseq и т.д.), поэтому сервер их отбрасывает, а DPI — нет

Сервер корректно собирает поток: фейки отбрасываются благодаря fooling, реальные сегменты доставляются через стандартный TCP-механизм.

**Ключевое отличие от [[fakedsplit]]:** `hostfakesplit` автоматически знает где hostname, генерирует осмысленный фейковый hostname той же длины и имеет опцию `midhost` для дополнительного разреза внутри hostname. [[fakedsplit]] работает по произвольной позиции и заливает фейк паттерном (0x00 и т.п.).

---

## Быстрый старт

Минимально (fooling обязателен для фейков!):

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5
```

С шаблоном для фейкового hostname:

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:host=google.com
```

С дополнительным разрезом посередине hostname:

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:midhost=midsld
```

С disorder хвостовой части:

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:disorder_after
```

---

## Откуда берутся данные

Внутри `hostfakesplit` данные (`data`) выбираются в следующем порядке приоритетов:

```
1. blob_or_def(desync, desync.arg.blob)    — если задан blob= и он существует
2. desync.reasm_data                        — если есть реассемблированные данные
3. desync.dis.payload                       — текущий пакет (fallback)
```

**Следствие:** маркеры `host`, `endhost`, `midsld` и прочие работают по тем данным, которые реально выбраны. Если задан `blob=myblob`, маркеры разрешатся только если `myblob` содержит валидный TLS ClientHello или HTTP-запрос, который zapret может распознать.

---

## Основные точки разреза: host и endhost

`hostfakesplit` **не принимает** произвольный `pos=`. Вместо этого две основные точки разреза определяются автоматически через вызов:

```lua
local pos = resolve_range(data, desync.l7payload, "host,endhost-1", true)
```

Это разрешает два маркера с `strict=true`:
- `pos[1]` = **host** — первый байт имени хоста (начало `Host:` значения в HTTP, начало SNI в TLS)
- `pos[2]` = **endhost-1** — последний байт имени хоста (байт перед `endhost`)

Если хотя бы один маркер не разрешается (например, payload = `unknown` или `quic_initial`), функция логирует "host range cannot be resolved" и ничего не делает.

**Таким образом:** `hostfakesplit` работает **только** с `http_req` и `tls_client_hello`.

---

## Генерация фейкового hostname (genhost)

Фейковый hostname генерируется вызовом:

```lua
fakehost = genhost(pos[2] - pos[1] + 1, desync.arg.host)
```

- **Длина фейка** всегда равна длине реального hostname (`endhost - host`). Это критически важно: DPI видит hostname той же длины на том же TCP sequence, и не может отличить по размеру
- **С шаблоном** (`host=vk.com`): генерируется случайный поддомен, например `e8nzn.vk.com`. Если реальный hostname короче шаблона — шаблон обрезается слева
- **Без шаблона**: генерируется случайный домен с одним из стандартных TLD (`com`, `org`, `net`, `edu`, `gov`, `biz`). Если длина < 7 — случайная строка без точек

Примеры генерации (шаблон `google.com`, реальный hostname длиной 16):

```
h82aj.google.com    (len=16, template="google.com")
```

Примеры без шаблона:

```
k3x.net             (len=7)
b8c54a              (len=6, без TLD)
u9a7bk2.org         (len=11)
```

---

## Дополнительные точки разреза

### midhost — разрез внутри hostname

`midhost` задает позицию для **дополнительного** разреза внутри реального hostname. Реальный hostname отправляется не одним сегментом, а двумя.

```
midhost=<posmarker>
```

Маркер разрешается через `resolve_pos`. Типичные значения: `midsld`, `sld`, `endsld`, `host+5`, и т.д.

**Ограничение:** разрешенная позиция `midhost` должна быть строго внутри hostname:

```
host + 1  <=  midhost  <=  endhost - 1
```

Если позиция выходит за эти границы (т.е. `midhost <= pos[1]` или `midhost > pos[2]`), разрез внутри hostname не происходит, и hostname отправляется одним сегментом. Функция логирует "midhost is not inside the host range".

**Без midhost:**

```
  Один сегмент: [весь реальный hostname]
```

**С midhost=midsld:**

```
  Сегмент 3a: [host → midhost-1]       (первая часть hostname)
  Сегмент 3b: [midhost → endhost-1]    (вторая часть hostname)
```

### disorder_after — обратный порядок хвоста

`disorder_after` задает позицию для **дополнительного** разреза хвостовой части (всё что после hostname) и отправки двух результирующих частей в **обратном** порядке.

```
disorder_after=<posmarker>
```

**Особый случай:** если маркер — пустая строка (`disorder_after` без `=значения`, т.е. просто `:disorder_after`), используется маркер `"-1"` (последний байт payload).

```lua
disorder_after_pos = resolve_pos(data, desync.l7payload,
    desync.arg.disorder_after == "" and "-1" or desync.arg.disorder_after)
```

**Ограничение:** разрешенная позиция должна быть **строго больше** `pos[2] + 1` (т.е. после endhost):

```
disorder_after_pos  >  pos[2] + 1
```

Если это условие не выполняется, disorder не происходит, и хвост отправляется одним сегментом в прямом порядке.

**Без disorder_after:**

```
  Один сегмент: [endhost → конец данных]
```

**С disorder_after (порядок отправки перевернут!):**

```
  Сначала: [disorder_after → конец данных]    (последняя часть, отправлена ПЕРВОЙ)
  Затем:   [endhost → disorder_after-1]       (средняя часть, отправлена ВТОРОЙ)
```

DPI, ожидающий данные по порядку, может не собрать хвост корректно.

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=hostfakesplit[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`, `:nodrop`, `:nofake1`.

### A) Собственные аргументы hostfakesplit

#### `host`

- **Формат:** `host=<str>`
- **Тип:** строка (шаблон hostname)
- **По умолчанию:** не задан (случайный домен со стандартным TLD)
- **Описание:** Шаблон для генерации фейкового hostname через [[genhost]]. Фейк будет выглядеть как `random.template`, например для `host=vk.com` и реального hostname длиной 12 символов: `e8nzn.vk.com`
- **Рекомендация:** задавайте домен, похожий на реальный (тот же TLD, популярный сервис), чтобы фейк выглядел правдоподобно для DPI-эвристик
- **Примеры:**
  - `host=google.com` — фейк вида `k7z2a.google.com`
  - `host=vk.com` — фейк вида `e8nzn.vk.com`
  - без `host=` — фейк вида `r4k2m.net` или `b8c54a` (случайный)

#### `midhost`

- **Формат:** `midhost=<posmarker>`
- **Тип:** строка (маркер позиции)
- **По умолчанию:** не задан (реальный hostname отправляется одним сегментом)
- **Описание:** Дополнительный разрез реального hostname на два сегмента. Маркер разрешается через `resolve_pos`. Должен быть строго внутри `host+1..endhost-1`, иначе игнорируется
- **Примеры:**
  - `midhost=midsld` — разрез посередине SLD (самый популярный вариант)
  - `midhost=sld` — разрез по началу SLD
  - `midhost=endsld` — разрез по концу SLD
  - `midhost=host+5` — 5 байт от начала hostname

#### `nofake1`

- **Формат:** `nofake1` (флаг, без значения)
- **Описание:** Не отправлять **первый** фейковый сегмент (fake1, перед реальным hostname). Полезно для экспериментов: некоторые DPI реагируют только на один из фейков

#### `nofake2`

- **Формат:** `nofake2` (флаг, без значения)
- **Описание:** Не отправлять **второй** фейковый сегмент (fake2, после реального hostname). Аналогично `nofake1`, но для второго фейка

#### `disorder_after`

- **Формат:** `disorder_after[=<posmarker>]`
- **Тип:** строка (маркер позиции) или пустая строка
- **По умолчанию:** не задан (хвост отправляется одним сегментом в прямом порядке)
- **Описание:** Дополнительный разрез хвостовой части (после hostname) и отправка в обратном порядке. Если значение = пустая строка (`:disorder_after` без `=...`), используется маркер `"-1"` (последний байт payload). Позиция должна быть > `endhost`, иначе игнорируется
- **Примеры:**
  - `disorder_after` — разрез по `-1` (последний байт), disorder всего хвоста
  - `disorder_after=-10` — разрез за 10 байт до конца payload
  - `disorder_after=sniext+50` — разрез через 50 байт после начала SNI extension data

#### `blob`

- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** не задан
- **Описание:** Заменить текущий payload/reasm на указанный blob. Blob должен содержать валидный HTTP-запрос или TLS ClientHello, иначе маркеры `host`/`endhost` не разрешатся
- **Примеры:**
  - `blob=fake_default_tls` — стандартный TLS-фейк
  - `blob=my_custom_ch` — предзагруженный blob с модифицированным ClientHello

#### `optional`

- **Формат:** `optional` (флаг, без значения)
- **Описание:** Мягкий режим:
  - Если задан `blob=...` и blob отсутствует — `hostfakesplit` **ничего не делает** (тихий skip, без ошибок)
- **Использование:** защита от ошибок при использовании blob, которые могут отсутствовать

#### `nodrop`

- **Формат:** `nodrop` (флаг, без значения)
- **Описание:** После успешной отправки сегментов **не выносить** `VERDICT_DROP` (вместо этого вернуть `VERDICT_PASS`). Оригинальный пакет тоже будет отправлен
- **Предупреждение:** в боевых профилях `nodrop` нежелателен — оригинал создаст дублирование и может ухудшить обход

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `hostfakesplit` по умолчанию работает только с исходящими (`out`).

- `dir=out` — только исходящие (от клиента к серверу)
- `dir=in` — только входящие (от сервера к клиенту)
- `dir=any` — оба направления

---

### C) Standard payload

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `payload` | список типов через запятую | `known` |

Фильтр по типу payload на уровне Lua. Это **дополнительный** фильтр к `--payload=...` на уровне профиля.

- `payload=known` — только распознанные протоколы
- `payload=tls_client_hello,http_req` — конкретные типы
- `payload=all` — любой payload, включая `unknown`

**Важно:** `hostfakesplit` требует payload с hostname (`http_req`, `tls_client_hello`). Даже при `payload=all`, если payload = `unknown`, маркеры `host`/`endhost` не разрешатся и функция ничего не сделает. Поэтому фильтр `payload` здесь влияет только на то, дойдет ли код до попытки resolve_range.

---

### D) Standard fooling

Модификации L3/L4 заголовков. В `hostfakesplit` fooling и repeats применяются **только к фейковым** сегментам. К оригиналам — только `tcp_ts_up`.

| Параметр | Описание | Пример |
|:---------|:---------|:-------|
| `ip_ttl=N` | Установить IPv4 TTL | `ip_ttl=6` |
| `ip6_ttl=N` | Установить IPv6 Hop Limit | `ip6_ttl=6` |
| `ip_autottl=delta,min-max` | Автоматический TTL (delta от серверного TTL) | `ip_autottl=-2,40-64` |
| `ip6_autottl=delta,min-max` | Аналогично для IPv6 | `ip6_autottl=-2,40-64` |
| `ip6_hopbyhop[=HEX]` | Вставить extension header hop-by-hop | `ip6_hopbyhop` |
| `ip6_hopbyhop2[=HEX]` | Второй hop-by-hop header | `ip6_hopbyhop2` |
| `ip6_destopt[=HEX]` | Destination options header | `ip6_destopt` |
| `ip6_destopt2[=HEX]` | Второй destination options | `ip6_destopt2` |
| `ip6_routing[=HEX]` | Routing header | `ip6_routing` |
| `ip6_ah[=HEX]` | Authentication header | `ip6_ah` |
| `tcp_seq=N` | Сместить TCP sequence (+ или -) | `tcp_seq=-10000` |
| `tcp_ack=N` | Сместить TCP ack (+ или -) | `tcp_ack=-66000` |
| `tcp_ts=N` | Сместить TCP timestamp | `tcp_ts=-100` |
| `tcp_md5[=HEX]` | Добавить TCP MD5 option (16 байт) | `tcp_md5` |
| `tcp_flags_set=LIST` | Установить TCP-флаги | `tcp_flags_set=FIN,PUSH` |
| `tcp_flags_unset=LIST` | Снять TCP-флаги | `tcp_flags_unset=ACK` |
| `tcp_ts_up` | Поднять TCP timestamp option в начало заголовка | `tcp_ts_up` |
| `tcp_nop_del` | Удалить все TCP NOP опции | `tcp_nop_del` |
| `fool=<func>` | Кастомная Lua-функция fooling | `fool=my_fooler` |

**Критически важно:** fooling **обязателен** для `hostfakesplit`. Без fooling фейковые hostname будут приняты сервером, что вызовет ошибку соединения. Минимально рекомендуемый fooling: `tcp_md5` или `ip_ttl=1`.

**Заметка про tcp_ts_up:** это единственная fooling-опция, которая применяется и к оригинальным сегментам. Она перемещает TCP timestamp option в начало заголовка, что улучшает совместимость с badseq-fooling на серверах с Linux TCP-стеком.

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | — |
| `ip_id=zero` | Нулевые IP ID | — |
| `ip_id=none` | Не менять IP ID | — |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения | — |

`ip_id` применяется и к фейкам, и к оригиналам (через `ipid = desync.arg` в обоих `opts`).

---

### F) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета |

**Важно:** `reconstruct` (включая `badsum`) применяется **только к фейкам**. У оригиналов `reconstruct = {}` (пустая таблица). Это логично: если испортить checksum на оригинале, сервер его отбросит.

---

### G) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить каждый сегмент N раз |
| `ifout=<iface>` | Интерфейс для отправки |
| `fwmark=N` | Firewall mark (только Linux) |

**Важно:** `repeats` применяется **только к фейкам**. Оригиналы используют `rawsend_opts_base`, в которой repeats отсутствует. Фейки используют `rawsend_opts`, включающую `repeats`. Таким образом `repeats=3` означает, что каждый фейковый сегмент отправится 3 раза, а каждый реальный — 1 раз.

`ifout` и `fwmark` применяются и к фейкам, и к оригиналам.

---

## Порядок отправки сегментов

### Базовый вариант (без midhost, без disorder_after)

```
Payload: [....before_host....][..hostname..][....after_host....]
                               ^host        ^endhost

Отправка (5 сегментов, 3 реальных + 2 фейка):
  1. [before_host]           — реальный, opts_orig
  2. [FAKE hostname]         — фейк (fake1), opts_fake
  3. [hostname]              — реальный, opts_orig
  4. [FAKE hostname]         — фейк (fake2), opts_fake
  5. [after_host]            — реальный, opts_orig
```

### С midhost (hostname делится на две части)

```
Payload: [....before_host....][..host_part1..][..host_part2..][....after_host....]
                               ^host          ^midhost        ^endhost

Отправка (6 сегментов, 4 реальных + 2 фейка):
  1. [before_host]           — реальный, opts_orig
  2. [FAKE hostname]         — фейк (fake1), opts_fake
  3a.[host_part1]            — реальный (host → midhost-1), opts_orig
  3b.[host_part2]            — реальный (midhost → endhost-1), opts_orig
  4. [FAKE hostname]         — фейк (fake2), opts_fake
  5. [after_host]            — реальный, opts_orig
```

### С disorder_after (хвост в обратном порядке)

```
Payload: [....before_host....][..hostname..][..after_1..][..after_2..]
                               ^host        ^endhost     ^disorder_after

Отправка (6 сегментов, 4 реальных + 2 фейка):
  1. [before_host]           — реальный, opts_orig
  2. [FAKE hostname]         — фейк (fake1), opts_fake
  3. [hostname]              — реальный, opts_orig
  4. [FAKE hostname]         — фейк (fake2), opts_fake
  5a.[after_2]               — реальный (disorder_after → конец), ПЕРВЫМ
  5b.[after_1]               — реальный (endhost → disorder_after-1), ВТОРЫМ
```

### Полный вариант (midhost + disorder_after + оба фейка)

```
Payload:
  [before_host][host_p1][host_p2][after_1][after_2]
                ^host    ^mid     ^endhost ^disord

Отправка (7 сегментов):
  1.  [before_host]      seq=0              opts_orig
  2.  [FAKE hostname]    seq=host           opts_fake (fake1)
  3a. [host_p1]          seq=host           opts_orig
  3b. [host_p2]          seq=midhost        opts_orig
  4.  [FAKE hostname]    seq=host           opts_fake (fake2)
  5a. [after_2]          seq=disorder_after opts_orig (ПЕРВЫМ)
  5b. [after_1]          seq=endhost        opts_orig (ВТОРЫМ)
```

### ASCII-диаграмма: вид на уровне TCP sequence

```
TCP sequence (байты):
  0          host     midhost  endhost  disord   end
  |           |         |        |        |       |
  v           v         v        v        v       v
  [before_host][=hostname=area=][=after_host_area=]

Порядок отправки пакетов по времени (сверху вниз):

  t=1  |-before-|                                        seq=0          REAL
  t=2            |====FAKE_HOST====|                     seq=host       FAKE
  t=3            |--p1--|                                seq=host       REAL
  t=4                    |---p2---|                      seq=mid        REAL
  t=5            |====FAKE_HOST====|                     seq=host       FAKE
  t=6                                       |--after2--| seq=disord    REAL
  t=7                              |after1--|            seq=endhost   REAL
```

**Что видит DPI:** на одном и том же TCP sequence (`host`) приходят разные данные — реальный hostname и фейковый. DPI должен выбрать, какой из них "правильный". Если DPI выбирает фейк — обход успешен.

**Что видит сервер:** фейковые пакеты отброшены благодаря fooling (инвалидный TTL, md5sig, badseq и т.д.). Реальные сегменты корректно реассемблируются TCP-стеком.

---

## Разделение opts: оригиналы vs фейки

Это ключевая особенность `hostfakesplit` (и аналогичных fake-функций):

```lua
opts_orig = {
    rawsend    = rawsend_opts_base(desync),   -- ifout, fwmark. БЕЗ repeats
    reconstruct = {},                          -- пустой (без badsum)
    ipfrag     = {},                           -- пустой (ipfrag не используется)
    ipid       = desync.arg,                   -- ip_id применяется
    fooling    = {tcp_ts_up = desync.arg.tcp_ts_up}  -- ТОЛЬКО tcp_ts_up
}

opts_fake = {
    rawsend    = rawsend_opts(desync),         -- ifout, fwmark, repeats
    reconstruct = reconstruct_opts(desync),    -- badsum
    ipfrag     = {},                           -- пустой (ipfrag не используется)
    ipid       = desync.arg,                   -- ip_id применяется
    fooling    = desync.arg                    -- ВСЕ fooling-опции
}
```

| Что | Оригиналы | Фейки |
|:----|:----------|:------|
| fooling | Только `tcp_ts_up` | Все (`ip_ttl`, `tcp_md5`, `tcp_seq`, ...) |
| reconstruct (badsum) | Нет | Да |
| repeats | Нет (всегда 1 раз) | Да |
| ipfrag | Нет | Нет |
| ip_id | Да | Да |
| ifout, fwmark | Да | Да |

---

## Поведение при replay / reasm

При многопакетных payload (например, TLS ClientHello с post-quantum Kyber) zapret собирает части в `reasm_data`. При перепроигрывании:

1. **Первая часть replay:** `hostfakesplit` берёт весь `reasm_data`, определяет hostname, генерирует фейк, отправляет все сегменты. Устанавливает флаг `replay_drop_set`
2. **Все последующие части replay:** `hostfakesplit` видит, что отправка уже произошла, и выносит `VERDICT_DROP` (если не `nodrop`)

**Исключение:** если первая отправка неуспешна (`rawsend` вернул `false`), флаг не устанавливается и последующие части проходят как есть.

---

## Псевдокод алгоритма

```lua
function hostfakesplit(ctx, desync)
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
        if replay_first() then

            -- 6. Разрешение host и endhost (strict=true)
            pos = resolve_range(data, l7payload, "host,endhost-1", true)
            -- pos[1] = host, pos[2] = endhost-1 (последний байт hostname)

            if pos then
                -- 7. Подготовка opts
                opts_orig = { fooling = {tcp_ts_up only}, no repeats, no badsum }
                opts_fake = { fooling = all, repeats, badsum }

                -- 8. Отправка before_host (реальный)
                rawsend(data[1..host-1], seq=0, opts_orig)

                -- 9. Генерация фейкового hostname
                fakehost = genhost(endhost - host, arg.host)

                -- 10. Fake1 (если не nofake1)
                if not nofake1 then
                    rawsend(fakehost, seq=host-1, opts_fake)
                end

                -- 11. Реальный hostname (с midhost или без)
                if midhost and midhost внутри host+1..endhost-1 then
                    rawsend(data[host..midhost-1], seq=host-1, opts_orig)
                    rawsend(data[midhost..endhost-1], seq=midhost-1, opts_orig)
                else
                    rawsend(data[host..endhost-1], seq=host-1, opts_orig)
                end

                -- 12. Fake2 (если не nofake2)
                if not nofake2 then
                    rawsend(fakehost, seq=host-1, opts_fake)
                end

                -- 13. After_host (с disorder или без)
                if disorder_after and disorder_after > endhost then
                    -- ОБРАТНЫЙ порядок:
                    rawsend(data[disorder_after..end], seq=disorder_after-1, opts_orig)
                    rawsend(data[endhost..disorder_after-1], seq=endhost-1, opts_orig)
                else
                    rawsend(data[endhost..end], seq=endhost-1, opts_orig)
                end

                -- 14. Пометить как отправленное
                replay_drop_set()
                return nodrop and VERDICT_PASS or VERDICT_DROP
            else
                DLOG("host range cannot be resolved")
            end
        else
            DLOG("not acting on further replay pieces")
        end
        -- 15. Drop replayed packets если ранее успешно отправлено
        if replay_drop() then
            return nodrop and VERDICT_PASS or VERDICT_DROP
        end
    end
end
```

---

## Нюансы и подводные камни

### 1. Работает только с http_req и tls_client_hello

`hostfakesplit` требует payload с hostname. Для `unknown`, `quic_initial` и любых других типов маркеры `host`/`endhost` не разрешатся, и функция ничего не сделает. Это **не ошибка** — просто тихий пропуск.

### 2. Fooling обязателен

Без fooling фейковые hostname будут приняты сервером. Сервер получит два противоречивых hostname на одном TCP sequence. Результат непредсказуем: от ошибки TLS handshake до 400 Bad Request. **Всегда** задавайте хотя бы одну fooling-опцию (`tcp_md5`, `ip_ttl=1`, `badsum`, `tcp_seq=-10000` и т.д.).

### 3. ipfrag не задействуется

В отличие от [[multisplit]] и [[multidisorder]], `hostfakesplit` **не поддерживает** IP-фрагментацию. Поля `ipfrag = {}` пусты и для оригиналов, и для фейков. Если вам нужна IP-фрагментация поверх hostname-разреза — придётся комбинировать с другими инструментами.

### 4. repeats идут только на фейки

`repeats=5` означает, что каждый фейковый сегмент отправится 5 раз, а реальные — по 1 разу. Это полезно: повторение фейков увеличивает шанс, что DPI примет именно фейк, а не реальный hostname.

### 5. midhost за пределами hostname молча игнорируется

Если `midhost` разрешается в позицию за пределами hostname (например, `midhost=method` для HTTP, который указывает на начало `GET`), разрез внутри hostname не произойдет. Функция логирует "midhost is not inside the host range" и отправляет hostname одним сегментом.

### 6. disorder_after с пустым значением = "-1"

Запись `:disorder_after` (без `=значения`) эквивалентна `:disorder_after=-1`. Маркер `-1` разрешается в `#data - 1` (предпоследний байт payload в 0-based, последний байт в 1-based). Это делает disorder хвостовой части максимально выраженным: последний байт отправляется первым, а основная часть хвоста — вторым.

### 7. Оба фейка используют один и тот же fakehost

`genhost` вызывается один раз, и результат (`fakehost`) используется и для fake1, и для fake2. Оба фейковых сегмента содержат **идентичный** фейковый hostname и отправляются с одинаковым TCP sequence (`pos[1]-1`).

### 8. TCP sequence фейков = TCP sequence реального hostname

Фейки отправляются с тем же `seq = pos[1] - 1`, что и реальный hostname. Это означает, что DPI видит **перекрывающиеся** данные: на одном и том же диапазоне sequence — фейковый hostname, затем реальный, затем снова фейковый. TCP-стек сервера отбросит фейки (благодаря fooling) и примет реальный.

### 9. nodrop создает дублирование

С `nodrop` оригинальный пакет тоже будет отправлен. Сервер получит hostname дважды (из нарезанных сегментов и из оригинала). Используйте `nodrop` только для отладки.

### 10. Порядок инстансов важен

Если перед `hostfakesplit` стоит `pktmod` с fooling — fooling применится к диссекту, и `hostfakesplit` порежет модифицированный пакет. Если после `hostfakesplit` стоит другой инстанс — он увидит `VERDICT_DROP` и не получит оригинальный payload.

---

## Отличия от других функций сегментации

| Аспект | `hostfakesplit` | `fakedsplit` | `fakeddisorder` | `multisplit` | `multidisorder` |
|:-------|:----------------|:-------------|:----------------|:-------------|:----------------|
| Точки разреза | Автоматические (host/endhost) + midhost, disorder_after | Одна произвольная | Одна произвольная | Список произвольных | Список произвольных |
| Привязка к hostname | **Да** (только http_req, tls_client_hello) | Нет | Нет | Нет | Нет |
| Фейковые сегменты | 2 (фейковый hostname) | До 4 (паттерн) | До 4 (паттерн) | Нет | Нет |
| Содержимое фейков | Осмысленный hostname (genhost) | Паттерн (0x00 и т.п.) | Паттерн (0x00 и т.п.) | — | — |
| disorder хвоста | Опционально (disorder_after) | Нет | Весь порядок обратный | Нет | Весь порядок обратный |
| seqovl | **Нет** | Да (число) | Да (маркер) | Да (число) | Да (маркер) |
| ipfrag | **Нет** | **Нет** | **Нет** | Да | Да |
| Fooling к | Только фейкам | Только фейкам | Только фейкам | Всем сегментам | Всем сегментам |
| repeats к | Только фейкам | Только фейкам | Только фейкам | Всем сегментам | Всем сегментам |

---

## Миграция с nfqws1

### Соответствие параметров

| nfqws1 | nfqws2 |
|:-------|:-------|
| `--dpi-desync=hostfakesplit` | `--lua-desync=hostfakesplit` |
| `--dpi-desync-fooling=md5sig` | `:tcp_md5` |
| `--dpi-desync-fooling=badseq` | `:tcp_seq=-10000` |
| `--dpi-desync-fooling=ttl` + `--dpi-desync-ttl=N` | `:ip_ttl=N` |
| `--dpi-desync-fake-unknown=hex` | `:host=<template>` (не прямой аналог; genhost вместо hex) |
| нет аналога | `:midhost=midsld` (новая возможность nfqws2) |
| нет аналога | `:disorder_after` (новая возможность nfqws2) |
| нет аналога | `:nofake1`, `:nofake2` (новая возможность nfqws2) |

### Пример полной миграции

```bash
# nfqws1:
nfqws --dpi-desync=hostfakesplit \
  --dpi-desync-fooling=md5sig

# nfqws2 (эквивалент):
nfqws2 \
  --payload=tls_client_hello,http_req \
    --lua-desync=hostfakesplit:tcp_md5
```

```bash
# nfqws1: hostfakesplit + fake
nfqws --dpi-desync=fake,hostfakesplit \
  --dpi-desync-fooling=md5sig \
  --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid

# nfqws2 (два инстанса):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --payload=http_req \
    --lua-desync=fake:blob=fake_default_http:tcp_md5 \
  --payload=tls_client_hello,http_req \
    --lua-desync=hostfakesplit:tcp_md5
```

```bash
# nfqws1: hostfakesplit + syndata
nfqws --dpi-desync=syndata,hostfakesplit \
  --dpi-desync-fooling=md5sig --wssize 1:6

# nfqws2:
nfqws2 \
  --lua-desync=wssize:wsize=1:scale=6 \
  --lua-desync=syndata \
  --payload=tls_client_hello,http_req \
    --lua-desync=hostfakesplit:tcp_md5
```

---

## Практические примеры

### 1. Минимальный (TLS + md5sig fooling)

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5
```

Разрезает TLS ClientHello по границам SNI, вставляет 2 фейка с md5sig fooling.

### 2. HTTP + TTL fooling

```bash
--payload=http_req --lua-desync=hostfakesplit:ip_ttl=4
```

Разрезает HTTP-запрос по границам `Host:`, фейки с TTL=4 (не доживут до сервера).

### 3. С шаблоном фейкового hostname

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:host=google.com
```

Фейковый SNI будет выглядеть как `r7k2q.google.com` (длина = длина реального hostname).

### 4. С midhost (разрез hostname пополам)

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:midhost=midsld
```

Реальный hostname разрезается посередине SLD. Вместо 3 реальных сегментов — 4. DPI получает ещё более фрагментированную картину.

### 5. С disorder хвоста (пустое значение = "-1")

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:disorder_after
```

Хвостовая часть (после hostname) отправляется в обратном порядке: последний байт первым, основная часть — вторым.

### 6. С disorder_after по конкретной позиции

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:disorder_after=-20
```

Хвост разрезается за 20 байт до конца payload. Последние 20 байт идут первыми, остальная часть хвоста — вторым.

### 7. Полный набор: midhost + disorder_after + шаблон

```bash
--payload=tls_client_hello \
  --lua-desync=hostfakesplit:tcp_md5:host=vk.com:midhost=midsld:disorder_after
```

Максимальная фрагментация: hostname разрезан пополам, хвост перевернут, фейки с правдоподобным `*.vk.com`.

### 8. Только один фейк (nofake2)

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:nofake2
```

Отправляется только fake1 (перед реальным hostname). Полезно если DPI реагирует именно на первый hostname в потоке.

### 9. Только второй фейк (nofake1)

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:nofake1
```

Отправляется только fake2 (после реального hostname). Для DPI, которые берут последний hostname.

### 10. С badsum на фейках

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:badsum
```

Фейковые сегменты получают невалидный TCP checksum. Сервер отбросит их, DPI (который часто не проверяет checksum) примет.

### 11. Многократные фейки (repeats)

```bash
--payload=tls_client_hello --lua-desync=hostfakesplit:tcp_md5:repeats=5
```

Каждый фейковый сегмент отправляется 5 раз. Реальные — по 1 разу. Итого: 1 before_host + 5 fake1 + 1 hostname + 5 fake2 + 1 after_host = 13 пакетов.

### 12. Комбинация: fake → hostfakesplit (два инстанса)

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=3:tls_mod=rnd,rndsni,dupsid \
  --lua-desync=hostfakesplit:tcp_md5:midhost=midsld:host=google.com
```

Сначала 3 фейковых TLS ClientHello (целиком), затем реальный — нарезанный по hostname с дополнительным разрезом по midsld и фейковым hostname `*.google.com`.

### 13. Боевой пример для YouTube (TLS)

```bash
--filter-tcp=443 --hostlist=youtube.txt \
  --lua-desync=fake:blob=fake_default_tls:repeats=5:tcp_md5 \
  --lua-desync=hostfakesplit:tcp_md5:midhost=midsld:host=google.com
```

5 фейковых TLS ClientHello + реальный с hostname-фейками и разрезом по midsld.

### 14. HTTP + TLS в одном конфиге

```bash
--filter-tcp=80 --hostlist=blocked.txt \
  --lua-desync=hostfakesplit:ip_ttl=3 \
--filter-tcp=443 --hostlist=blocked.txt \
  --lua-desync=hostfakesplit:tcp_md5:midhost=midsld
```

HTTP с TTL-fooling, TLS с md5sig и разрезом hostname.

### 15. С blob (отправка произвольного payload)

```bash
--blob=my_ch:@custom_clienthello.bin \
--payload=tls_client_hello \
  --lua-desync=hostfakesplit:tcp_md5:blob=my_ch
```

Вместо реального ClientHello отправляется кастомный blob (при условии, что в нём есть валидный SNI).

### 16. Защита от отсутствующего blob

```bash
--payload=tls_client_hello \
  --lua-desync=hostfakesplit:tcp_md5:blob=maybe_missing:optional
```

Если blob не существует — тихий пропуск, без ошибок.

---

> **Источники:** `lua/zapret-antidpi.lua:695-800`, `lua/zapret-lib.lua:396-401` (rawsend_opts/rawsend_opts_base), `lua/zapret-lib.lua:1287-1302` (genhost), `docs/manual.md:4208-4246` из репозитория zapret2.

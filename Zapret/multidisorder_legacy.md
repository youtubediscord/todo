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
  - multidisorder
  - multidisorder_legacy
  - seqovl
aliases:
  - multidisorder_legacy
---

# `multidisorder_legacy` --- попакетный обратный порядок TCP-сегментов (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:637`
**nfqws1 эквивалент:** `--dpi-desync=multidisorder` (полная совместимость)
**Сигнатура:** `function multidisorder_legacy(ctx, desync)`

`multidisorder_legacy` --- реализация алгоритма [[multidisorder]], **полностью совместимая с nfqws1**. Ключевое отличие от нового [[multidisorder]]: legacy-вариант работает **попакетно** --- он обрабатывает каждую оригинальную часть replay отдельно, сохраняя исходную TCP-сегментацию. Сегменты отправляются в обратном порядке **только внутри каждого пакета**, а между пакетами --- в прямом порядке (как они пришли).

Родственные функции: [[multisplit]] (прямой порядок), [[multidisorder]] (новый, по всему reasm), [[fakedsplit]] (с фейками), [[fakeddisorder]] (фейки + обратный порядок).

---

## Оглавление

- [Зачем нужен multidisorder_legacy](#зачем-нужен-multidisorder_legacy)
- [Быстрый старт](#быстрый-старт)
- [Ключевое отличие: попакетная обработка vs целый reasm](#ключевое-отличие-попакетная-обработка-vs-целый-reasm)
  - [Диаграмма: новый multidisorder (весь reasm)](#диаграмма-новый-multidisorder-весь-reasm)
  - [Диаграмма: multidisorder_legacy (попакетно)](#диаграмма-multidisorder_legacy-попакетно)
- [Откуда берутся данные](#откуда-берутся-данные)
- [Маркеры позиций (pos)](#маркеры-позиций-pos)
  - [Типы маркеров](#типы-маркеров)
  - [Относительные маркеры](#относительные-маркеры)
  - [Арифметика маркеров](#арифметика-маркеров)
  - [Нормализация позиций по пакету](#нормализация-позиций-по-пакету)
  - [Важные нюансы pos](#важные-нюансы-pos)
- [seqovl --- попакетный скрытый фейк](#seqovl--попакетный-скрытый-фейк)
  - [seqovl --- маркер, а не число](#seqovl--маркер-а-не-число)
  - [Нормализация seqovl по пакету](#нормализация-seqovl-по-пакету)
  - [seqovl_pattern](#seqovl_pattern)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы multidisorder_legacy](#a-собственные-аргументы-multidisorder_legacy)
  - [B) Standard direction](#b-standard-direction)
  - [C) Standard payload](#c-standard-payload)
  - [D) Standard fooling](#d-standard-fooling)
  - [E) Standard ipid](#e-standard-ipid)
  - [F) Standard ipfrag](#f-standard-ipfrag)
  - [G) Standard reconstruct](#g-standard-reconstruct)
  - [H) Standard rawsend](#h-standard-rawsend)
- [Порядок отправки сегментов](#порядок-отправки-сегментов)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Сравнительная таблица: multidisorder vs multidisorder_legacy](#сравнительная-таблица-multidisorder-vs-multidisorder_legacy)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен multidisorder_legacy

Новый [[multidisorder]] в zapret2 работает с полным `reasm_data` целиком: он собирает весь многопакетный payload, нарезает его и отправляет все сегменты в обратном порядке за один проход. Это изменяет оригинальную TCP-сегментацию и порядок следования частей по сравнению с nfqws1.

`multidisorder_legacy` нужен для случаев, когда:

1. **Необходима 100%-я совместимость с nfqws1.** Если рабочий профиль из nfqws1 использовал `--dpi-desync=multidisorder`, legacy-вариант воспроизведёт точно такое же поведение
2. **DPI чувствителен к оригинальной сегментации.** Некоторые DPI анализируют размеры TCP-сегментов. Legacy сохраняет оригинальные размеры пакетов, меняя только порядок внутри каждого
3. **Нужен контроль seqovl на уровне пакетов.** В legacy seqovl применяется только к тому пакету, в который попала нормализованная позиция, а не ко всему reasm

---

## Быстрый старт

Минимально (разрез по позиции 2, payload=known, dir=out):

```bash
--lua-desync=multidisorder_legacy
```

Типовой TLS-разрез посередине SNI:

```bash
--payload=tls_client_hello --lua-desync=multidisorder_legacy:pos=1,midsld
```

TLS с seqovl (маркер):

```bash
--payload=tls_client_hello --lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=midsld-1
```

---

## Ключевое отличие: попакетная обработка vs целый reasm

Это **центральное** различие между [[multidisorder]] и `multidisorder_legacy`. Рассмотрим его на примере большого TLS ClientHello, который не влезает в один TCP-сегмент и разбит на 2 пакета.

### Диаграмма: новый multidisorder (весь reasm)

```
Исходные пакеты от ядра:
  Пакет A (500 байт, offset=0):   [AAAAAAAAAAAA...]
  Пакет B (300 байт, offset=500):  [BBBBBBBB...]

reasm_data (800 байт): [AAAAAAAAAAAA...BBBBBBBB...]

Позиции разреза: pos=200,600 (2 разреза -> 3 сегмента)

Разрезанный reasm:
  Часть 1: [AAA..200 байт..]  seq=0    (из пакета A)
  Часть 2: [AAA..400 байт..]  seq=200  (из пакета A + B)
  Часть 3: [BBB..200 байт..]  seq=600  (из пакета B)

Порядок отправки (ОБРАТНЫЙ по всему reasm):
  3 -> 2 -> 1
  [BBB..200] seq=600   <-- первым
  [AAA..400] seq=200   <-- вторым (+ seqovl если задан)
  [AAA..200] seq=0     <-- последним

Оригинальная сегментация (500+300) ПОТЕРЯНА.
```

### Диаграмма: multidisorder_legacy (попакетно)

```
Исходные пакеты от ядра:
  Пакет A (500 байт, offset=0):   [AAAAAAAAAAAA...]
  Пакет B (300 байт, offset=500):  [BBBBBBBB...]

fulldata (800 байт): [AAAAAAAAAAAA...BBBBBBBB...]  (для resolve_pos)
data = dis.payload (текущий пакет)

Позиции разреза: pos=200,600 (2 разреза -> маркеры)

=== Обработка пакета A (data = 500 байт, range_low=1, range_hi=501) ===

  Разрешённые позиции (на fulldata): [200, 600]
  Нормализация по пакету A:
    200 -> в диапазоне [1, 501) -> нормализован: 200 - 1 + 1 = 200  OK
    600 -> НЕ в диапазоне [1, 501) -> УДАЛЁН

  После нормализации: pos = [200]
  Разрезанный пакет A:
    Часть A1: [AAA..200 байт..]
    Часть A2: [AAA..300 байт..]

  Порядок отправки (обратный ВНУТРИ пакета A):
    A2 -> A1
    [AAA..300] seq=200  <-- первым из пакета A (+ seqovl если попал сюда)
    [AAA..200] seq=0    <-- вторым из пакета A

=== Обработка пакета B (data = 300 байт, range_low=501, range_hi=801) ===

  Разрешённые позиции (на fulldata): [200, 600]
  Нормализация по пакету B:
    200 -> НЕ в диапазоне [501, 801) -> УДАЛЁН
    600 -> в диапазоне [501, 801) -> нормализован: 600 - 501 + 1 = 100  OK

  После нормализации: pos = [100]
  Разрезанный пакет B:
    Часть B1: [BBB..100 байт..]
    Часть B2: [BBB..200 байт..]

  Порядок отправки (обратный ВНУТРИ пакета B):
    B2 -> B1
    [BBB..200] seq=600  <-- первым из пакета B
    [BBB..100] seq=500  <-- вторым из пакета B

=== Итоговый порядок на проводе ===

  A2, A1, B2, B1
  [AAA..300] seq=200   (пакет A, обратный)
  [AAA..200] seq=0     (пакет A, обратный)
  [BBB..200] seq=600   (пакет B, обратный)
  [BBB..100] seq=500   (пакет B, обратный)

Оригинальная сегментация (500+300) СОХРАНЕНА.
Обратный порядок ТОЛЬКО внутри каждого пакета.
Между пакетами --- ПРЯМОЙ порядок.
```

---

## Откуда берутся данные

В `multidisorder_legacy` используются **два** источника данных одновременно:

```
data     = desync.dis.payload       -- текущий пакет (для нарезки и отправки)
fulldata = desync.reasm_data        -- полный реассемблированный payload (для resolve_pos)
```

**Почему два источника:**
- `fulldata` нужен для разрешения маркеров (`midsld`, `host` и т.д.), потому что они вычисляются по полному payload (SNI может быть виден только в контексте всего ClientHello)
- `data` --- это то, что реально нарезается и отправляется: именно текущий оригинальный пакет

**Отличие от нового [[multidisorder]]:**

| | multidisorder (новый) | multidisorder_legacy |
|:--|:--|:--|
| data для нарезки | `blob_or_def() or reasm_data or dis.payload` | `dis.payload` (всегда текущий пакет) |
| data для resolve_pos | то же самое (data) | `reasm_data` (fulldata) |
| blob поддержка | Да | **Нет** |

**Следствие:** `multidisorder_legacy` **не поддерживает** аргумент `blob`. Нельзя заменить payload на произвольные данные.

---

## Маркеры позиций (pos)

`pos` --- главный аргумент. Определяет **где** внутри payload будет произведён разрез. Задаётся как строка со списком маркеров через запятую.

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
| `sld` | Первый байт домена второго уровня (SLD). Для `www.example.com` --- это `e` в `example` | `http_req`, `tls_client_hello` |
| `endsld` | Байт, следующий за последним байтом SLD. Для `example.com` --- это `.` после `example` | `http_req`, `tls_client_hello` |
| `midsld` | Середина SLD (самый популярный маркер). Для `example` (7 символов) --- позиция 3-го или 4-го символа | `http_req`, `tls_client_hello` |
| `sniext` | Начало поля данных SNI extension в TLS ClientHello | `tls_client_hello` |
| `extlen` | Поле длины всех TLS extensions | `tls_client_hello` |

### Арифметика маркеров

К любому маркеру можно прибавить (+) или вычесть (-) целое число:

```
midsld+1      -- один байт ПОСЛЕ середины SLD
midsld-1      -- один байт ДО середины SLD
endhost-2     -- два байта до конца hostname
host+3        -- три байта после начала hostname
sniext+1      -- один байт после начала SNI extension data
-1            -- последний байт payload (абсолютный, не относительный)
```

### Нормализация позиций по пакету

Это **ключевая** особенность `multidisorder_legacy`, отсутствующая в новом [[multidisorder]].

Маркеры разрешаются по **fulldata** (весь reasm), но затем нормализуются по диапазону текущего пакета:

```
range_low = (desync.reasm_offset or 0) + 1
range_hi  = range_low + #data
```

Функция `pos_array_normalize(pos, range_low, range_hi)`:
1. Для каждой позиции проверяет: `pos >= range_low AND pos < range_hi`
2. Если позиция в диапазоне --- нормализует: `pos_normalized = pos - range_low + 1`
3. Если позиция вне диапазона --- **удаляет** из массива

```
Пример:
  fulldata = 800 байт
  Маркеры разрешены: pos = [200, 450, 600]

  Пакет A (offset=0, len=500):
    range_low=1, range_hi=501
    200: 200 >= 1 AND 200 < 501 -> OK, normalize: 200
    450: 450 >= 1 AND 450 < 501 -> OK, normalize: 450
    600: 600 >= 1 AND 600 < 501 -> УДАЛЁН
    Результат: [200, 450]

  Пакет B (offset=500, len=300):
    range_low=501, range_hi=801
    200: 200 >= 501? -> НЕТ -> УДАЛЁН
    450: 450 >= 501? -> НЕТ -> УДАЛЁН
    600: 600 >= 501 AND 600 < 801 -> OK, normalize: 600 - 501 + 1 = 100
    Результат: [100]
```

### Важные нюансы pos

- **Нельзя разрезать по позиции 1** (первый байт). Позиция 1 автоматически удаляется из списка (`delete_pos_1`). Это выполняется **после** нормализации
- **Дублирующиеся позиции объединяются.** `pos=5,5,5` = `pos=5`
- **Неразрешимые маркеры пропускаются.** Если `midsld` не разрешается (payload = unknown), он исчезает из списка
- **Позиции сортируются.** Независимо от порядка записи, `pos=100,5,50` обрабатывается как `5,50,100`
- **По умолчанию pos="2".** Если `pos` не задан, разрез по позиции 2
- **Если все позиции вышли за пределы пакета** --- пакет отправляется **как есть** (с применёнными опциями fooling, ipid и т.д.) через `rawsend_payload_segmented`, без разреза

---

## seqovl --- попакетный скрытый фейк

### seqovl --- маркер, а не число

В отличие от [[multisplit]], где `seqovl` принимает только число, в `multidisorder_legacy` (и в новом [[multidisorder]]) `seqovl` является **маркером**. Это значит, что можно написать:

```bash
:seqovl=midsld-1      -- seqovl = (позиция midsld) - 1
:seqovl=host           -- seqovl = позиция host
:seqovl=5              -- seqovl = 5 (число тоже маркер)
```

Маркер seqovl разрешается через `resolve_pos(fulldata, l7payload, seqovl)` --- по **полному** reasm, точно так же, как и позиции разреза.

### Нормализация seqovl по пакету

После разрешения маркера, seqovl нормализуется по диапазону текущего пакета через `pos_normalize(seqovl, range_low, range_hi)`:

```
seqovl_resolved = resolve_pos(fulldata, l7payload, "midsld-1")  -- например, 245
seqovl_normalized = pos_normalize(245, range_low, range_hi)

Для пакета A (range_low=1, range_hi=501):
  245 >= 1 AND 245 < 501 -> OK -> seqovl = 245 - 1 + 1 = 245

Для пакета B (range_low=501, range_hi=801):
  245 >= 501? -> НЕТ -> seqovl = nil (отменён для этого пакета)
```

**Следствие:** seqovl применяется **только к тому пакету**, в диапазон которого попала нормализованная позиция seqovl. Для остальных пакетов seqovl не действует.

### seqovl_pattern

Паттерн заполнения seqovl-области. По умолчанию --- `0x00` (нули). Задаётся как имя blob:

```bash
:seqovl_pattern=0x1603030000         -- inline hex
:seqovl_pattern=my_pattern_blob       -- предзагруженный blob
```

Если `optional` задан и blob `seqovl_pattern` отсутствует --- используется нулевой паттерн (seqovl не отменяется).

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=multidisorder_legacy[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:optional`.

### A) Собственные аргументы multidisorder_legacy

#### `pos`

- **Формат:** `pos=<marker[,marker2,...]>`
- **Тип:** строка со списком маркеров через запятую
- **По умолчанию:** `"2"`
- **Описание:** Точки разреза. Маркеры разрешаются по fulldata (reasm_data), затем нормализуются по диапазону текущего пакета. N маркеров -> до N+1 сегментов **на пакет**
- **Примеры:**
  - `pos=2` --- разрез после 1-го байта (дефолт)
  - `pos=midsld` --- разрез посередине SLD
  - `pos=1,midsld` --- два разреза
  - `pos=host,midsld,endhost-2,-10` --- четыре разреза

#### `seqovl`

- **Формат:** `seqovl=<marker>` (маркер, не просто число!)
- **Тип:** маркер (строка, разрешаемая через `resolve_pos`)
- **По умолчанию:** не задан (нет seqovl)
- **Описание:** Разрешается по fulldata, нормализуется по текущему пакету. Применяется ко 2-му сегменту в оригинальной очередности (предпоследнему отсылаемому). seqovl обязательно должен быть меньше первой позиции разреза (в нормализованном виде), иначе отменяется
- **Примеры:**
  - `seqovl=5` --- 5 байт фейка
  - `seqovl=midsld-1` --- seqovl привязан к позиции midsld
  - `seqovl=host` --- seqovl привязан к позиции host

#### `seqovl_pattern`

- **Формат:** `seqovl_pattern=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** один байт `0x00`, повторяемый до длины seqovl
- **Описание:** Данные для заполнения seqovl-области. Blob повторяется функцией `pattern()` до нужного размера
- **Поведение с `optional`:** если `optional` задан и blob отсутствует --- используется нулевой паттерн

#### `optional`

- **Формат:** `optional` (флаг, без значения)
- **Описание:** Мягкий режим. Если задан `seqovl_pattern=...` и blob отсутствует --- используется нулевой паттерн (seqovl не отменяется)

**Внимание:** `blob` и `nodrop` **не поддерживаются** в `multidisorder_legacy`. Это ключевое отличие от нового [[multidisorder]].

---

### B) Standard direction

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `dir` | `in`, `out`, `any` | `out` |

Фильтр по направлению пакета. `multidisorder_legacy` по умолчанию работает только с исходящими (`out`).

- `dir=out` --- только исходящие (от клиента к серверу)
- `dir=in` --- только входящие (от сервера к клиенту)
- `dir=any` --- оба направления

При первом вызове с указанным `dir` функция делает `direction_cutoff_opposite` --- отсекает себя от противоположного направления.

---

### C) Standard payload

| Параметр | Значения | По умолчанию |
|:---------|:---------|:-------------|
| `payload` | список типов через запятую | `known` |

Фильтр по типу payload на уровне Lua. Это **дополнительный** фильтр к `--payload=...` на уровне профиля.

- `payload=known` --- только распознанные протоколы (`http_req`, `tls_client_hello`, `quic_initial` и т.д.)
- `payload=all` --- любой payload, включая `unknown`
- `payload=tls_client_hello,http_req` --- конкретные типы
- `payload=~unknown` --- инверсия: всё кроме unknown

---

### D) Standard fooling

Модификации L3/L4 заголовков. Применяются **ко всем** отправляемым сегментам.

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

**Заметка:** Fooling применяется ко **ВСЕМ** сегментам (и реальным). Если задать `tcp_ack=-66000`, сервер отбросит все сегменты. Fooling в multidisorder_legacy имеет смысл только для специфических вещей (`tcp_ts_up`, `ip_id`, IPv6 extension headers).

---

### E) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | --- |
| `ip_id=zero` | Нулевые IP ID | --- |
| `ip_id=none` | Не менять IP ID | --- |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения | --- |

---

### F) Standard ipfrag

IP-фрагментация **поверх** TCP-сегментации. Каждый TCP-сегмент дополнительно фрагментируется на уровне IP.

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ipfrag[=func]` | Включить IP-фрагментацию. Если без значения --- `ipfrag2` | --- |
| `ipfrag_disorder` | Отправить IP-фрагменты в обратном порядке | --- |
| `ipfrag_pos_tcp=N` | Позиция фрагментации TCP (кратно 8) | `32` |
| `ipfrag_pos_udp=N` | Позиция фрагментации UDP (кратно 8) | `8` |
| `ipfrag_next=N` | IPv6: next protocol во 2-м фрагменте | --- |

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

`multidisorder_legacy` использует общую функцию `multidisorder_send`, которая отправляет сегменты **в обратном порядке** (от последнего к первому). Но поскольку legacy обрабатывает каждый пакет отдельно, обратный порядок действует **только внутри одного пакета**.

### Пример: однопакетный payload

```
Payload (600 байт), pos=100,300,450:

Разрезанный payload:
  Часть 1: [0..99]    100 байт
  Часть 2: [100..299] 200 байт
  Часть 3: [300..449] 150 байт
  Часть 4: [450..599] 150 байт

Порядок отправки (ОБРАТНЫЙ):
  Часть 4: [450..599] seq=450   <-- первой
  Часть 3: [300..449] seq=300   <-- второй
  Часть 2: [100..299] seq=100   <-- третьей (+ seqovl если задан)
  Часть 1: [0..99]    seq=0     <-- последней
```

### Пример: многопакетный payload (2 пакета)

```
Пакет A (400 байт, offset=0), pos=150
Пакет B (300 байт, offset=400), pos=550 (нормализованный: 150)

=== Обработка пакета A ===
  Часть A1: [0..149]   150 байт
  Часть A2: [150..399]  250 байт
  Отправка: A2 (seq=150), A1 (seq=0)

=== Обработка пакета B ===
  Часть B1: [0..149]   150 байт  (соответствует offset 400..549)
  Часть B2: [150..299]  150 байт  (соответствует offset 550..699)
  Отправка: B2 (seq=550), B1 (seq=400)

Итог на проводе: A2, A1, B2, B1
Между пакетами A и B --- ПРЯМОЙ порядок.
Внутри каждого --- ОБРАТНЫЙ.
```

### Пример с seqovl

```
Payload (600 байт, один пакет), pos=100,300, seqovl=80:

seqovl применяется к сегменту i=1 (второй в оригинальной очередности = предпоследний отсылаемый):

Порядок отправки:
  Часть 3: [300..599]              seq=300   len=300
  Часть 2: [PATTERN(79)][100..299] seq=21    len=279  <-- seqovl=80, ovl=79
  Часть 1: [0..99]                 seq=0     len=100  <-- переписывает паттерн

Часть 1 отправляется последней и переписывает ложные данные из seqovl_pattern
в буфере TCP-стека сервера.
```

---

## Псевдокод алгоритма

```lua
function multidisorder_legacy(ctx, desync)
    -- 1. Проверка: только TCP
    if not desync.dis.tcp then
        if not desync.dis.icmp then instance_cutoff_shim() end
        return
    end

    -- 2. Cutoff противоположного направления
    direction_cutoff_opposite(ctx, desync)

    -- 3. Источники данных
    local data = desync.dis.payload           -- текущий пакет (для нарезки)
    local fulldata = desync.reasm_data        -- весь reasm (для resolve_pos)

    -- 4. Проверки: данные не пусты, направление OK, payload OK
    if #data > 0 and direction_check() and payload_check() then

        -- 5. Вычисление диапазона текущего пакета
        local range_low = (desync.reasm_offset or 0) + 1
        local range_hi = range_low + #data

        -- 6. Разрешение маркеров по FULLDATA
        local pos = resolve_multi_pos(fulldata, l7payload, pos_arg or "2")

        -- 7. Нормализация позиций по диапазону текущего пакета
        pos_array_normalize(pos, range_low, range_hi)
        delete_pos_1(pos)  -- нельзя резать по позиции 1

        if #pos > 0 then
            -- 8. Разрешение и нормализация seqovl (если задан)
            local seqovl = nil
            if desync.arg.seqovl then
                seqovl = resolve_pos(fulldata, l7payload, desync.arg.seqovl)
                if seqovl then
                    seqovl = pos_normalize(seqovl, range_low, range_hi)
                    -- seqovl может стать nil если вне диапазона пакета
                end
            end

            -- 9. Отправка через общую функцию (обратный порядок)
            return multidisorder_send(desync, data, seqovl, pos)
            -- multidisorder_send: for i = #pos, 0, -1 do ... end
            -- seqovl применяется к сегменту i=1 (2-й по оригинальной очередности)
        else
            -- 10. Нет позиций в этом пакете -> отправить как есть
            if rawsend_payload_segmented(desync) then
                return VERDICT_DROP
            end
        end
    end
end
```

Обратите внимание: в отличие от нового [[multidisorder]], здесь **нет** `replay_first()` / `replay_drop()` / `replay_drop_set()`. Функция вызывается для **каждого** пакета replay и обрабатывает его самостоятельно. Это и есть попакетная обработка.

---

## Сравнительная таблица: multidisorder vs multidisorder_legacy

| Аспект | [[multidisorder]] (новый) | `multidisorder_legacy` |
|:-------|:--------------------------|:-----------------------|
| Совместимость с nfqws1 | Частичная (порядок может отличаться) | **Полная** |
| Источник данных для нарезки | `blob_or_def() or reasm_data or dis.payload` | `dis.payload` (текущий пакет) |
| Источник данных для resolve_pos | то же (data) | `reasm_data` (fulldata) |
| Оригинальная сегментация | **Не сохраняется** | **Сохраняется** |
| Нормализация позиций | Нет | Да, по диапазону каждого пакета |
| Порядок сегментов | Обратный по **всему** reasm | Обратный **только внутри** каждого пакета |
| Между пакетами | Обратный (как часть единого обратного порядка) | **Прямой** (порядок пакетов сохраняется) |
| seqovl | Применяется к целому reasm | **Нормализуется** по текущему пакету |
| seqovl тип | Маркер | Маркер |
| blob | **Да** | **Нет** |
| nodrop | **Да** | **Нет** |
| optional | Для blob и seqovl_pattern | Только для seqovl_pattern |
| replay_first/replay_drop | Да (обрабатывает только первый replay) | Нет (обрабатывает каждый пакет) |
| Пакет без позиций разреза | Не применимо (весь reasm обрабатывается) | Отправляется как есть с применёнными опциями |

---

## Нюансы и подводные камни

### 1. Работает только с TCP

Если текущий пакет не TCP (UDP, ICMP и т.д.), `multidisorder_legacy` делает `instance_cutoff_shim` --- отключает себя для этого потока навсегда. Исключение: related ICMP не вызывает cutoff.

### 2. Нет blob и nodrop

В отличие от нового [[multidisorder]], `multidisorder_legacy` **не поддерживает** аргументы `blob` и `nodrop`. Попытка использовать их не вызовет ошибку (Lua просто проигнорирует неизвестные аргументы), но и эффекта не будет:
- `blob` --- данные всегда берутся из `dis.payload`
- `nodrop` --- оригинальный пакет всегда дропается при успешной отправке (вердикт `VERDICT_DROP` из `multidisorder_send` или из `rawsend_payload_segmented`)

### 3. seqovl может не попасть ни в один пакет

Если маркер seqovl разрешается в позицию, которая оказывается на стыке двух пакетов и не попадает точно ни в один диапазон, seqovl будет отменён для всех пакетов. Например:

```
fulldata = 800 байт
Пакет A: offset=0, len=400   -> range [1, 401)
Пакет B: offset=400, len=400 -> range [401, 801)
seqovl разрешился в позицию 401

Пакет A: 401 >= 1 AND 401 < 401? -> НЕТ (граница не включена)
Пакет B: 401 >= 401 AND 401 < 801? -> ДА -> нормализованный seqovl = 1

Но seqovl=1 означает ovl=0 (seqovl - 1 = 0 в multidisorder_send),
поэтому фактически seqovl не применится.
```

### 4. Позиция 1 удаляется после нормализации

`delete_pos_1(pos)` вызывается **после** `pos_array_normalize`. Это значит, что позиция, которая нормализуется в 1 (например, `range_low` сама по себе), будет удалена. Это правильное поведение --- нельзя разрезать на самом первом байте пакета.

### 5. Пакет без позиций отправляется как есть

Если после нормализации в пакете не осталось ни одной позиции разреза, пакет **не пропускается**, а отправляется как есть через `rawsend_payload_segmented(desync)`. Это значит, что к нему всё равно будут применены fooling, ipid, ipfrag и прочие опции.

### 6. Fooling применяется ко ВСЕМ сегментам

Как и в [[multisplit]] / [[multidisorder]], fooling в `multidisorder_legacy` идёт на **все** сегменты (включая реальные). Не путайте с [[fakedsplit]] / [[fakeddisorder]], где fooling идёт только на фейки.

### 7. Для однопакетных payload разницы нет

Если payload помещается в один TCP-сегмент (что характерно для большинства HTTP-запросов и многих TLS ClientHello без post-quantum), поведение `multidisorder_legacy` и нового [[multidisorder]] **идентично**. Разница проявляется только при многопакетных payload.

### 8. Порядок вызова: каждый пакет --- отдельный вызов

В отличие от нового [[multidisorder]], который обрабатывает весь reasm за один `replay_first()` и дропает последующие replay через `replay_drop()`, legacy-функция вызывается для **каждого** пакета replay. Каждый вызов обрабатывает свой пакет независимо.

### 9. seqovl может применяться к разным пакетам

Поскольку seqovl нормализуется попакетно, в теории seqovl может применяться к разным пакетам в разных сценариях. Но на практике маркер seqovl разрешается в одну конкретную позицию и попадает ровно в один пакет.

---

## Миграция с nfqws1

### Когда использовать multidisorder_legacy

| Сценарий | Рекомендация |
|:---------|:-------------|
| Миграция рабочего профиля nfqws1 с `--dpi-desync=multidisorder` | Используйте `multidisorder_legacy` для 100%-й совместимости |
| Новый профиль, однопакетный payload | Нет разницы, можно использовать [[multidisorder]] |
| Новый профиль, многопакетный payload | Попробуйте оба варианта --- DPI может реагировать по-разному |
| Нужен blob или nodrop | Используйте [[multidisorder]] (legacy не поддерживает) |

### Соответствие параметров

| nfqws1 | nfqws2 (multidisorder_legacy) |
|:-------|:-------------------------------|
| `--dpi-desync=multidisorder` | `--lua-desync=multidisorder_legacy` |
| `--dpi-desync-split-pos=midsld` | `:pos=midsld` |
| `--dpi-desync-split-pos=1,midsld` | `:pos=1,midsld` |
| `--dpi-desync-split-seqovl=5` | `:seqovl=5` |
| `--dpi-desync-split-seqovl-pattern=0x1603030000` | `:seqovl_pattern=0x1603030000` |
| `--dpi-desync-any-protocol` | Не нужно; или `payload=all` в инстансе |

### Пример полной миграции

```bash
# nfqws1:
nfqws --dpi-desync=fake,multidisorder \
  --dpi-desync-fooling=md5sig \
  --dpi-desync-split-pos=1,midsld \
  --dpi-desync-split-seqovl=5 \
  --dpi-desync-split-seqovl-pattern=0x1603030000

# nfqws2 (эквивалент с multidisorder_legacy):
nfqws2 \
  --payload=tls_client_hello \
    --lua-desync=fake:blob=fake_default_tls:tcp_md5 \
  --payload=http_req \
    --lua-desync=fake:blob=fake_default_http:tcp_md5 \
  --payload=tls_client_hello,http_req \
    --lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

### Миграция с нового multidisorder на legacy

Если у вас уже есть профиль с новым [[multidisorder]] и вы хотите попробовать legacy-вариант:

```bash
# Было (новый multidisorder):
--lua-desync=multidisorder:pos=1,midsld:seqovl=midsld-1:blob=fake_ch:nodrop

# Стало (legacy) --- убираем blob и nodrop:
--lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=midsld-1
```

**Внимание:** `blob` и `nodrop` потеряны при миграции. Если они необходимы --- legacy не подходит.

---

## Практические примеры

### 1. Минимальный (дефолт: pos=2, dir=out, payload=known)

```bash
--lua-desync=multidisorder_legacy
```

Разрезает payload после 1-го байта, отправляет в обратном порядке: сначала основная часть, потом 1-й байт.

### 2. TLS: разрез посередине SNI

```bash
--payload=tls_client_hello --lua-desync=multidisorder_legacy:pos=midsld
```

SNI разрезан пополам. Сначала отправляется вторая половина (с конца SNI), затем первая (с начала ClientHello до середины SNI). DPI получает вторую половину раньше и не может собрать полный hostname.

### 3. TLS: два разреза с seqovl-маркером

```bash
--payload=tls_client_hello --lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=midsld-1
```

3 сегмента в обратном порядке. seqovl привязан к позиции `midsld-1` --- фейковые данные перекрывают область SNI. Последний отправленный сегмент (1-й байт) переписывает буфер сокета реальными данными.

### 4. TLS: seqovl с паттерном маскировки под TLS record

```bash
--payload=tls_client_hello \
  --lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=5:seqovl_pattern=0x1603030000
```

5 байт seqovl-области заполнены `0x16 0x03 0x03 0x00 0x00` --- DPI может принять это за начало TLS record.

### 5. HTTP: разрезы вокруг hostname

```bash
--payload=http_req --lua-desync=multidisorder_legacy:pos=host,midsld,endhost
```

4 сегмента: отправляются в обратном порядке (после hostname -> вторая половина hostname -> первая половина -> до hostname). DPI видит фрагменты в "неправильном" порядке.

### 6. Комбинация: fake + multidisorder_legacy

```bash
--payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5 \
  --lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=midsld-1:seqovl_pattern=0x1603030000
```

Сначала отправляется фейковый TLS ClientHello (с MD5 fooling --- сервер отбросит), затем реальный payload нарезан и отправлен в обратном порядке с seqovl.

### 7. Боевой пример для YouTube (TLS)

```bash
--filter-tcp=443 --hostlist=youtube.txt \
  --lua-desync=fake:blob=fake_default_tls:repeats=11:tcp_md5 \
  --lua-desync=multidisorder_legacy:pos=1,midsld
```

11 фейков подряд + реальный payload разрезан и отправлен в обратном порядке. Полная совместимость с поведением nfqws1.

### 8. Множественные разрезы с арифметикой маркеров

```bash
--payload=tls_client_hello \
  --lua-desync=multidisorder_legacy:pos=sniext+1,host,midsld,endhost-2,-10
```

5 маркеров -> до 6 сегментов (в зависимости от того, сколько маркеров попадут в текущий пакет после нормализации). Все 6 сегментов отправляются в обратном порядке внутри каждого пакета.

### 9. С IP-фрагментацией

```bash
--payload=tls_client_hello \
  --lua-desync=multidisorder_legacy:pos=1,midsld:ipfrag:ipfrag_disorder:ipfrag_pos_tcp=32
```

Каждый TCP-сегмент дополнительно фрагментируется на IP-уровне в обратном порядке. Двойной disorder: TCP-сегменты в обратном порядке внутри пакета + IP-фрагменты в обратном порядке.

### 10. С TCP timestamp и IP ID

```bash
--payload=tls_client_hello \
  --lua-desync=multidisorder_legacy:pos=1,midsld:tcp_ts_up:ip_id=seq:ip_id_conn
```

TCP timestamp поднят в начало заголовка, IP ID --- последовательные в рамках соединения.

### 11. Payload=all (обработка unknown протоколов)

```bash
--lua-desync=multidisorder_legacy:payload=all:pos=2
```

Обрабатывает **любой** payload, включая нераспознанные. Маркеры вроде `midsld` не разрешатся для unknown, но абсолютные позиции (как `2`) сработают.

### 12. С optional для защиты seqovl_pattern

```bash
--payload=tls_client_hello \
  --lua-desync=multidisorder_legacy:pos=1,midsld:seqovl=midsld-1:seqovl_pattern=my_blob:optional
```

Если blob `my_blob` не существует --- seqovl всё равно работает, но заполняется нулями вместо паттерна. Без `optional` отсутствие blob вызвало бы ошибку.

---

> **Источники:** `lua/zapret-antidpi.lua:530-684`, `lua/zapret-lib.lua`, `docs/manual.md:4098-4121` из репозитория zapret2.

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
  - oob
  - urgent
aliases:
  - oob
---

# `oob` -- TCP Out-of-Band десинхронизация (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:1084`
**nfqws1 эквивалент:** отсутствует (новая функция zapret2)
**tpws аналог:** `--split-pos=.. --oob` (близкий, но не идентичный механизм)
**Сигнатура:** `function oob(ctx, desync)`

`oob` -- функция TCP-десинхронизации через механизм Out-of-Band (Urgent) данных. Она перехватывает TCP handshake с самого начала (SYN), сдвигает sequence на 1 байт влево, а затем вставляет 1 байт OOB (помеченный флагом `TH_URG`) в первый исходящий payload. TCP-стек получателя выбрасывает OOB-байт из потока, но DPI может этого не делать -- и тогда DPI видит payload со вставленным посторонним байтом, что ломает распознавание сигнатур.

После отработки функция уходит в [[instance_cutoff]] по обоим направлениям.

Родственные функции: [[multisplit]] (TCP-сегментация), [[fakedsplit]] (с фейками), [[fake]] (фейковые пакеты), [[syndata]] (данные в SYN), [[tcpseg]] (диапазон).

---

## Оглавление

- [Зачем нужен oob](#зачем-нужен-oob)
- [Быстрый старт](#быстрый-старт)
- [Принцип работы](#принцип-работы)
  - [Фаза 1: перехват SYN](#фаза-1-перехват-syn)
  - [Фаза 2: вставка OOB-байта](#фаза-2-вставка-oob-байта)
  - [Фаза 3: cutoff](#фаза-3-cutoff)
  - [Обработка входящих пакетов](#обработка-входящих-пакетов)
- [Два стандарта th_urp](#два-стандарта-th_urp)
- [Режимы urp](#режимы-urp)
  - [urp=b -- начало (по умолчанию)](#urpb--начало-по-умолчанию)
  - [urp=e -- конец](#urpe--конец)
  - [urp=маркер -- произвольная позиция](#urpмаркер--произвольная-позиция)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы oob](#a-собственные-аргументы-oob)
  - [B) Standard fooling](#b-standard-fooling)
  - [C) Standard ipid](#c-standard-ipid)
  - [D) Standard ipfrag](#d-standard-ipfrag)
  - [E) Standard reconstruct](#e-standard-reconstruct)
  - [F) Standard rawsend](#f-standard-rawsend)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Поведение при reasm (многопакетный payload)](#поведение-при-reasm-многопакетный-payload)
- [Сравнение с tpws --oob](#сравнение-с-tpws---oob)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен oob

DPI анализирует TCP-поток, ищет сигнатуры (hostname в HTTP, SNI в TLS). Если вставить в поток лишний байт, помеченный как "urgent" (Out-of-Band), происходит следующее:

1. **Сервер (TCP-стек ОС):** выбрасывает OOB-байт из потока. Приложение получает чистые данные без вставки
2. **DPI:** может не понимать OOB-механизм и анализировать поток вместе со вставленным байтом. Если байт вставлен посередине hostname/SNI, сигнатура разрушается

**Ключевое отличие от сегментации:** oob не разрезает данные на части -- он вставляет **лишний байт**, который принимающая ОС удаляет, а DPI -- нет.

**Ключевое отличие от фейков:** oob не отправляет отдельных фейковых пакетов -- вставка происходит внутри единого легитимного потока. Это делает oob труднодетектируемым.

---

## Быстрый старт

Минимально (urp=b по умолчанию, OOB-байт = `0x00`):

```bash
--in-range=-s1 --lua-desync=oob
```

С маркером по середине SLD:

```bash
--in-range=-s1 --lua-desync=oob:urp=midsld
```

С конкретным OOB-символом:

```bash
--in-range=-s1 --lua-desync=oob:char=X
```

**Важно:** `--in-range=-s1` обязателен для HTTP/TLS (протоколов, где сервер ждёт запроса клиента). Без него oob не увидит SYN-пакет и не активируется.

---

## Принцип работы

### Фаза 1: перехват SYN

`oob` должен начать работу с самого первого пакета TCP-соединения -- SYN. Функция проверяет флаг `TH_SYN` и запоминает, что соединение перехвачено с начала.

На этапе SYN (pos=0) и первого ACK (pos=1) функция **уменьшает sequence на 1**:

```
Оригинальный SYN:
  th_seq = 1000

После oob:
  th_seq = 999    (уменьшен на 1)
```

Это "резервирует" место для будущего OOB-байта. Сервер запоминает начальный sequence = 999, и ожидает данные начиная с позиции 1000 (999 + 1 за SYN).

### Фаза 2: вставка OOB-байта

Когда приходит первый исходящий пакет с данными (pos >= 1, payload непуст), oob:

1. Берёт payload (или reasm, если многопакетный)
2. Определяет OOB-байт: `char=` или `byte=` или `0x00` по умолчанию
3. Определяет позицию вставки по `urp`
4. Вставляет OOB-байт в payload по этой позиции
5. Устанавливает флаг `TH_URG` и значение `th_urp`
6. Отправляет модифицированный пакет через `rawsend_dissect_segmented`
7. Дропает оригинальный пакет (`VERDICT_DROP`)

**Визуализация вставки (urp=b, th_urp=0):**

```
Оригинальный payload:
  [G][E][T][ ][/][p][a][t][h]...

После вставки OOB-байта (0x00) в позицию 1:
  [OOB][G][E][T][ ][/][p][a][t][h]...
   ^
   th_urp=0, TH_URG=1

Что видит сервер (TCP-стек удаляет OOB):
  [G][E][T][ ][/][p][a][t][h]...   <-- оригинал

Что видит DPI (не удаляет OOB):
  [0x00][G][E][T][ ][/][p][a][t][h]...   <-- "GET" сдвинут, сигнатура сломана
```

**Визуализация вставки (urp=midsld, TLS SNI):**

```
Payload (TLS ClientHello), SNI = "example.com", midsld указывает на "m" в "example":

Оригинал:
  ...[e][x][a][m][p][l][e][.][c][o][m]...

После вставки OOB (0x00) в позицию midsld:
  ...[e][x][a][OOB][m][p][l][e][.][c][o][m]...
              ^
              th_urp = (позиция midsld + 1 по RFC)

DPI видит: "exa\x00mple.com" -- нет совпадения с "example.com"
Сервер видит: "example.com" -- OOB-байт удалён
```

### Фаза 3: cutoff

После успешной отправки OOB-пакета (если это не replay) функция выполняет `instance_cutoff_shim` -- отключает себя от обоих направлений данного соединения. Дальнейшие пакеты проходят без модификации.

При replay (многопакетный payload): все replay-части дропаются, cutoff выполняется после последней части.

### Обработка входящих пакетов

Для входящих пакетов (от сервера) oob **увеличивает th_ack на 1**, компенсируя сдвиг sequence:

```
Входящий от сервера:
  th_ack = 999   (сервер подтверждает sequence, сдвинутый на 1)

oob модифицирует:
  th_ack = 1000  (возвращает ожидаемое значение для клиента)
```

Это необходимо, чтобы клиентская ОС не запуталась -- она ожидает ack на основе своего оригинального sequence.

---

## Два стандарта th_urp

Существуют два RFC-интерпретации поля `th_urp` (Urgent Pointer) в TCP-заголовке:

| Стандарт | th_urp указывает на | Поддержка |
|:---------|:--------------------|:----------|
| RFC 793 (оригинальный) | Сам OOB-байт (0-based) | Старые реализации |
| RFC 1122 (уточнённый) | Байт, **следующий** за OOB (1-based) | Современные ОС (Linux, Windows, BSD) |

Из-за этого расхождения значение `th_urp=0` невалидно по одному из стандартов, но может работать на практике.

В коде `oob`:
- Для `urp=b`: `th_urp` устанавливается в `0` (согласно RFC 793)
- Для `urp=e` и маркеров: `th_urp` устанавливается как `позиция + 1` (согласно RFC 1122)

---

## Режимы urp

### urp=b -- начало (по умолчанию)

OOB-байт вставляется **перед первым байтом** payload. `th_urp = 0`.

```
th_urp = 0
Payload: [OOB][оригинальные данные...]
```

**Ограничение:** работает **только на Linux-серверах**. Windows и BSD серверы ломаются при `th_urp=0`, поскольку интерпретируют его как невалидный по RFC 1122.

Это наиболее эффективный режим для обхода DPI, т.к. OOB-байт вставляется в самое начало, ломая распознавание протокола (HTTP-метод, TLS record header).

### urp=e -- конец

OOB-байт вставляется **после последнего байта** payload. `th_urp = len(payload) + 1`.

```
th_urp = len+1
Payload: [оригинальные данные...][OOB]
```

**Как правило бесполезен для обхода DPI:** DPI получает весь оригинальный payload целиком, OOB-байт идёт после него и не мешает анализу.

### urp=маркер -- произвольная позиция

`urp` может быть любым [[маркером|маркеры]], поддерживаемым функцией `resolve_pos`. OOB-байт вставляется в позицию, куда разрешается маркер. `th_urp = позиция + 1` (по RFC 1122).

Поддерживаемые маркеры (те же, что в [[multisplit]]):

| Маркер | Описание | Для каких payload |
|:-------|:---------|:------------------|
| `host` | Первый байт имени хоста | `http_req`, `tls_client_hello` |
| `endhost` | Байт после последнего байта hostname | `http_req`, `tls_client_hello` |
| `sld` | Первый байт домена второго уровня | `http_req`, `tls_client_hello` |
| `endsld` | Байт после SLD | `http_req`, `tls_client_hello` |
| `midsld` | Середина SLD | `http_req`, `tls_client_hello` |
| `sniext` | Начало данных SNI extension | `tls_client_hello` |
| `method` | Начало HTTP-метода | `http_req` |
| Числа | Абсолютная позиция (1-based) | Любой |

Арифметика маркеров поддерживается: `midsld+1`, `host-1`, `sniext+2` и т.д.

**Пример:** `urp=midsld` -- OOB-байт вставляется посередине SLD. DPI видит домен с лишним байтом посередине.

**Если маркер не разрешается** (например, `midsld` для unknown payload), функция логирует ошибку и выполняет `instance_cutoff`.

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=oob[:arg1[=val1][:arg2[=val2]]...]
```

**Важно:** у oob **нет** фильтров `dir` и `payload`. Функция не может быть отфильтрована по payload, поскольку после начала модификации TCP handshake (сдвиг sequence) соскок невозможен -- иначе поедут sequence numbers. Направление обрабатывается автоматически: исходящие -- вставка OOB, входящие -- коррекция ack.

### A) Собственные аргументы oob

#### `char`

- **Формат:** `char=<символ>`
- **Тип:** строка длиной 1 байт
- **По умолчанию:** `0x00`
- **Описание:** Символ, используемый как OOB-байт. Должен быть ровно 1 байт
- **Приоритет:** `char` проверяется первым, затем `byte`, затем `0x00`
- **Примеры:**
  - `char=X` -- OOB-байт = ASCII 'X'
  - `char=A` -- OOB-байт = ASCII 'A'

#### `byte`

- **Формат:** `byte=<число 0..255>`
- **Тип:** числовое значение байта
- **По умолчанию:** не задан
- **Описание:** Числовое значение OOB-байта. Используется, если `char` не задан
- **Примеры:**
  - `byte=0` -- OOB-байт = 0x00
  - `byte=255` -- OOB-байт = 0xFF
  - `byte=65` -- OOB-байт = 0x41 (ASCII 'A')

#### `urp`

- **Формат:** `urp=<маркер>` или `urp=b` или `urp=e`
- **Тип:** строка -- специальное значение (`b`, `e`) или [[маркер|маркеры]]
- **По умолчанию:** `b`
- **Описание:** Позиция, куда будет вставлен OOB-байт
  - `b` -- начало payload (`th_urp=0`). Только для Linux-серверов
  - `e` -- конец payload (`th_urp=len+1`). Бесполезно для обхода DPI
  - маркер -- произвольная позиция. `th_urp = позиция + 1` (RFC 1122)
- **Примеры:**
  - `urp=b` -- перед первым байтом (дефолт)
  - `urp=e` -- после последнего байта
  - `urp=midsld` -- середина SLD
  - `urp=host` -- начало hostname
  - `urp=2` -- после первого байта payload
  - `urp=sniext+1` -- один байт после начала SNI extension data

---

### B) Standard fooling

Модификации L3/L4 заголовков. Применяются к отправляемому OOB-пакету.

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

**Заметка:** fooling в oob имеет ограниченный смысл. В отличие от [[fakedsplit]], где fooling применяется к фейковым пакетам (чтобы сервер их отбросил), в oob fooling применяется к **реальному** OOB-пакету. Если сервер отбросит этот пакет из-за fooling -- данные не дойдут. Используйте fooling осторожно (например, `tcp_ts_up`, IPv6 extension headers).

---

### C) Standard ipid

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ip_id=seq` | Последовательные IP ID | `seq` |
| `ip_id=rnd` | Случайные IP ID | -- |
| `ip_id=zero` | Нулевые IP ID | -- |
| `ip_id=none` | Не менять IP ID | -- |
| `ip_id_conn` | Сквозная нумерация IP ID в рамках соединения (требует tracking) | -- |

`ip_id` применяется к каждому отправляемому сегменту (при автосегментации по MSS).

---

### D) Standard ipfrag

IP-фрагментация. Каждый отправляемый TCP-сегмент дополнительно фрагментируется на уровне IP.

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ipfrag[=func]` | Включить IP-фрагментацию. Если без значения -- `ipfrag2` | -- |
| `ipfrag_disorder` | Отправить IP-фрагменты в обратном порядке | -- |
| `ipfrag_pos_tcp=N` | Позиция фрагментации TCP (кратно 8) | `32` |
| `ipfrag_next=N` | IPv6: next protocol во 2-м фрагменте | -- |

---

### E) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета. Сервер отбросит такой пакет |

**Предупреждение:** `badsum` в oob сделает OOB-пакет невалидным -- сервер его отбросит, OOB-байт не будет вставлен, а sequence останутся сдвинутыми. TCP-соединение будет сломано. Не используйте `badsum` в oob в боевых профилях.

---

### F) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить каждый сегмент N раз (идентичные повторы) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

---

## Псевдокод алгоритма

```lua
function oob(ctx, desync)
    -- 1. Требуется conntrack
    if not desync.track then return end

    -- 2. Только TCP (ICMP пропускается, остальное -- cutoff)
    if not desync.dis.tcp then
        if not desync.dis.icmp then instance_cutoff_shim() end
        return
    end

    -- 3. Проверка: начали с SYN?
    if not lua_state[key.."_syn"] then
        if th_flags ~= TH_SYN then
            -- Соединение началось без нас -- невозможно вставить OOB
            DLOG("must be applied since the very beginning - SYN packet")
            instance_cutoff_shim()
            return
        end
        lua_state[key.."_syn"] = true  -- запомнить, что видели SYN
    end

    if desync.outgoing then
        -- === ИСХОДЯЩИЕ ПАКЕТЫ ===
        local pos = pos_get(desync, 's', false)  -- relative seq position

        if pos <= 1 then
            -- SYN (pos=0) или первый ACK (pos=1): уменьшить seq на 1
            desync.dis.tcp.th_seq = th_seq - 1
        end

        if pos == 0 then
            -- SYN: просто модифицировать seq и пропустить
            return VERDICT_MODIFY

        elseif pos == 1 then
            -- Первый пакет с данными
            local data = desync.reasm_data or desync.dis.payload

            if #data == 0 then
                -- Пустой ACK: модифицировать seq и пропустить
                return VERDICT_MODIFY
            else
                -- Определить OOB-байт (char > byte > 0x00)
                local oob_byte = desync.arg.char
                    or (desync.arg.byte and bu8(desync.arg.byte))
                    or "\x00"
                assert(#oob_byte == 1)

                -- Создать копию диссекта
                local dis_oob = deepcopy(desync.dis)

                -- Определить urp позицию
                if not urp or urp == 'b' then
                    -- Начало: вставить перед 1-м байтом
                    insert_pos = 1
                    dis_oob.tcp.th_urp = 0
                elseif urp == 'e' then
                    -- Конец: вставить после последнего байта
                    insert_pos = #data + 1
                    dis_oob.tcp.th_urp = insert_pos
                else
                    -- Маркер: разрешить позицию
                    insert_pos = resolve_pos(data, l7payload, urp)
                    if not insert_pos then
                        DLOG("cannot resolve urp marker")
                        instance_cutoff_shim()
                        return
                    end
                    dis_oob.tcp.th_urp = insert_pos  -- +1 по RFC
                end

                -- Вставить OOB-байт
                dis_oob.payload = data[1..urp-1] .. oob_byte .. data[urp..]
                -- Установить TH_URG
                dis_oob.tcp.th_flags |= TH_URG

                -- Отправить с автосегментацией по MSS
                rawsend_dissect_segmented(desync, dis_oob)

                -- Cutoff (если не replay)
                if not desync.replay then
                    instance_cutoff_shim()  -- оба направления
                end

                return VERDICT_DROP
            end

        else
            -- pos > 1: replay-часть -- дропнуть
            if desync.replay then
                if desync.replay_piece_last then
                    instance_cutoff_shim()
                end
                return VERDICT_DROP
            end
            instance_cutoff_shim()
        end

    else
        -- === ВХОДЯЩИЕ ПАКЕТЫ ===
        local pos = pos_get(desync, 's', true)  -- reverse pos
        if pos > 1 then
            -- Неожиданная позиция -- cutoff
            instance_cutoff_shim()
            return
        end
        -- Увеличить ack на 1 (компенсация сдвига seq)
        desync.dis.tcp.th_ack = th_ack + 1
        return VERDICT_MODIFY
    end
end
```

---

## Поведение при reasm (многопакетный payload)

Если payload не помещается в один TCP-сегмент (например, большой TLS ClientHello с post-quantum Kyber), zapret собирает все части в `reasm_data`. Функция `oob` при этом:

1. **Берёт весь `reasm_data`** (а не отдельные части)
2. **Вставляет OOB-байт** в позицию `urp` внутри полного reasm
3. **Отправляет через `rawsend_dissect_segmented`**, которая автоматически разбивает на сегменты по MSS

При сегментации `rawsend_dissect_segmented` корректно обрабатывает OOB:

```
Сегментация по MSS с OOB:

Полный payload с OOB (3000 байт, MSS=1460):
  [данные_до_urp][OOB][данные_после_urp]

Сегмент 1 (1460 байт): th_urp нормализуется, TH_URG если urp попал сюда
Сегмент 2 (1460 байт): TH_URG снимается если urp не попал сюда
Сегмент 3 (80 байт):   аналогично
```

В каждом сегменте:
- Если `urp` попадает в диапазон `[pos, pos+len)` -- устанавливается `TH_URG`, `th_urp` нормализуется по смещению сегмента (`th_urp = urp - pos + 1`)
- Если `urp` не попадает в сегмент -- `TH_URG` снимается, `th_urp = 0`

Replay-части (2-я и далее) дропаются. Cutoff выполняется после последней replay-части.

---

## Сравнение с tpws --oob

| Аспект | `oob` (nfqws2) | `--split-pos=.. --oob` (tpws) |
|:-------|:----------------|:------------------------------|
| Уровень работы | Пакетный (L3/L4, raw sockets) | Потоковый (L7, прокси) |
| Способ вставки | Модификация raw TCP-пакетов с `TH_URG` | Использование `MSG_OOB` в `send()` |
| Позиция OOB | Любая (маркер, `b`, `e`) | Привязана к `--split-pos` |
| Сегментация + OOB | **Невозможна** (несовместима с multisplit) | Возможна (split + oob в одном вызове) |
| Модификация handshake | Да (сдвиг seq на SYN) | Нет (ОС делает handshake) |
| Контроль th_urp | Полный (можно задать `b`, `e`, маркер) | Нет (ОС решает) |
| Контроль OOB-байта | Да (`char`, `byte`) | Ограниченный |
| Работа с reasm | Да (весь reasm, MSS-сегментация) | Нет (потоковый режим) |
| NAT совместимость | Да | Да |
| Необходимость --in-range | Да (`--in-range=-s1`) | Нет (прокси) |

**Вывод:** `oob` в nfqws2 даёт больше контроля над позицией и содержимым OOB-байта, но не может быть скомбинирован с TCP-сегментацией. tpws позволяет комбинировать split + OOB, но без тонкого контроля th_urp.

---

## Нюансы и подводные камни

### 1. Обязательно --in-range=-s1

Для HTTP и TLS (протоколов, где сервер ждёт запроса клиента) необходим `--in-range=-s1`. Это разрешает перехват входящего SYN-ACK от сервера, что нужно для корректной работы oob (коррекция ack). Без `--in-range=-s1` oob не увидит SYN и откажется работать.

На Windows `--wf-tcp-in` для HTTP/TLS **не нужен** -- достаточно автоматически перехватываемых SYN-пакетов.

### 2. Для server-first протоколов нужен --wf-tcp-in (Windows)

Для протоколов, где сервер отправляет данные **до** первого запроса клиента (например, SMTP, FTP, SSH), требуется разрешить **все** входящие пакеты до первого исходящего с данными. На Windows это означает обязательный `--wf-tcp-in`.

### 3. urp=b работает только на Linux-серверах

Значение `th_urp=0` невалидно по RFC 1122. Linux-серверы его обрабатывают корректно (удаляют OOB-байт), но Windows и BSD серверы **ломаются** -- соединение может разорваться или данные будут повреждены. Используйте `urp=b` только если уверены, что целевой сервер работает на Linux.

### 4. Нет фильтрации по payload

`oob` **не может** быть отфильтрован по типу payload (`payload=tls_client_hello` и т.д.). Причина: модификация начинается на SYN (до появления любого payload). После сдвига sequence "соскочить" невозможно -- если oob не вставит байт, sequence будут сдвинуты, и TCP-соединение сломается.

Фильтрация возможна только на уровне профиля (`--filter-tcp`, `--hostlist` через `--ipcache-hostname` и т.д.).

### 5. Нет фильтрации по направлению (dir)

Стандартный аргумент `dir` отсутствует. Функция автоматически обрабатывает оба направления: исходящие -- вставка OOB и сдвиг seq, входящие -- коррекция ack.

### 6. Несовместимость с multisplit, fakedsplit и другими функциями отправки payload

`oob` **не может работать** совместно с [[multisplit]], [[multidisorder]], [[fakedsplit]], [[fakeddisorder]] и другими функциями, которые пересылают текущий payload. Причина: эти функции отправляют **копии** payload, но без OOB-модификации. В результате:

- oob вставит OOB-байт и сдвинет sequence
- multisplit отправит свои сегменты **без** OOB и **без** учёта сдвига
- Сервер получит дублирующиеся данные с рассогласованными sequence

Получить эффект "разбить на сегменты и всунуть OOB" (как в tpws) через комбинацию oob + multisplit **невозможно**.

### 7. Длящаяся десинхронизация и переключение профилей

`oob` -- **длящаяся десинхронизация**: между SYN (сдвиг seq) и первым payload (вставка OOB) проходит несколько пакетов. Если за это время происходит переключение профиля (например, `--ipcache-hostname` разрешил домен и переключил на другой профиль), новый профиль **должен также содержать oob**. Иначе:

- Старый профиль сдвинул seq на SYN
- Новый профиль не знает об этом и не вставит OOB
- TCP-соединение сломано (sequence рассогласованы)

**Решение:** дублировать `oob` во всех профилях, которые могут получить управление в процессе handshake.

### 8. Требуется conntrack (tracking)

`oob` использует `desync.track` для хранения состояния (видели ли SYN, текущая позиция). Без tracking функция немедленно возвращает `nil`.

### 9. Соединение должно быть перехвачено с SYN

Если oob получает управление **после** SYN (например, после перескока профиля или при подключении к уже установленному соединению), она немедленно выполняет cutoff. Специальный флаг `lua_state[key.."_syn"]` гарантирует, что oob видела SYN самого первого пакета.

### 10. Фильтрация по хостлистам

Фильтрация через `--hostlist` возможна **только** при использовании `--ipcache-hostname`. Если в кэше хоста ещё нет, и профиль получает управление не с начала соединения -- срабатывает cutoff (см. п.9).

### 11. OOB-байт ровно 1

OOB-байт **обязательно** 1 байт. Попытка задать `char` длиной != 1 вызовет Lua error.

### 12. Пустой ACK не ломает поток

Если первый исходящий пакет с данными оказался пустым ACK (пустой payload), oob просто уменьшает seq и возвращает `VERDICT_MODIFY`. Вставка OOB произойдёт при появлении следующего непустого пакета.

---

## Практические примеры

### 1. Минимальный: urp=b (по умолчанию), OOB=0x00

```bash
--in-range=-s1 --lua-desync=oob
```

Вставляет `0x00` перед первым байтом payload. Работает только на Linux-серверах.

### 2. Позиция urp=0 (нулевая, 0-based = первый байт)

```bash
--in-range=-s1 --lua-desync=oob:urp=0
```

Маркер `0` разрешается в абсолютную позицию. `th_urp = 0 + 1 = 1` (RFC 1122). Безопаснее `urp=b` для не-Linux серверов.

### 3. Позиция urp=2 (после первого байта)

```bash
--in-range=-s1 --lua-desync=oob:urp=2
```

OOB-байт вставляется после первого байта payload. `th_urp = 3`. Для HTTP: `G[OOB]ET /...` -- DPI не распознает метод.

### 4. Середина SLD (самый популярный вариант)

```bash
--in-range=-s1 --lua-desync=oob:urp=midsld
```

Для `example.com`: OOB вставляется посередине `example`. DPI видит `exa[OOB]mple.com`.

### 5. Произвольный OOB-символ

```bash
--in-range=-s1 --lua-desync=oob:char=Z:urp=midsld
```

OOB-байт = ASCII 'Z' вместо `0x00`.

### 6. OOB-байт по числовому значению

```bash
--in-range=-s1 --lua-desync=oob:byte=255:urp=midsld
```

OOB-байт = `0xFF`.

### 7. Для HTTPS (TLS) с фильтром по порту

```bash
--filter-tcp=443 --in-range=-s1 --lua-desync=oob:urp=midsld
```

Применяется только к HTTPS-соединениям.

### 8. Для HTTP и HTTPS одновременно

```bash
--filter-tcp=80,443 --in-range=-s1 --lua-desync=oob:urp=midsld
```

### 9. С хостлистом и ipcache

```bash
--filter-tcp=443 --hostlist=blocked.txt --ipcache-hostname \
  --in-range=-s1 --lua-desync=oob:urp=midsld
```

Фильтрация по хостлисту. `--ipcache-hostname` обязателен для работы хостлиста с oob.

### 10. Комбинация: fake + oob (в разных профилях)

```bash
# Профиль 1: фейк для TLS
--filter-tcp=443 --payload=tls_client_hello \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5

# Профиль 2: oob
--filter-tcp=443 --in-range=-s1 \
  --lua-desync=oob:urp=midsld
```

**Важно:** fake и oob могут быть в разных профилях, но oob **несовместим** с multisplit/fakedsplit в рамках одного потока.

### 11. Перебор позиций urp (как в blockcheck2)

```bash
# blockcheck2 перебирает: b, 0, 2, midsld
--in-range=-s1 --lua-desync=oob:urp=b
--in-range=-s1 --lua-desync=oob:urp=0
--in-range=-s1 --lua-desync=oob:urp=2
--in-range=-s1 --lua-desync=oob:urp=midsld
```

Это паттерн из `blockcheck2.d/standard/17-oob.sh` -- попробовать разные позиции urp для нахождения рабочей.

### 12. С IP-фрагментацией

```bash
--in-range=-s1 --lua-desync=oob:urp=midsld:ipfrag:ipfrag_pos_tcp=32
```

OOB-пакет дополнительно фрагментируется на IP-уровне.

### 13. С IPv6 extension headers

```bash
--in-range=-s1 --lua-desync=oob:urp=midsld:ip6_hopbyhop
```

Добавляет hop-by-hop extension header к OOB-пакету.

### 14. Дублирование oob при переключении профилей

```bash
# Профиль "по умолчанию" (до разрешения hostname)
--filter-tcp=443 --in-range=-s1 \
  --lua-desync=oob:urp=midsld

# Профиль "для заблокированных" (после ipcache-hostname)
--filter-tcp=443 --hostlist=blocked.txt --ipcache-hostname --in-range=-s1 \
  --lua-desync=oob:urp=midsld
```

oob дублируется в оба профиля, чтобы переключение не сломало TCP.

### 15. OOB в позиции host (начало hostname)

```bash
--in-range=-s1 --lua-desync=oob:urp=host:byte=0
```

Вставляет нулевой байт прямо перед hostname. DPI видит `\x00example.com` вместо `example.com`.

---

> **Источники:** `lua/zapret-antidpi.lua:1084-1176`, `lua/zapret-lib.lua:1148-1192`, `docs/manual.md:4276-4309`, `docs/manual.en.md:4095-4127`, `blockcheck2.d/standard/17-oob.sh` из репозитория zapret2.

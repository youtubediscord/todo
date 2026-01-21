---
date: 2026-01-21
tags:
  - zapret
  - zapret2
  - nfqws2
  - lua
  - lua-desync
  - antidpi
  - tcp
aliases:
  - multisplit
---

# `multisplit` (zapret / nfqws2)

Документация по Lua-функции `multisplit(ctx, desync)` из `lua/zapret-antidpi.lua`.

`multisplit` режет текущий payload (или `reasm`, или заданный `blob`) на несколько TCP-сегментов по списку “маркеров” `pos=...` и отправляет их **в исходном порядке** (с 1-го по последний). После успешной отправки обычно выносит `VERDICT_DROP`, чтобы оригинальный пакет “как есть” не ушёл (если не задан `nodrop`).

## Быстрый старт

Минимально:

```bash
--lua-desync=multisplit
```

Часто используемо (TLS ClientHello):

```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=5
```

Часто используемо (HTTP request):

```bash
--payload=http_req --lua-desync=multisplit:pos=method+2
```

## Откуда берутся данные, которые режем (важно)

Внутри `multisplit` выбирается `data` так:

1) если задан `blob=NAME` и blob существует → режется blob  
2) иначе если есть `desync.reasm_data` → режется весь reasm (актуально при multi-packet запросах)  
3) иначе режется `desync.dis.payload`

Следствие: маркеры `pos=...` и `seqovl` применяются именно к тем данным, которые реально выбраны (blob / reasm / payload).

## Формат аргументов `--lua-desync`

Общий формат:

```text
--lua-desync=multisplit:arg1[=val1]:arg2[=val2]:flag3:flag4...
```

- Все `val` приходят в Lua как строки.
- Если `=val` не указан, значение считается пустой строкой `""` (в Lua это “truthy”), поэтому флаги пишутся как `:optional`, `:nodrop`, `:tcp_ts_up`, `:ip_id_conn` и т.д.

## Маркеры `pos` (как писать точки разреза)

`pos` — это список маркеров через запятую. Маркеры бывают:

- **Абсолютные**: `100` (позиция внутри payload), `-10` (10 байт “с конца”), `-1` (последний байт)
- **Относительные (по протоколу)**: `method`, `host`, `endhost`, `sld`, `endsld`, `midsld`, `sniext`, `extlen`
- Можно задавать смещения: `midsld+1`, `endhost-2`, `method+2`

Важно:

- маркеры работают только для payload’ов, где эти логические элементы обнаружимы (HTTP/TLS и т.п.)
- `multisplit` не позволит резать “в самый первый байт” (позиция начала удаляется как невалидная точка разреза)

## Полный список аргументов `multisplit` и что они принимают

Ниже перечислено всё, что реально читает/использует `multisplit` и код отправки сегментов.

### A) Собственные аргументы `multisplit`

#### `pos`
- **Формат:** `pos=<marker[,marker2,...]>`
- **Тип:** строка со списком маркеров
- **Дефолт:** `"2"`
- **Примеры:** `pos=method+2`, `pos=host,midsld,endhost-2`, `pos=1,host,midsld+1,-10`

#### `seqovl`
- **Формат:** `seqovl=N`
- **Тип:** число `N>0` (только число; маркеры не поддерживаются)
- **Действие:** применяется только к *первой* отправляемой части: слева добавляется `N` байт `seqovl_pattern`, а TCP `seq` уменьшается на `N`
- **Примеры:** `seqovl=5`, `seqovl=13`

#### `seqovl_pattern`
- **Формат:** `seqovl_pattern=<blobName>`
- **Тип:** имя blob-переменной (см. “blob” ниже)
- **Дефолт:** один байт `0x00`, который повторяется до `seqovl`
- **Особенность с `optional`:**
  - если `optional` задан и blob `seqovl_pattern` отсутствует → паттерн берётся нулевой (операция не отменяется)

#### `blob`
- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной
- **Действие:** заменить текущий payload/reasm на указанный blob и резать/слать его

#### `optional`
- **Формат:** `optional` (флаг)
- **Действие:**
  - если задан `blob=...` и blob отсутствует → `multisplit` **ничего не делает** (skip)
  - если задан `seqovl_pattern=...` и blob отсутствует → используется нулевой паттерн

#### `nodrop`
- **Формат:** `nodrop` (флаг)
- **Действие:** после успешной отправки сегментов не выносить `VERDICT_DROP` (вернуть `VERDICT_PASS`)
- **Использование:** полезно для отладки, но в реальных профилях чаще нужно именно `DROP`, чтобы не ушёл оригинал “как есть”

---

### B) Standard args, которые тоже реально влияют на `multisplit`

#### 1) `dir` (standard direction)
- **Формат:** `dir=in|out|any`
- **Дефолт в большинстве anti-dpi функций:** `out`
- **Смысл:** фильтр по направлению внутри Lua (доп. предохранитель)

#### 2) `payload` (standard payload)
- **Формат:** `payload=type1[,type2,...]` или `payload=all` или `payload=known`
- **Инверсия:** `payload=~type1[,type2,...]`
- **Дефолт:** `known`

#### 3) Fooling (standard fooling) — модификации L3/L4 заголовков
Эти поля задаются прямо в `:...` и применяются перед отправкой каждого сегмента:

- `ip_ttl=N`, `ip6_ttl=N`
- `ip_autottl=delta,min-max`, `ip6_autottl=delta,min-max` (пример: `ip_autottl=-2,40-64`)
- `ip6_hopbyhop[=HEX]`, `ip6_hopbyhop2[=HEX]`, `ip6_destopt[=HEX]`, `ip6_destopt2[=HEX]`, `ip6_routing[=HEX]`, `ip6_ah[=HEX]`
- `tcp_seq=N`, `tcp_ack=N`, `tcp_ts=N`
- `tcp_md5[=HEX]`
- `tcp_flags_set=FIN,SYN,...`, `tcp_flags_unset=...`
- `tcp_ts_up` (флаг)
- `tcp_nop_del` (флаг)
- `fool=<luaFunctionName>`

#### 4) IPID (standard ipid)
- `ip_id=seq|rnd|zero|none`
- `ip_id_conn` (флаг)

Примечание: `ip_id` применяется на *каждый* отправляемый сегмент (и на под-сегменты при MSS-сегментации).

#### 5) Reconstruct (standard reconstruct)
- `badsum` (флаг) — портит L4 checksum при реконструкции raw-пакета

#### 6) Rawsend (standard rawsend)
- `repeats=N` (число)
- `ifout=<iface>` (строка)
- `fwmark=N` (число, Linux)

#### 7) IP fragmentation (standard ipfrag)
Включается только если указать `ipfrag` (даже без значения):

- `ipfrag[=frag_function]` — если значение пустое, используется `ipfrag2`
- `ipfrag_disorder` (флаг) — слать IP-фрагменты с последнего к первому
- `ipfrag_pos_udp=N` (кратно 8; дефолт 8) — только для `ipfrag2`
- `ipfrag_pos_tcp=N` (кратно 8; дефолт 32) — только для `ipfrag2`
- `ipfrag_next=N` — только для `ipfrag2` (ipv6 “next protocol” 2-го фрагмента)

Примечание: `multisplit` работает только с TCP, поэтому `ipfrag_pos_udp` здесь практического смысла не имеет.

## Нюансы поведения (то, что обычно ломает ожидания)

## Как это устроено в коде (псевдокод)

См. `lua/zapret-antidpi.lua:458` (`multisplit`) и `lua/zapret-lib.lua:1084` (отправка/сегментация).

Упрощённо:

```lua
data = blob_or_def(blob) or reasm_data or dis.payload
pos = resolve_multi_pos(data, l7payload, pos_list_or_default)
delete_pos_1(pos)

for i = 0 .. #pos do
  part = data[pos_start .. pos_end]
  if i == 0 and seqovl > 0 then
    part = pattern(seqovl_pattern, seqovl) .. part
  end
  rawsend_payload_segmented(part, seq_offset = (pos_start-1) - seqovl)
end

return nodrop and PASS or DROP
```

### 1) Работает только для TCP
Если текущий пакет не TCP — функция сама отключит себя (cutoff) для этого потока и выйдет.

### 2) Срабатывает только на первом `replay`-куске
Если включён механизм replay/reasm и пакет “переигрывается”, то реальная нарезка/отсылка происходит только на первой части. Дальше, если отправка была успешной, следующие replay-части будут дропаться (если не `nodrop`).

### 3) “Автосегментация по MSS” может добавить ещё сегментов
Даже если вы разрезали на 2–3 части, каждый кусок дополнительно режется по MSS, если превышает допустимый размер.

### 4) `nodrop` почти всегда делает “дубликаты”
С `nodrop` вы отправляете “нарезанное”, но пропускаете и оригинал. В реальном боевом профиле это часто лишний трафик и может ухудшить ситуацию.

## Примеры (12 штук, разные флаги и настройки)

Ниже примеры именно синтаксиса `--lua-desync=...`. В реальном профиле обычно ещё есть `--filter-*`, `--payload` на уровне профиля, `--in-range/--out-range` и т.д.

### 1) Самый простой (дефолт `pos=2`, `dir=out`, `payload=known`)
```bash
--lua-desync=multisplit
```
Что делает: режет текущий payload начиная со 2-го байта (то есть фактически на 2 части) и шлёт по порядку.

### 2) HTTP: разрез после первых 2 символов метода
```bash
--payload=http_req --lua-desync=multisplit:pos=method+2
```
Идея: многие DPI “узнают” HTTP по началу строки, поэтому ломаем первые байты запроса.

### 3) HTTP: несколько точек вокруг `Host`
```bash
--payload=http_req --lua-desync=multisplit:pos=host,midsld,endhost-2
```
Идея: сломать домен/хост и дать DPI неоднозначную картину.

### 4) TLS: базовый разрез + `seqovl`
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=5
```
Идея: сделать “левый хвост” за окном (сервер игнорирует), DPI может проглотить.

### 5) TLS: `seqovl` + кастомный паттерн через blob
```bash
--blob=pat:0xDEADBEEF --payload=tls_client_hello --lua-desync=multisplit:pos=1:seqovl=8:seqovl_pattern=pat
```
Паттерн повторяется до нужной длины `seqovl`.

### 6) Резать не реальный payload, а свой blob (фейковая полезная нагрузка)
```bash
--blob=mydata:@payload.bin --lua-desync=multisplit:blob=mydata:pos=10,100,-20
```
Идея: использовать `multisplit` как “отправщик произвольных данных” по уже установленным L3/L4 заголовкам.

### 7) `optional`: тихо пропустить, если blob отсутствует
```bash
--lua-desync=multisplit:blob=maybe_missing:optional:pos=2
```
Если blob не загружен, функция не делает ничего (без ошибок и без DROP).

### 8) `nodrop`: отладочный режим “не блокировать оригинал”
```bash
--payload=http_req --lua-desync=multisplit:pos=method+2:nodrop
```
Оригинальный пакет тоже уйдёт, поэтому это чаще для проверки/экспериментов.

### 9) Добавить “фулинг”: TTL + TCP MD5 + подъем timestamp опции
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:ip_ttl=64:tcp_md5:tcp_ts_up
```
`tcp_md5` без значения → значение пустое, и будет использован дефолтный MD5-опцион (внутренняя логика).

### 10) Управление IPv4 `ip_id` + сохранение последовательности между пакетами
```bash
--payload=http_req --lua-desync=multisplit:pos=host:ip_id=seq:ip_id_conn
```
Важно: `ip_id_conn` работает только при наличии tracking (`desync.track`).

### 11) Повторы отправки (каждый сегмент 2 раза)
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:repeats=2
```
Иногда полезно, но это бинарно идентичные повторы (без “умного” изменения полей).

### 12) Сверху включить IP-фрагментацию `ipfrag2` (по умолчанию) и отправку фрагментов в обратном порядке
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:ipfrag:ipfrag_disorder:ipfrag_pos_tcp=32
```
Здесь `ipfrag` без `=...` означает пустую строку → включается `ipfrag2`.

### 13) Включить IP-фрагментацию `ipfrag2` дефолтами (без disorder)
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:ipfrag
```

### 14) Настроить позицию IP-фрагментации TCP для `ipfrag2`
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:ipfrag:ipfrag_pos_tcp=64
```
Важно: `ipfrag_pos_tcp` должен быть кратен 8.

### 15) IPv6: задать `ipfrag_next` (next header во 2-м фрагменте) для `ipfrag2`
```bash
--payload=tls_client_hello --lua-desync=multisplit:pos=1:ipfrag:ipfrag_next=17
```
`ipfrag_next` имеет смысл только для IPv6 (и только для `ipfrag2`); значение — числовой код next header.

## Практические рекомендации

- Для **HTTP** чаще начинают с `pos=method+2` или разрезов вокруг `host/midsld/endhost`.
- Для **TLS ClientHello** часто работают разрезы около `pos=1` и `seqovl=...` (если серверная ОС не ломает прием).
- Если используете `blob=...`, всегда подумайте про `optional`, чтобы профиль не падал/не ломался при отсутствии blob.
- `nodrop` включайте только осознанно (иначе получите “оригинал + нарезка”).

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
---

# `multidisorder` (zapret / nfqws2)

Документация по Lua-функции `multidisorder(ctx, desync)` из `lua/zapret-antidpi.lua`.

`multidisorder` режет текущий payload (или `reasm`, или заданный `blob`) на несколько TCP-сегментов по списку маркеров `pos=...`, но отправляет сегменты **в обратном порядке**: с последнего к первому. После успешной отправки обычно выносит `VERDICT_DROP` (если не задан `nodrop`).

Ключевое отличие от `multisplit`: другой порядок отправки + `seqovl` здесь — **маркер**, а не число, и применяется к “предпоследнему отправляемому” сегменту для эффекта переписывания буфера приёмника (на практике зависит от ОС и стека TCP на принимающей стороне).

## Быстрый старт

Минимально:

```bash
--lua-desync=multidisorder
```

TLS ClientHello (частая форма):

```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:seqovl=midsld-1
```

## Откуда берутся данные, которые режем

Алгоритм выбора данных такой же, как в `multisplit`:

1) `blob=NAME` (если задан и существует)  
2) иначе `desync.reasm_data` (если есть)  
3) иначе `desync.dis.payload`

Важно: `pos=...` и `seqovl=...` резолвятся по выбранным данным (`data`) и по текущему `desync.l7payload` (тип протокола).

## Формат аргументов `--lua-desync`

```text
--lua-desync=multidisorder:arg1[=val1]:arg2[=val2]:flag3...
```

Если `=val` не указан, значение считается пустой строкой `""` (Lua считает её true), поэтому флаги пишутся как `:optional`, `:nodrop`, `:tcp_ts_up`, `:ipfrag` и т.п.

## Маркеры `pos` и `seqovl` (как писать)

### Маркеры для `pos`
`pos` — список маркеров через запятую. Маркеры такие же, как в `multisplit`:

- числа: `100`, `-10`, `-1`
- относительные: `method`, `host`, `endhost`, `sld`, `endsld`, `midsld`, `sniext`, `extlen`
- со смещениями: `midsld+1`, `endhost-2`

### Маркер для `seqovl`
В `multidisorder` `seqovl` — **маркер**, который резолвится через `resolve_pos(...)`:

- **примеры:** `seqovl=midsld-1`, `seqovl=host+3`, `seqovl=10`
- если маркер не резолвится → `seqovl` отменяется (просто не применяется)
- если `seqovl` оказывается **не меньше первой точки разреза**, то он тоже будет отменён (защитная проверка)

## Полный список аргументов `multidisorder` и что они принимают

### A) Собственные аргументы `multidisorder`

#### `pos`
- **Формат:** `pos=<marker[,marker2,...]>`
- **Тип:** строка со списком маркеров
- **Дефолт:** `"2"`
- **Смысл:** точки разреза; сегменты отправляются в обратном порядке

#### `seqovl`
- **Формат:** `seqovl=<marker>`
- **Тип:** маркер (строка), например `midsld-1`
- **Действие:** применяется к сегменту “2-му по оригинальному порядку” (который отправляется предпоследним в обратной очереди)
- **Правило валидности:** итоговый `seqovl` должен быть меньше первой точки разреза, иначе отмена

#### `seqovl_pattern`
- **Формат:** `seqovl_pattern=<blobName>`
- **Тип:** blob-имя
- **Дефолт:** `0x00`
- **С `optional` и отсутствием blob:** используется нулевой паттерн

#### `blob`
- **Формат:** `blob=<blobName>`
- **Тип:** blob-имя
- **Смысл:** заменить данные (payload/reasm) на blob и работать с ним

#### `optional`
- **Формат:** `optional` (флаг)
- **Действие:**
  - если задан `blob=...` и blob отсутствует → функция ничего не делает
  - если отсутствует `seqovl_pattern` → используется нулевой паттерн

#### `nodrop`
- **Формат:** `nodrop` (флаг)
- **Смысл:** не возвращать `VERDICT_DROP` после успешной отправки

---

### B) Standard args, которые влияют на `multidisorder`

Полностью те же группы, что и у `multisplit`:

- `dir=in|out|any` (дефолт `out`)
- `payload=...` (дефолт `known`, поддерживает `~` инверсию)
- fooling: `ip_ttl`, `ip_autottl`, `tcp_md5`, `tcp_ts_up`, и т.д.
- ipid: `ip_id=seq|rnd|zero|none`, `ip_id_conn`
- reconstruct: `badsum`
- rawsend: `repeats`, `ifout`, `fwmark`
- ipfrag: `ipfrag[=func]`, `ipfrag_disorder`, `ipfrag_pos_tcp`, `ipfrag_next`, ...

Примечание: `multidisorder` работает только с TCP, поэтому `ipfrag_pos_udp` здесь практического смысла не имеет.

## Нюансы поведения (важные для понимания результатов)

## Как это устроено в коде (псевдокод)

См. `lua/zapret-antidpi.lua:571` (`multidisorder`) и `lua/zapret-lib.lua:1084` (отправка/сегментация).

Ключевой момент: отправка идёт **в обратной очереди**, а `seqovl` применяется только к сегменту с индексом `i==1` (2-й по оригиналу).

```lua
data = blob_or_def(blob) or reasm_data or dis.payload
pos = resolve_multi_pos(data, l7payload, pos_list_or_default)
delete_pos_1(pos)
seqovl = resolve_pos(data, l7payload, seqovl_marker) -- может быть nil

for i = #pos .. 0 step -1 do
  part = data[pos_start .. pos_end]
  ovl = 0
  if i == 1 and seqovl and seqovl > 0 and seqovl < pos[1] then
    ovl = seqovl - 1
    part = pattern(seqovl_pattern, ovl) .. part
  end
  rawsend_payload_segmented(part, seq_offset = (pos_start-1) - ovl)
end

return nodrop and PASS or DROP
```

### 1) TCP-only
Если пакет не TCP, функция отключит себя (cutoff) и вернёт управление.

### 2) SNI/HTTP маркеры зависят от распознавания payload
Если `desync.l7payload` не соответствует ожидаемому типу (например, “unknown”), относительные маркеры могут не резолвиться.

### 3) Срабатывание только на первом replay-куске + DROP остальных
При reasm/replay реальная “нарезка всего reasm” делается только один раз, затем последующие replay-части могут дропаться (если отправка была успешной и не `nodrop`).

### 4) MSS/сегментация и IP-фрагментация могут добавиться поверх
Каждый “логический” сегмент может быть дополнительно порезан по MSS, а затем (если включено `ipfrag`) — ещё и фрагментирован на уровне IP.

## Примеры (12 штук, разные флаги и настройки)

### 1) Самый простой (дефолты: `pos=2`, `dir=out`, `payload=known`)
```bash
--lua-desync=multidisorder
```

### 2) TLS: разрез по 1 байту + по середине домена SLD, seqovl “чуть левее midsld”
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:seqovl=midsld-1
```

### 3) TLS: несколько точек разреза
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,sniext+1,extlen,-10
```

### 4) HTTP: разрезы вокруг `Host`, в обратной очереди
```bash
--payload=http_req --lua-desync=multidisorder:pos=host,midsld,endhost-2
```

### 5) `seqovl` как абсолютный маркер-число
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=20,60:seqovl=19
```
Здесь `seqovl` — маркер “19”, он резолвится как позиция 19.

### 6) Демонстрация “отмены seqovl” (если `seqovl` не меньше первой точки разреза)
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=20,60:seqovl=20
```
`seqovl` будет отменён защитной проверкой, и отправка пойдёт без seqovl.

### 7) Заменить данные на blob и резать blob
```bash
--blob=mydata:@payload.bin --lua-desync=multidisorder:blob=mydata:pos=10,100,-20
```

### 8) `optional`: не делать ничего, если blob отсутствует
```bash
--lua-desync=multidisorder:blob=maybe_missing:optional:pos=2
```

### 9) `nodrop`: оставить оригинал (чаще для отладки)
```bash
--payload=http_req --lua-desync=multidisorder:pos=host:endhost:nodrop
```

### 10) Добавить “фулинг”: TTL + TCP MD5 + перенос timestamp наверх
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:ip_ttl=64:tcp_md5:tcp_ts_up
```

### 11) Управление ip_id (последовательный ipid с сохранением между пакетами)
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:ip_id=seq:ip_id_conn
```

### 12) Включить IP-фрагментацию `ipfrag2` и отправку IP-фрагментов в обратном порядке
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:ipfrag:ipfrag_disorder:ipfrag_pos_tcp=32
```

### 13) Включить IP-фрагментацию `ipfrag2` дефолтами (без disorder)
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:ipfrag
```

### 14) Настроить позицию IP-фрагментации TCP для `ipfrag2`
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:ipfrag:ipfrag_pos_tcp=64
```

### 15) IPv6: задать `ipfrag_next` (next header во 2-м фрагменте) для `ipfrag2`
```bash
--payload=tls_client_hello --lua-desync=multidisorder:pos=1,midsld:ipfrag:ipfrag_next=17
```

## Практические рекомендации

- `multidisorder` часто полезнее на TLS-пейлоадах, чем на произвольных TCP-данных, потому что маркеры (`sniext`, `midsld`) понятны и стабильны.
- `seqovl` в режиме disorder чувствителен к стеку TCP на сервере (и поведению ОС), поэтому его лучше проверять на целевом ресурсе.
- `nodrop` включайте только если вы намеренно хотите “оригинал + disordered сегменты”.

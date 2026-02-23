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
  - syndata
  - tls_mod
aliases:
  - syndata
---

# `syndata` --- payload в TCP SYN (zapret2 / nfqws2)

**Файл:** `lua/zapret-antidpi.lua:385`
**nfqws1 эквивалент:** `--dpi-desync=syndata`
**Сигнатура:** `function syndata(ctx, desync)`

`syndata` --- стратегия "нулевой фазы" в zapret2. Она добавляет произвольный payload в TCP SYN-пакет, применяет модификации (fooling, tls_mod) и отправляет его **вместо** оригинального SYN. Оригинальный пакет дропается (`VERDICT_DROP`). Работает **до** установления TCP-соединения --- на этапе, когда клиент ещё только отправляет SYN.

Родственные/сопутствующие функции: [[fake]] (фейковый пакет после SYN), [[multisplit]] (TCP-сегментация), [[wssize]] (управление размером окна), [[multidisorder]], [[fakedsplit]], [[fakeddisorder]].

---

## Оглавление

- [Зачем нужен syndata](#зачем-нужен-syndata)
- [Быстрый старт](#быстрый-старт)
- [Принцип работы](#принцип-работы)
  - [Что такое SYN с payload](#что-такое-syn-с-payload)
  - [Нулевая фаза](#нулевая-фаза)
  - [Логика обработки пакетов](#логика-обработки-пакетов)
- [Полный список аргументов](#полный-список-аргументов)
  - [A) Собственные аргументы syndata](#a-собственные-аргументы-syndata)
  - [B) Standard fooling](#b-standard-fooling)
  - [C) Standard reconstruct](#c-standard-reconstruct)
  - [D) Standard rawsend](#d-standard-rawsend)
  - [E) Standard ipfrag](#e-standard-ipfrag)
- [tls_mod --- модификация TLS в syndata](#tls_mod--модификация-tls-в-syndata)
  - [Работающие модификации](#работающие-модификации)
  - [dupsid и padencap --- молчаливое игнорирование](#dupsid-и-padencap--молчаливое-игнорирование)
  - [Почему dupsid и padencap не работают](#почему-dupsid-и-padencap-не-работают)
- [Псевдокод алгоритма](#псевдокод-алгоритма)
- [Отличия от fake](#отличия-от-fake)
- [Работа с хостлистами](#работа-с-хостлистами)
- [Комбинирование с другими функциями](#комбинирование-с-другими-функциями)
- [Нюансы и подводные камни](#нюансы-и-подводные-камни)
- [Миграция с nfqws1](#миграция-с-nfqws1)
- [Практические примеры](#практические-примеры)

---

## Зачем нужен syndata

Некоторые DPI начинают анализировать соединение уже с первого пакета --- с SYN. Они запоминают IP и порт клиента, ждут данные и сопоставляют их с сигнатурами. `syndata` атакует этот механизм на самом раннем этапе:

1. **Ложные данные в SYN:** DPI видит SYN-пакет с payload (например, фейковый TLS ClientHello) и может принять его за начало реального соединения
2. **Сбой трекинга:** если DPI привязывает сессию к содержимому первого пакета, подменный SYN может направить трекинг по ложному пути
3. **Обход до handshake:** воздействие происходит до TCP handshake --- DPI ещё не видел реальных данных приложения

**Важно:** TCP SYN с payload --- это валидная TCP-операция (RFC 793 разрешает данные в SYN, хотя многие стеки их игнорируют до завершения handshake). Сервер примет SYN, но payload из него обычно отбросит --- DPI же может попытаться его проанализировать.

---

## Быстрый старт

Минимально (16 нулевых байт в SYN):

```bash
--lua-desync=syndata
```

С TLS-фейком:

```bash
--lua-desync=syndata:blob=fake_default_tls
```

С TLS-фейком и модификацией SNI:

```bash
--lua-desync=syndata:blob=fake_default_tls:tls_mod=rnd,rndsni
```

Типовая комбинация (wssize + syndata + multisplit):

```bash
--lua-desync=wssize:wsize=1:scale=6 \
--lua-desync=syndata \
--lua-desync=multisplit:pos=midsld
```

---

## Принцип работы

### Что такое SYN с payload

Обычный TCP SYN-пакет не содержит данных --- только заголовки с флагом SYN. `syndata` берёт этот пакет, добавляет в него payload (указанный в `blob` или 16 нулевых байт по умолчанию), применяет модификации и отправляет через raw socket вместо оригинала.

```
Обычный SYN:
  [IP Header][TCP Header (SYN)]

SYN после syndata:
  [IP Header][TCP Header (SYN)][PAYLOAD (blob или 16x 0x00)]
```

Сервер получит SYN с данными. Большинство TCP-стеков:
- Завершат handshake (SYN-ACK), **проигнорировав** payload в SYN
- Payload будет отброшен, потому что соединение ещё не установлено

DPI же может:
- Проанализировать payload из SYN как начало потока данных
- Записать ложную информацию о соединении (фейковый SNI, фейковый HTTP Host)
- Пропустить реальные данные, которые пойдут позже

### Нулевая фаза

`syndata` --- **стратегия нулевой фазы**. В терминологии zapret это означает:

| Фаза | Когда | Что доступно | Примеры функций |
|:-----|:------|:-------------|:----------------|
| **Фаза 0 (SYN)** | До TCP handshake | Только SYN-пакет. Нет payload от приложения | `syndata`, [[wssize]] |
| **Фаза 1 (данные)** | После handshake, первые данные | Реальный payload (TLS ClientHello, HTTP request и т.д.) | [[fake]], [[multisplit]], [[fakedsplit]] |

Следствия нулевой фазы:

- **Нет реального payload:** приложение ещё ничего не отправило, поэтому syndata работает только с blob-данными или нулями
- **Нет hostname:** на этом этапе zapret не знает, к какому домену обращается клиент --- хостлисты работают только через `--ipcache-hostname`
- **Нет payload filter:** параметры `--payload=...` и `payload=...` не применимы --- SYN-пакет не содержит данных приложения
- **Воздействие на все ретрансмиссии SYN:** если TCP-стек ретранслирует SYN (timeout), syndata обработает и его

### Логика обработки пакетов

```
Пакет пришёл в syndata
  |
  +-- Не TCP? --> instance_cutoff (кроме ICMP)
  |
  +-- TCP:
       |
       +-- Флаг SYN (не SYN+ACK)? --> deepcopy dis, добавить payload,
       |                               apply_fooling, tls_mod,
       |                               rawsend + VERDICT_DROP
       |
       +-- Не SYN? --> instance_cutoff (миссия завершена)
```

Ключевые моменты:

- Проверяется именно `TH_SYN` без `TH_ACK` --- то есть **только исходящий SYN** от клиента, не SYN+ACK от сервера
- `deepcopy` --- работа ведётся с **копией** dissect, оригинал не модифицируется
- Если пакет не SYN (например, ACK, PSH+ACK) --- это значит, что handshake уже прошёл, и syndata отключает себя (`instance_cutoff`)
- Для ICMP cutoff не выполняется --- ICMP может быть связан с SYN (например, ICMP Destination Unreachable)

---

## Полный список аргументов

Формат вызова:

```
--lua-desync=syndata[:arg1[=val1][:arg2[=val2]]...]
```

Все `val` приходят в Lua как строки. Если `=val` не указан, значение = пустая строка `""` (в Lua это truthy), поэтому флаги пишутся просто как `:tcp_md5`, `:badsum`, `:ipfrag`.

**Важно:** syndata **не поддерживает** стандартные аргументы `direction`, `payload` (фильтр) и `ipid`. Это связано с тем, что syndata работает на фазе 0 (SYN), где нет данных приложения, нет понятия "payload type", и `apply_ip_id` не вызывается.

### A) Собственные аргументы syndata

#### `blob`

- **Формат:** `blob=<blobName>`
- **Тип:** имя blob-переменной
- **По умолчанию:** 16 нулевых байт (`\x00` x 16)
- **Описание:** Payload, который будет добавлен в SYN-пакет. Должен помещаться в один пакет --- сегментация **невозможна** (используется `rawsend_dissect_ipfrag`, а не `rawsend_payload_segmented`). Если blob не задан, отправляются 16 нулевых байт
- **Примеры:**
  - `blob=fake_default_tls` --- стандартный TLS-фейк из zapret
  - `blob=fake_default_http` --- стандартный HTTP-фейк
  - `blob=0xDEADBEEF` --- inline hex
  - `blob=my_custom_payload` --- предзагруженный blob
  - без `blob=` --- 16 нулей (дефолт)

#### `tls_mod`

- **Формат:** `tls_mod=<mod1[,mod2,...]>`
- **Тип:** строка со списком модификаций через запятую
- **По умолчанию:** не задан
- **Описание:** Модификации TLS-данных в payload перед отправкой. Применяется **после** `apply_fooling`. Подробности --- в разделе [tls_mod](#tls_mod--модификация-tls-в-syndata)
- **Работающие значения:** `rnd`, `rndsni`, `sni=<str>` (включая `sni=%var`)
- **Молча игнорируемые:** `dupsid`, `padencap`
- **Примеры:**
  - `tls_mod=rnd` --- рандомизация TLS-полей
  - `tls_mod=rndsni` --- рандомизация SNI
  - `tls_mod=sni=google.com` --- замена SNI
  - `tls_mod=rnd,rndsni,sni=google.com` --- комбинация
  - `tls_mod=dupsid` --- **не даст ошибки, но молча проигнорируется**

---

### B) Standard fooling

Модификации L3/L4 заголовков. В `syndata` применяются к **копии** dissect (через `apply_fooling` после `deepcopy`). Оригинальный пакет не модифицируется --- он дропается.

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

**Заметка:** fooling в syndata имеет иной смысл, чем в [[fake]] или [[fakedsplit]]. В [[fake]] fooling нужен, чтобы сервер **отбросил** фейк. В syndata fooling модифицирует сам SYN-пакет, который сервер должен **принять** для установления соединения. Поэтому деструктивные fooling-параметры (`tcp_seq`, `tcp_ack`, `badsum`) **сломают** handshake --- сервер не получит валидный SYN. Безопасные варианты: `ip_ttl`/`ip6_ttl` (если TTL хватит до DPI, но не до сервера --- спорно для SYN), `tcp_md5` (сервер без MD5 проигнорирует опцию), IPv6 extension headers.

---

### C) Standard reconstruct

| Параметр | Описание |
|:---------|:---------|
| `badsum` | Испортить L4 (TCP) checksum при реконструкции raw-пакета. Сервер отбросит такой пакет |

**Предупреждение:** `badsum` в syndata означает, что сервер **не получит SYN вообще** --- TCP handshake не состоится. Используйте только если хотите отправить "мусорный" SYN, за которым пойдёт ретрансмиссия.

---

### D) Standard rawsend

| Параметр | Описание |
|:---------|:---------|
| `repeats=N` | Отправить пакет N раз (идентичные повторы) |
| `ifout=<iface>` | Интерфейс для отправки (по умолчанию определяется автоматически) |
| `fwmark=N` | Firewall mark (только Linux, nftables/iptables) |

---

### E) Standard ipfrag

IP-фрагментация SYN-пакета. Каждый отправляемый SYN+payload фрагментируется на уровне IP.

| Параметр | Описание | По умолчанию |
|:---------|:---------|:-------------|
| `ipfrag[=func]` | Включить IP-фрагментацию. Если без значения --- `ipfrag2` | --- |
| `ipfrag_disorder` | Отправить IP-фрагменты в обратном порядке | --- |
| `ipfrag_pos_tcp=N` | Позиция фрагментации TCP (кратно 8) | `32` |
| `ipfrag_pos_udp=N` | Позиция фрагментации UDP (кратно 8). Для syndata бесполезно --- он только TCP | `8` |
| `ipfrag_next=N` | IPv6: next protocol во 2-м фрагменте (penetration атака на фаерволы) | --- |

---

## tls_mod --- модификация TLS в syndata

`tls_mod` позволяет модифицировать TLS-данные внутри payload перед отправкой. Вызывается **после** `apply_fooling`:

```lua
if desync.arg.tls_mod then
    dis.payload = tls_mod_shim(desync, dis.payload, desync.arg.tls_mod, nil)
end
```

Четвёртый аргумент --- `nil` (реальный payload от приложения). Это ключевой момент, определяющий какие модификации работают, а какие --- нет.

### Работающие модификации

| Мод | Описание | Работает? | Причина |
|:----|:---------|:----------|:--------|
| `rnd` | Рандомизация TLS-полей (session_id, random) | Да | Код находится **вне** блока `if(payload)` |
| `rndsni` | Рандомизация SNI (замена на случайные символы) | Да | Код находится **вне** блока `if(payload)` |
| `sni=<str>` | Замена SNI на указанную строку. Поддерживает `sni=%var` | Да | Код находится **вне** блока `if(payload)` |

**Пример:** если blob содержит TLS ClientHello с SNI `www.example.com`, а вы указали `tls_mod=sni=google.com`, в отправленном SYN-пакете SNI будет заменён на `google.com`.

### dupsid и padencap --- молчаливое игнорирование

| Мод | Описание | Работает? | Причина |
|:----|:---------|:----------|:--------|
| `dupsid` | Дублирование session_id из реального ClientHello | Молча игнорируется | Требует реальный payload (4-й аргумент != NULL) |
| `padencap` | Упаковка в padding extension | Молча игнорируется | Требует реальный payload (4-й аргумент != NULL) |

Поведение при использовании dupsid/padencap:

| Аспект | Результат |
|:-------|:----------|
| Вызывают ошибку? | НЕТ |
| Выводят warning в лог? | НЕТ |
| Возвращают false? | НЕТ (возвращают true = "успех") |
| Применяются? | НЕТ --- код просто пропускается |

### Почему dupsid и padencap не работают

В C-коде (`protocol.c`) логика dupsid и padencap находится внутри блока `if (payload)`:

```c
// protocol.c
if (payload)  // <-- syndata передаёт NULL сюда
{
    if (tls_mod->mod & FAKE_TLS_MOD_DUP_SID)
        // ... копирование session_id из реального ClientHello
        // этот код НЕ выполнится

    if (tls_mod->mod & FAKE_TLS_MOD_PADENCAP)
        // ... упаковка реального payload в padding
        // и этот тоже
}
return bRes;  // возвращает true --- "всё ОК"
```

Причина: dupsid копирует session_id **из реального ClientHello клиента** в фейк. На фазе SYN реального ClientHello ещё не существует (клиент его не отправлял). Аналогично padencap упаковывает **реальный payload** в padding extension --- на фазе SYN упаковывать нечего.

Это дизайн-решение, а не баг. Но отсутствие warning в логе может ввести в заблуждение --- конфигурация с `tls_mod=dupsid` будет молча работать "без dupsid".

---

## Псевдокод алгоритма

```lua
function syndata(ctx, desync)
    -- 1. Проверка: только TCP
    if not desync.dis.tcp then
        -- ICMP пропускаем (не делаем cutoff), остальное --- cutoff
        if not desync.dis.icmp then instance_cutoff(ctx, desync) end
        return
    end

    -- 2. Проверка: только SYN (не SYN+ACK)
    if bitand(th_flags, TH_SYN + TH_ACK) == TH_SYN then

        -- 3. Глубокая копия dissect (оригинал не трогаем)
        dis = deepcopy(desync.dis)

        -- 4. Установка payload: blob или 16 нулей
        dis.payload = blob(desync, arg.blob, "\x00" * 16)

        -- 5. Применение fooling к копии
        apply_fooling(desync, dis)

        -- 6. tls_mod (если задан)
        if arg.tls_mod then
            dis.payload = tls_mod_shim(desync, dis.payload, arg.tls_mod, nil)
            --                                                           ^^^ payload от приложения = nil
        end

        -- 7. Отправка и фрагментация
        if rawsend_dissect_ipfrag(dis, desync_opts(desync)) then
            return VERDICT_DROP  -- оригинальный SYN дропается
        end

    else
        -- 8. Не SYN --- миссия завершена
        instance_cutoff(ctx, desync)
    end
end
```

Ключевые отличия от функций сегментации ([[multisplit]], [[fakedsplit]] и т.д.):

- **Нет цикла по позициям** --- payload отправляется **одним** пакетом целиком
- **`rawsend_dissect_ipfrag`** вместо `rawsend_payload_segmented` --- нет TCP-сегментации, только IP-фрагментация
- **`deepcopy`** --- полная копия dissect, а не создание нового пакета
- **Нет replay/reasm логики** --- на фазе SYN нет многопакетных данных

---

## Отличия от fake

| Аспект | `syndata` | [[fake]] |
|:-------|:----------|:---------|
| **Фаза** | 0 (SYN, до handshake) | 1 (после handshake, есть реальные данные) |
| **Что отправляет** | SYN-пакет с payload | Отдельный data-пакет (не SYN) |
| **Дефолтный blob** | 16 нулевых байт | **Обязательный** --- без blob ничего не отправится |
| **Сегментация** | Невозможна (один пакет) | Невозможна (один пакет) |
| **Заменяет оригинал** | Да (VERDICT_DROP на SYN) | Нет (оригинал проходит дальше) |
| **Fooling** | Модифицирует сам SYN --- осторожно! | Модифицирует фейк --- сервер должен его отбросить |
| **tls_mod=dupsid** | Молча игнорируется | Работает (есть реальный ClientHello) |
| **tls_mod=padencap** | Молча игнорируется | Работает (есть реальный payload) |
| **Хостлисты** | Только `--ipcache-hostname` | Работают напрямую (payload уже содержит hostname) |
| **Воздействие на ретрансмиссии** | Да --- каждый SYN обрабатывается | Нет --- работает с конкретным data-пакетом |
| **direction** | Не поддерживается | Поддерживается |
| **payload filter** | Не поддерживается | Поддерживается |
| **ipid** | Не поддерживается | Поддерживается |

**Когда использовать syndata вместо fake:**

- DPI начинает трекинг с SYN и не реагирует на фейки после handshake
- Нужно "отравить" DPI ложными данными **до** того, как пойдёт реальный трафик
- В комбинации с [[wssize]] и [[multisplit]] для многоуровневой атаки

---

## Работа с хостлистами

На фазе 0 (SYN) zapret **не знает** hostname --- приложение ещё не отправило HTTP-запрос или TLS ClientHello. Поэтому стандартная фильтрация по хостлистам (`--hostlist=...`) не работает с syndata напрямую.

Единственный способ --- `--ipcache-hostname`:

```bash
nfqws2 --ipcache-hostname \
  --hostlist=blocked.txt \
  --lua-desync=syndata:blob=fake_default_tls
```

Как это работает:

1. Первое соединение к IP-адресу проходит **без** syndata (hostname ещё не известен)
2. Из первого соединения zapret узнаёт hostname (из TLS ClientHello или HTTP Host) и кеширует привязку IP -> hostname
3. Последующие SYN к этому IP уже проходят через syndata, потому что zapret знает hostname из кеша

**Следствие:** syndata с хостлистом не подействует на **первое** соединение к данному IP. Это может быть проблемой для сайтов с уникальными IP или CDN с ротацией адресов.

---

## Комбинирование с другими функциями

`syndata` часто используется в цепочке с другими функциями. **Порядок инстансов важен!**

### Типовая цепочка: wssize + syndata + multisplit

```bash
--lua-desync=wssize:wsize=1:scale=6 \
--lua-desync=syndata \
--lua-desync=multisplit:pos=midsld
```

Что происходит:

1. **SYN-пакет приходит:**
   - `wssize` модифицирует TCP Window Size в SYN (wsize=1, scale=6)
   - `syndata` добавляет payload в SYN, дропает оригинал, отправляет модифицированный
   - `multisplit` ничего не делает (SYN, нет данных для нарезки)

2. **Первый data-пакет (например, TLS ClientHello) приходит:**
   - `wssize` --- миссия уже выполнена (cutoff или пропуск)
   - `syndata` делает `instance_cutoff` (пакет не SYN)
   - `multisplit` нарезает payload по позиции `midsld`

**Почему wssize перед syndata:** [[wssize]] модифицирует TCP Window Size в SYN-пакете. Если поставить после syndata, wssize увидит `VERDICT_DROP` и не получит SYN. Если перед --- wssize модифицирует dissect, затем syndata использует `deepcopy` этого (уже модифицированного) dissect.

### Цепочка: syndata + fake + multisplit

```bash
--lua-desync=syndata:blob=fake_default_tls \
--lua-desync=fake:blob=fake_default_tls:tcp_md5 \
--lua-desync=multisplit:pos=1,midsld
```

Многоуровневая атака:
1. Фаза 0: SYN с фейковым TLS
2. Фаза 1: фейковый пакет с fooling (tcp_md5)
3. Фаза 1: реальный payload нарезан на сегменты

---

## Нюансы и подводные камни

### 1. Payload должен помещаться в один пакет

syndata использует `rawsend_dissect_ipfrag`, а **не** `rawsend_payload_segmented`. Это означает, что TCP-сегментация **невозможна**. Если blob слишком большой и не влезает в один Ethernet frame (с учётом MTU), пакет может быть отброшен сетевым стеком или фрагментирован на IP-уровне (если включён `ipfrag`).

### 2. Fooling может сломать handshake

В отличие от [[fake]], где fooling **должен** заставить сервер отбросить пакет, в syndata fooling применяется к пакету, который сервер **должен принять**. Деструктивные параметры:

- `tcp_seq=N` --- сервер не увидит SYN с правильным sequence
- `tcp_ack=N` --- невалидный ack в SYN
- `badsum` --- сервер отбросит пакет с плохой checksum
- `tcp_flags_unset=SYN` --- пакет перестанет быть SYN

Безопасные параметры:
- `tcp_md5` --- сервер без MD5 проигнорирует опцию (RFC 2385)
- `tcp_ts_up` --- перестановка timestamp option (не влияет на валидность)
- `tcp_nop_del` --- удаление NOP (не влияет на валидность)
- IPv6 extension headers --- для обхода DPI/фаерволов на пути

### 3. Нет direction, payload filter, ipid

syndata не вызывает `direction_cutoff_opposite`, `direction_check`, `payload_check` или `apply_ip_id`. Эти стандартные блоки просто отсутствуют в коде функции:

- **direction** --- SYN всегда исходящий, фильтрация по направлению бессмысленна
- **payload filter** --- в SYN нет данных приложения, фильтровать нечего
- **ipid** --- `apply_ip_id` не вызывается, IP ID не контролируется

### 4. Все ретрансмиссии SYN обрабатываются

Если первый SYN не дошёл (или SYN+ACK потерялся), TCP-стек отправит ретрансмиссию SYN. syndata обработает **каждую** ретрансмиссию --- добавит payload, применит модификации, дропнет оригинал. Это полезно: DPI может обрабатывать только первый SYN, а ретрансмиссия с payload "перезапишет" данные в трекере.

### 5. deepcopy защищает оригинал

syndata делает `deepcopy(desync.dis)` и работает с копией. Это значит, что `apply_fooling` и замена payload не затрагивают оригинальный dissect. Если после syndata стоят другие инстансы и SYN не дропнут (rawsend failed), они увидят **немодифицированный** пакет.

### 6. instance_cutoff на не-SYN

Как только syndata видит пакет без флага SYN (ACK, PSH+ACK и т.д.), он делает `instance_cutoff` --- отключает себя для этого потока навсегда. Это правильно: миссия syndata --- только SYN-пакеты. Последующие данные должны обрабатываться другими функциями ([[multisplit]], [[fake]] и т.д.).

### 7. ICMP не вызывает cutoff

Если в цепочке инстансов через syndata проходит ICMP-пакет (например, ICMP Destination Unreachable в ответ на SYN), syndata **не** делает `instance_cutoff`. Это защита от преждевременного отключения --- ICMP может быть связан с SYN и не означает конец потока.

### 8. Дефолтный blob --- 16 нулей, а не обязательный параметр

В отличие от [[fake]], где blob обязателен, syndata имеет fallback --- 16 нулевых байт. `--lua-desync=syndata` без `blob=` отправит SYN с 16 байтами `0x00`. Это может быть достаточно, чтобы сбить DPI, который не ожидает payload в SYN.

### 9. tls_mod без blob бессмыслен

Если вы указали `tls_mod=rnd,rndsni` без `blob=`, tls_mod попытается модифицировать 16 нулевых байт как TLS --- результат будет непредсказуемым. Всегда используйте `tls_mod` вместе с blob, содержащим валидный TLS ClientHello.

---

## Миграция с nfqws1

### Соответствие параметров

| nfqws1 | nfqws2 |
|:-------|:-------|
| `--dpi-desync=syndata` | `--lua-desync=syndata` |
| `--dpi-desync-fake-tls=<file>` | `--blob=name:@file` + `:blob=name` |
| `--dpi-desync-fake-tls-mod=rnd,rndsni` | `:tls_mod=rnd,rndsni` |
| `--dpi-desync-fooling=md5sig` | `:tcp_md5` |
| `--wssize 1:6` | `--lua-desync=wssize:wsize=1:scale=6` (отдельный инстанс, **перед** syndata) |

### Пример полной миграции

```bash
# nfqws1:
nfqws --dpi-desync=syndata,multisplit \
  --dpi-desync-split-pos=midsld \
  --wssize 1:6

# nfqws2 (порядок инстансов важен!):
nfqws2 \
  --lua-desync=wssize:wsize=1:scale=6 \
  --lua-desync=syndata \
  --lua-desync=multisplit:pos=midsld
```

```bash
# nfqws1:
nfqws --dpi-desync=syndata \
  --dpi-desync-fake-tls-mod=rnd,rndsni

# nfqws2:
nfqws2 \
  --lua-desync=syndata:blob=fake_default_tls:tls_mod=rnd,rndsni
```

```bash
# nfqws1:
nfqws --dpi-desync=syndata \
  --dpi-desync-fooling=md5sig

# nfqws2:
nfqws2 \
  --lua-desync=syndata:tcp_md5
```

---

## Практические примеры

### Минимальный (дефолт: 16 нулей в SYN)

```bash
--lua-desync=syndata
```

Отправляет SYN с 16 нулевыми байтами вместо обычного SYN. Простейший вариант --- может сбить DPI, не ожидающий payload в SYN.

### С TLS-фейком

```bash
--lua-desync=syndata:blob=fake_default_tls
```

SYN содержит стандартный TLS ClientHello из zapret. DPI может принять это за начало TLS-сессии.

### С кастомным blob из файла

```bash
--blob=mysyndata:@custom_syn_payload.bin \
--lua-desync=syndata:blob=mysyndata
```

Загружает произвольный payload из файла и вставляет в SYN.

### С inline hex blob

```bash
--lua-desync=syndata:blob=0x160301000100
```

6 байт inline hex --- минимальный TLS record header.

### С рандомизацией TLS

```bash
--lua-desync=syndata:blob=fake_default_tls:tls_mod=rnd,rndsni
```

TLS-фейк с рандомизированными полями и SNI. Каждый SYN будет содержать уникальные random/session_id/SNI.

### С заменой SNI

```bash
--lua-desync=syndata:blob=fake_default_tls:tls_mod=sni=google.com
```

SYN содержит TLS ClientHello с SNI `google.com`. DPI может записать в трекер "это соединение к google.com" и не блокировать.

### С TCP MD5

```bash
--lua-desync=syndata:tcp_md5
```

SYN с 16 нулями и TCP MD5 option. Сервер без MD5 проигнорирует опцию, DPI может быть сбит нестандартным TCP-заголовком.

### С TTL fooling (осторожно!)

```bash
--lua-desync=syndata:blob=fake_default_tls:ip_ttl=5:ip6_ttl=5
```

SYN с TTL=5. Если DPI ближе 5 хопов --- увидит фейк. Если сервер дальше 5 хопов --- SYN не дойдёт, handshake не состоится. Ретрансмиссия SYN тоже получит TTL=5 и тоже не дойдёт. **Используйте только если точно знаете расстояние до DPI и сервера.**

### С IP-фрагментацией

```bash
--lua-desync=syndata:blob=fake_default_tls:ipfrag:ipfrag_disorder
```

SYN с TLS-фейком, фрагментированный на IP-уровне в обратном порядке. DPI, не собирающий IP-фрагменты, не увидит полный пакет.

### С IP-фрагментацией (кастомная позиция)

```bash
--lua-desync=syndata:blob=fake_default_tls:ipfrag:ipfrag_pos_tcp=24
```

Фрагментация по позиции 24 байта (кратно 8). Первый фрагмент содержит TCP-заголовок, второй --- payload.

### Типовая боевая комбинация: wssize + syndata + multisplit

```bash
--filter-tcp=443 \
  --lua-desync=wssize:wsize=1:scale=6 \
  --lua-desync=syndata \
  --lua-desync=multisplit:pos=midsld
```

Трёхуровневая атака на DPI: маленькое окно (заставляет сервер слать маленькие сегменты) + payload в SYN + нарезка реального ClientHello.

### Боевая комбинация: syndata + fake + multisplit

```bash
--filter-tcp=443 --hostlist=blocked.txt --ipcache-hostname \
  --lua-desync=syndata:blob=fake_default_tls:tls_mod=rnd,rndsni \
  --lua-desync=fake:blob=fake_default_tls:tcp_md5:tls_mod=rnd,rndsni,dupsid \
  --lua-desync=multisplit:pos=1,midsld
```

Максимальная комбинация: фейк в SYN, фейк после handshake (с dupsid --- здесь он работает, потому что это [[fake]], а не syndata), нарезка реального payload.

### Отладка: повторы отправки

```bash
--lua-desync=syndata:blob=fake_default_tls:repeats=3
```

Каждый SYN с payload отправляется 3 раза. Полезно для отладки или если DPI обрабатывает только N-й пакет.

### IPv6: extension headers

```bash
--lua-desync=syndata:blob=fake_default_tls:ip6_hopbyhop:ip6_destopt
```

SYN с hop-by-hop и destination options extension headers. Некоторые DPI/фаерволы не умеют парсить IPv6 extension headers и пропускают пакет.

---

> **Источники:** `lua/zapret-antidpi.lua:385`, `lua/zapret-lib.lua`, `docs/manual.md:3944-3961` из репозитория zapret2.

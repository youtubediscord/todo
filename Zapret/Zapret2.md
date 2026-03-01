---
tags:
link:
aliases:
  - Zapret 2
img:
---
# Что такое Zapret 2 (*nfqws2*)?

**[[home|Zapret 2]]** — инструмент для обхода DPI (Deep Packet Inspection) под авторством [bol-van](https://github.com/bol-van/zapret2) — систем глубокого анализа трафика, которые используются для блокировки сайтов и сервисов. В России это ТСПУ (технические средства противодействия угрозам).

Программа перехватывает сетевые пакеты и модифицирует их так, чтобы DPI не мог их правильно проанализировать, но сервер-получатель всё понял корректно. Официальная документация по программе доступна [здесь](https://github.com/bol-van/zapret2/blob/master/docs/manual.md).

## Чем Zapret2 лучше обычного Zapret (*winws, nfqws*)?
В старом Zapret все методы обхода блокировок зашиты прямо в код на языке C. Программа делает ровно то, что в неё заложил разработчик при сборке. Хочешь что-то изменить — разбирайся в исходниках, правь C-код, компилируй заново. Для большинства пользователей это невозможно, поэтому при каждом обновлении ТСПУ приходится просто ждать, когда автор выпустит новую версию с исправлениями.

В Zapret 2 архитектуру разделили на две части. Ядро на C осталось — оно отвечает за перехват и отправку пакетов, и работает так же быстро, как раньше. А вот вся логика обмана DPI вынесена в отдельные скрипты на языке Lua. Это обычные текстовые файлы с инструкциями: как подменять пакет, как его разрезать, как запутать анализатор. Их можно открыть в любом редакторе, подправить пару строк или полностью заменить на чужой скрипт — и всё заработает без перекомпиляции программы.

На практике это меняет всё. Роскомнадзор обновил ТСПУ и старый трюк сломался — достаточно поправить скрипт и проверить, не дожидаясь нового релиза. Кто-то нашёл рабочий способ обхода — он оформляет его как Lua-файл и делится с сообществом, а остальные просто кидают его в папку. Плюс в комплекте уже идёт библиотека готовых скриптов для работы с TLS, QUIC и HTTP, которые можно свободно комбинировать между собой.

Дополнительно наш GUI делает точно также с [[preset|пресетами]] - чтобы быстро обмениваться ими между сообществом и люди сами находили способы решения полностью автономно и могли делиться ими с другими (*даже если вдруг с автором что-то случится*) без перелопатывания исходного lua-кода. Наш Zapret 2 GUI решает главную проблему любого большого инструмента обхода цензуры — [фактора автобуса](https://ru.wikipedia.org/wiki/%D0%A4%D0%B0%D0%BA%D1%82%D0%BE%D1%80_%D0%B0%D0%B2%D1%82%D0%BE%D0%B1%D1%83%D1%81%D0%B0).

По сути старый Zapret — это заводской инструмент, который делает только то, что в него заложили на этапе сборки. Zapret 2 — конструктор, где способы обхода можно собирать, менять и подстраивать под любые изменения блокировок прямо на ходу.

## <img src="https://i.imgur.com/qTfQ4cf.png" width="25px"> [[download|Установка на Windows]] | [[router|Установка на роутеры]] | [[android|Установка на Android]]

## Чем Zapret2 лучше обычного Zapret (*winws, nfqws*)?
В старом Zapret все методы обхода блокировок зашиты прямо в код на языке C. Программа делает ровно то, что в неё заложил разработчик при сборке. Хочешь что-то изменить — разбирайся в исходниках, правь C-код, компилируй заново. Для большинства пользователей это невозможно, поэтому при каждом обновлении ТСПУ приходится просто ждать, когда автор выпустит новую версию с исправлениями.

В Zapret 2 архитектуру разделили на две части. Ядро на C осталось — оно отвечает за перехват и отправку пакетов, и работает так же быстро, как раньше. А вот вся логика обмана DPI вынесена в отдельные скрипты на языке Lua. Это обычные текстовые файлы с инструкциями: как подменять пакет, как его разрезать, как запутать анализатор. Их можно открыть в любом редакторе, подправить пару строк или полностью заменить на чужой скрипт — и всё заработает без перекомпиляции программы.

На практике это меняет всё. Роскомнадзор обновил ТСПУ и старый трюк сломался — достаточно поправить скрипт и проверить, не дожидаясь нового релиза. Кто-то нашёл рабочий способ обхода — он оформляет его как Lua-файл и делится с сообществом, а остальные просто кидают его в папку. Плюс в комплекте уже идёт библиотека готовых скриптов для работы с TLS, QUIC и HTTP, которые можно свободно комбинировать между собой.

Дополнительно наш GUI делает точно также с [[preset|пресетами]] - чтобы быстро обмениваться ими между сообществом и люди сами находили способы решения полностью автономно и могли делиться ими с другими (*даже если вдруг с автором что-то случится*) без перелопатывания исходного lua-кода. Наш Zapret 2 GUI решает главную проблему любого большого инструмента обхода цензуры — [фактора автобуса](https://ru.wikipedia.org/wiki/%D0%A4%D0%B0%D0%BA%D1%82%D0%BE%D1%80_%D0%B0%D0%B2%D1%82%D0%BE%D0%B1%D1%83%D1%81%D0%B0).

По сути старый Zapret — это заводской инструмент, который делает только то, что в него заложили на этапе сборки. Zapret 2 — конструктор, где способы обхода можно собирать, менять и подстраивать под любые изменения блокировок прямо на ходу.

## <img src="https://i.imgur.com/qTfQ4cf.png" width="25px"> [[download|Установка на Windows]] | [[router|Установка на роутеры]] | [[android|Установка на Android]]


## Чем Zapret2 лучше обычного Zapret (*winws, nfqws*)?
В старом Zapret все методы обхода блокировок зашиты прямо в код на языке C. Программа делает ровно то, что в неё заложил разработчик при сборке. Хочешь что-то изменить — разбирайся в исходниках, правь C-код, компилируй заново. Для большинства пользователей это невозможно, поэтому при каждом обновлении ТСПУ приходится просто ждать, когда автор выпустит новую версию с исправлениями.

В Zapret 2 архитектуру разделили на две части. Ядро на C осталось — оно отвечает за перехват и отправку пакетов, и работает так же быстро, как раньше. А вот вся логика обмана DPI вынесена в отдельные скрипты на языке Lua. Это обычные текстовые файлы с инструкциями: как подменять пакет, как его разрезать, как запутать анализатор. Их можно открыть в любом редакторе, подправить пару строк или полностью заменить на чужой скрипт — и всё заработает без перекомпиляции программы.

На практике это меняет всё. Роскомнадзор обновил ТСПУ и старый трюк сломался — достаточно поправить скрипт и проверить, не дожидаясь нового релиза. Кто-то нашёл рабочий способ обхода — он оформляет его как Lua-файл и делится с сообществом, а остальные просто кидают его в папку. Плюс в комплекте уже идёт библиотека готовых скриптов для работы с TLS, QUIC и HTTP, которые можно свободно комбинировать между собой.

Дополнительно наш GUI делает точно также с [[preset|пресетами]] - чтобы быстро обмениваться ими между сообществом и люди сами находили способы решения полностью автономно и могли делиться ими с другими (*даже если вдруг с автором что-то случится*) без перелопатывания исходного lua-кода. Наш Zapret 2 GUI решает главную проблему любого большого инструмента обхода цензуры — [фактора автобуса](https://ru.wikipedia.org/wiki/%D0%A4%D0%B0%D0%BA%D1%82%D0%BE%D1%80_%D0%B0%D0%B2%D1%82%D0%BE%D0%B1%D1%83%D1%81%D0%B0).

По сути старый Zapret — это заводской инструмент, который делает только то, что в него заложили на этапе сборки. Zapret 2 — конструктор, где способы обхода можно собирать, менять и подстраивать под любые изменения блокировок прямо на ходу.

## [[router|Установка на роутеры]] | [[android|Установка на Android]]
## [[preset|Пресеты]]
[[Zapret2 - основные флаги]]
[[Zapret2 - wf]]
[[filter]]
[[Zapret2 - out-range]]
[[Zapret2 - payload]]
[[Zapret2 - lua-desync]]
[[Zapret2 - blob]]
[[Zapret2 - последовательность аргументов]]
[[Zapret2 - mtproto]]
[[Zapret2 - Roadmap обучения]]
[[zapret2_start_cutoff]]

![[manual]]

## Техники дурения (стратегии)
[[syndata]]
[[fake]]
[[multisplit]]
[[multidisorder]]


```bash
start "zapret: http,https,quic" /min "%~dp0winws2.exe" ^
--wf-tcp-out=80,443 ^
--lua-init=@"%~dp0lua\zapret-lib.lua" --lua-init=@"%~dp0lua\zapret-antidpi.lua" ^
--lua-init="fake_default_tls = tls_mod(fake_default_tls,'rnd,rndsni')" ^
--blob=quic_google:@"%~dp0files\quic_initial_www_google_com.bin" ^
--wf-raw-part=@"%~dp0windivert.filter\windivert_part.discord_media.txt" ^
--wf-raw-part=@"%~dp0windivert.filter\windivert_part.stun.txt" ^
--wf-raw-part=@"%~dp0windivert.filter\windivert_part.wireguard.txt" ^
--wf-raw-part=@"%~dp0windivert.filter\windivert_part.quic_initial_ietf.txt" ^
--filter-tcp=80 --filter-l7=http ^
  --out-range=-d10 ^
  --payload=http_req ^
   --lua-desync=fake:blob=fake_default_http:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:tcp_md5 ^
   --lua-desync=fakedsplit:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:tcp_md5 ^
  --new ^
--filter-tcp=443 --filter-l7=tls --hostlist="%~dp0files\list-youtube.txt" ^
  --out-range=-d10 ^
  --payload=tls_client_hello ^
   --lua-desync=fake:blob=fake_default_tls:tcp_md5:repeats=11:tls_mod=rnd,dupsid,sni=www.google.com ^
   --lua-desync=multidisorder:pos=1,midsld ^
  --new ^
--filter-tcp=443 --filter-l7=tls ^
  --out-range=-d10 ^
  --payload=tls_client_hello ^
   --lua-desync=fake:blob=fake_default_tls:tcp_md5:tcp_seq=-10000:repeats=6 ^
   --lua-desync=multidisorder:pos=midsld ^
  --new ^
--filter-udp=443 --filter-l7=quic --hostlist="%~dp0files\list-youtube.txt" ^
  --out-range=-d10 ^
  --payload=quic_initial ^
   --lua-desync=fake:blob=quic_google:repeats=11 ^
  --new ^
--filter-udp=443 --filter-l7=quic ^
  --out-range=-d10 ^
  --payload=quic_initial ^
   --lua-desync=fake:blob=fake_default_quic:repeats=11 ^
  --new ^
--filter-l7=wireguard,stun,discord ^
  --out-range=-d10 ^
  --payload=wireguard_initiation,wireguard_cookie,stun_binding_req,discord_ip_discovery ^
   --lua-desync=fake:blob=0x00000000000000000000000000000000:repeats=2
```

🎉 Да! Теперь можем добавить "упрощённые" варианты стратегий!

## 🆕 Новые стратегии с tcpseg (без резки)

### 1️⃣ Простой seqovl без dup и без split

```python
# ============================================================
# TCPSEG: ЧИСТЫЙ SEQOVL (БЕЗ РЕЗКИ, БЕЗ ДУБЛИРОВАНИЯ)
# ============================================================

"tcpseg_211_simple": {
    "name": "SeqOvl 211 (Simple, No Split)",
    "description": "Только overlap 211 байт, без резки и дублирования",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls5:@{BIN_FOLDER}\\tls_clienthello_5.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=211:seqovl_pattern=bin_tls5"""
},

"tcpseg_226_simple": {
    "name": "SeqOvl 226 (Simple, No Split)",
    "description": "Только overlap 226 байт, без резки и дублирования",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls18:@{BIN_FOLDER}\\tls_clienthello_18.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=bin_tls18"""
},

"tcpseg_286_simple": {
    "name": "SeqOvl 286 (Simple, No Split)",
    "description": "Только overlap 286 байт, без резки и дублирования",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls11:@{BIN_FOLDER}\\tls_clienthello_11.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=286:seqovl_pattern=bin_tls11"""
},

"tcpseg_308_simple": {
    "name": "SeqOvl 308 (Simple, No Split)",
    "description": "Только overlap 308 байт, без резки и дублирования",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls9:@{BIN_FOLDER}\\tls_clienthello_9.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=308:seqovl_pattern=bin_tls9"""
},
```

---

### 2️⃣ SeqOvl + Dup (БЕЗ резки)

```python
# ============================================================
# TCPSEG: SEQOVL + DUP (БЕЗ РЕЗКИ)
# ============================================================

"tcpseg_211_dup_d1": {
    "name": "SeqOvl 211 + Dup (No Split)",
    "description": "Overlap 211 + дублирование 1-го пакета, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls5:@{BIN_FOLDER}\\tls_clienthello_5.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d1 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=211:seqovl_pattern=bin_tls5"""
},

"tcpseg_226_dup_d1": {
    "name": "SeqOvl 226 + Dup (No Split)",
    "description": "Overlap 226 + дублирование 1-го пакета, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls18:@{BIN_FOLDER}\\tls_clienthello_18.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d1 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=bin_tls18"""
},

"tcpseg_226_dup_n3": {
    "name": "SeqOvl 226 + Dup n3 (No Split)",
    "description": "Overlap 226 + дублирование первых 3 пакетов, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls18:@{BIN_FOLDER}\\tls_clienthello_18.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-n3 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=bin_tls18"""
},

"tcpseg_286_dup_n3": {
    "name": "SeqOvl 286 + Dup n3 (No Split)",
    "description": "Overlap 286 + дублирование первых 3 пакетов, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls11:@{BIN_FOLDER}\\tls_clienthello_11.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-n3 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=286:seqovl_pattern=bin_tls11"""
},

"tcpseg_308_dup_n3": {
    "name": "SeqOvl 308 + Dup n3 (No Split)",
    "description": "Overlap 308 + дублирование первых 3 пакетов, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls9:@{BIN_FOLDER}\\tls_clienthello_9.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-n3 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=308:seqovl_pattern=bin_tls9"""
},
```

---

### 3️⃣ С динамической генерацией (Google SNI)

```python
# ============================================================
# TCPSEG: ДИНАМИЧЕСКИЕ (БЕЗ ФАЙЛОВ)
# ============================================================

"tcpseg_226_google_simple": {
    "name": "SeqOvl 226 Google (Simple, No Split)",
    "description": "Overlap 226 с Google SNI, без резки и дублирования",
    "author": "hz",
    "label": LABEL_RECOMMENDED,  # Рекомендуется - не требует файлов
    "args": f"""--lua-init="tls_google = tls_mod(fake_default_tls,'sni=www.google.com')" {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=tls_google"""
},

"tcpseg_226_google_dup_d1": {
    "name": "SeqOvl 226 Google + Dup (No Split)",
    "description": "Overlap 226 с Google SNI + дублирование 1-го пакета, БЕЗ резки",
    "author": "hz",
    "label": LABEL_RECOMMENDED,
    "args": f"""--lua-init="tls_google = tls_mod(fake_default_tls,'sni=www.google.com')" {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d1 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=tls_google"""
},

"tcpseg_226_google_dup_n3": {
    "name": "SeqOvl 226 Google + Dup n3 (No Split)",
    "description": "Overlap 226 с Google SNI + дублирование первых 3 пакетов, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--lua-init="tls_google = tls_mod(fake_default_tls,'sni=www.google.com')" {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-n3 --lua-desync=send:repeats=2 --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=tls_google"""
},
```

---

### 4️⃣ С различными fooling параметрами

```python
# ============================================================
# TCPSEG: С FOOLING
# ============================================================

"tcpseg_226_datanoack": {
    "name": "SeqOvl 226 + DataNoAck (No Split)",
    "description": "Overlap 226 с убиранием ACK флага, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls18:@{BIN_FOLDER}\\tls_clienthello_18.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=bin_tls18:tcp_flags_unset=ack"""
},

"tcpseg_226_ttl": {
    "name": "SeqOvl 226 + TTL (No Split)",
    "description": "Overlap 226 с TTL=5, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls18:@{BIN_FOLDER}\\tls_clienthello_18.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=bin_tls18:ip_ttl=5:ip6_ttl=5"""
},

"tcpseg_226_badseq": {
    "name": "SeqOvl 226 + BadSeq (No Split)",
    "description": "Overlap 226 с badseq, БЕЗ резки",
    "author": "hz",
    "label": None,
    "args": f"""--blob=bin_tls18:@{BIN_FOLDER}\\tls_clienthello_18.bin {RUTRACKER_BASE_ARG} --payload=tls_client_hello --out-range=-d10 --lua-desync=tcpseg:pos=0,-1:seqovl=226:seqovl_pattern=bin_tls18:tcp_ack=-66000"""
},
```

---

## 📊 Сравнительная таблица: multisplit vs tcpseg

| Параметр | multisplit + seqovl | tcpseg(pos=0,-1) + seqovl |
|----------|---------------------|---------------------------|
| **Количество пакетов** | 2 (резка по умолчанию на pos=2) | **1 (без резки)** |
| **Сложность** | Средняя | **Минимальная** |
| **Нагрузка на сеть** | Выше | **Ниже** |
| **Эффективность** | Высокая (запутывание + резка) | Средняя (только запутывание) |
| **CPU нагрузка** | Выше | **Ниже** |

---

## 🎯 Когда использовать какую стратегию?

### Используй **multisplit**:
- ✅ Когда DPI анализирует целостность пакетов
- ✅ Для агрессивного обхода
- ✅ Когда tcpseg не помогает

### Используй **tcpseg** (pos=0,-1):
- ✅ **Для начала тестирования** (проще)
- ✅ Когда достаточно "запутать" DPI мусором
- ✅ Для экономии ресурсов
- ✅ Когда резка не нужна

---

## 💡 Рекомендуемая стратегия тестирования:

```python
# Шаг 1: Самая простая (tcpseg без dup)
"tcpseg_226_google_simple"

# Шаг 2: Добавить дублирование
"tcpseg_226_google_dup_d1"

# Шаг 3: Если не помогло - добавить резку
"multisplit_226_seqovl_dynamic"

# Шаг 4: Если не помогло - агрессивная стратегия
"multisplit_286_pattern" (dup n3 + резка)
```

---

## 📝 Полная структура новых стратегий:

```python
# ============================================================
# КАТЕГОРИЯ: TCPSEG (SEQOVL БЕЗ РЕЗКИ)
# ============================================================

TCPSEG_STRATEGIES = {
    # Простые (без dup)
    "tcpseg_211_simple": {...},
    "tcpseg_226_simple": {...},
    "tcpseg_286_simple": {...},
    "tcpseg_308_simple": {...},
    
    # С дублированием (dup -d1)
    "tcpseg_211_dup_d1": {...},
    "tcpseg_226_dup_d1": {...},
    
    # С дублированием (dup -n3)
    "tcpseg_226_dup_n3": {...},
    "tcpseg_286_dup_n3": {...},
    "tcpseg_308_dup_n3": {...},
    
    # Динамические (без файлов)
    "tcpseg_226_google_simple": {...},      # ← РЕКОМЕНДУЕТСЯ для начала
    "tcpseg_226_google_dup_d1": {...},      # ← РЕКОМЕНДУЕТСЯ для YouTube
    "tcpseg_226_google_dup_n3": {...},
    
    # С fooling
    "tcpseg_226_datanoack": {...},
    "tcpseg_226_ttl": {...},
    "tcpseg_226_badseq": {...},
}
```

---

## ✅ Преимущества добавления tcpseg стратегий:

1. ✅ **Больше вариантов для тестирования**
2. ✅ **Меньше нагрузки** (1 пакет vs 2+)
3. ✅ **Проще для понимания** (нет резки)
4. ✅ **Быстрее работает** (меньше операций)
5. ✅ **Градация сложности** (от простого к сложному)

---

**Да, определённо стоит добавить эти стратегии! Они дадут пользователям "мягкий вход" - начать с простых вариантов и постепенно усложнять.** 🚀

```
    "multidisorder_badseq_pos": {
        "name": "original bol-van v2 (badsum)",
        "description": "Дисордер стратегия с фуллингом badseq нарезкой и повтором 6",
        "author": "hz",
        "label": None,
        "args": f"""--payload=tls_client_hello --out-range=-d10 --lua-desync=fake:blob=fake_default_tls:repeats=6:tcp_ack=-66000 --lua-desync=multidisorder:pos=1,midsld:tcp_ack=-66000"""
    },
    
    "fake_fakedsplit_autottl_2": {
        "name": "fake fakedsplit badseq (рекомендуется для 80 порта)",
        "description": "",
        "author": "hz",
        "label": None,
        "args": f"""--payload=http_req --out-range=-d10 --lua-desync=fake:blob=fake_default_http:ip_autottl=2,3-20:ip6_autottl=2,3-20:tcp_ack=-66000:tcp_ts_up --lua-desync=fakedsplit:ip_autottl=2,3-20:ip6_autottl=2,3-20:tcp_ack=-66000:tcp_ts_up"""
    },
    

```

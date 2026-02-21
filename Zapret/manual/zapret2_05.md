---
date: 2026-01-21
tags:
  - zapret
  - zapret2
  - payload
  - lua
  - learning
aliases:
  - Zapret2 учебник 05
---
# Zapret2 для новичков — 05: payload types, reasm/replay и маркеры

Цель: понять, как zapret2 отличает `http_req` от `tls_client_hello`, зачем нужен `reasm_data` и почему “маркеры” (host/midsld/…) иногда не работают.

## 1) `l7proto` vs `l7payload`

Это разные уровни классификации:

- `l7proto`: “какой протокол потока” (tls/http/quic/…)
- `l7payload`: “какой именно тип полезной нагрузки” (http_req, tls_client_hello, quic_initial, …)

В CLI это отражается так:
- `--filter-l7=tls,http,quic` — фильтр протокола потока
- `--payload=tls_client_hello` — фильтр типов payload внутри профиля

## 2) Почему payload важнее для Lua стратегий

Многие стратегии должны срабатывать только на “первом важном пакете”:
- HTTP request (где виден Host)
- TLS ClientHello (где виден SNI)
- QUIC Initial (где тоже “есть hello”, но шифрованнее и сложнее)

Поэтому фильтрация по payload экономит CPU и делает поведение предсказуемым.

## 3) `reasm_data`: когда один payload приходит в нескольких TCP сегментах

Иногда полезная нагрузка не помещается в один TCP сегмент (например TLS ClientHello с kyber).
Тогда zapret2 может собрать несколько сегментов в один “логический payload”:

- `desync.reasm_data` — полный собранный блок

Ключевой момент:
- стратегии типа `multisplit`/`multidisorder` работают “умнее”, если видят `reasm_data`: они режут **весь reasm**, а не только текущий кусок.

## 4) `replay`: почему пакеты иногда “задерживают и переигрывают”

Если нужно сначала накопить части payload (для reasm) или выполнить серию Lua‑инстансов, система может:

1) временно задержать часть пакетов
2) когда готово состояние (`reasm_data`), “переиграть” (replay) эти пакеты

Отсюда поля типа:
- `desync.replay`, `desync.replay_piece`, `desync.replay_piece_count`

И поведение:
- многие стратегии делают основную работу только на `replay_first(...)`, а дальше дропают “повторные” части, потому что уже отправили reasm в нужной форме.

## 5) Маркеры: что это и зачем

Маркеры — это способ указать позицию “логически”, а не байтовым смещением.

Примеры маркеров:
- `method` (HTTP метод)
- `host`, `endhost`, `midsld` (позиции внутри Host/SNI домена)
- `sniext`, `extlen` (TLS структуры)

Можно писать:
- `midsld+1`, `endhost-2`, `-10`, `100`

И использовать в:
- `multisplit:pos=...`
- `multidisorder:pos=...:seqovl=...`

Почему маркер может “не сработать”:
- payload не распознан (l7payload = unknown)
- в payload нет нужной структуры (например нет SNI)
- маркер невалиден для данного payload типа

## 6) Мини‑практика: “проверить, распознан ли payload”

Добавь:
```bash
--lua-desync=luaexec:code="DLOG('l7payload '..tostring(desync.l7payload)..' l7proto '..tostring(desync.l7proto))"
```

И сравни с ожиданиями.

## 7) Что читать дальше

- `[[Zapret2 - 06 - Lua pipeline: инстансы, args, дебаг]]`
- `[[multisplit]]` и `[[multidisorder]]` (там маркеры используются в реальной технике)


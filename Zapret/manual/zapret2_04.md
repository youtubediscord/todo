---
date: 2026-01-21
tags:
  - zapret
  - zapret2
  - lua
  - networking
  - learning
aliases:
  - Zapret2 учебник 04
---
# Zapret2 для новичков — 04: dissect/reconstruct и что такое `desync`

Цель: научиться “читать” то, что видит Lua‑функция, и понимать, откуда берутся поля.

## 1) `desync` — главный объект, который получает Lua

Каждый `--lua-desync=...` вызывает Lua‑функцию вида:

```lua
function something(ctx, desync)
  ...
end
```

`desync` — это таблица, в которой есть:

- `desync.dis` — текущий диссект (структура IP/TCP/UDP/payload)
- `desync.arg` — аргументы текущего инстанса (все строки/флаги)
- `desync.l7payload` / `desync.l7proto` — распознанные типы
- `desync.track` — conntrack‑состояние (может быть nil)
- `desync.reasm_data` / `desync.decrypt_data` — если сработал механизм сборки
- флаги про replay (например `desync.replay`, `desync.replay_piece`, …)

## 2) Что такое `desync.dis` (диссект)

Упрощённо:

- `desync.dis.ip` или `desync.dis.ip6` — IP заголовок
- `desync.dis.tcp` или `desync.dis.udp` — транспортный заголовок
- `desync.dis.payload` — байты полезной нагрузки (string)

Для TCP полезно знать, что:
- `desync.dis.tcp.th_seq`, `th_ack`, `th_flags`, `th_win`, `th_urp` — основные поля
- `desync.dis.tcp.options` — массив tcp‑опций (timestamp, md5, nop, …)

## 3) Почему “диссект” удобнее, чем raw

С raw пакетами неудобно работать:
- нужно помнить смещения полей
- легко ошибиться
- сложно корректно пересчитать checksum

Поэтому zapret2 большую часть модификаций делает так:

1) разобрать → диссект
2) поменять поля в диссекте
3) собрать raw обратно (reconstruct)

## 4) Как debuggить `desync`

Есть готовые функции (в `lua/zapret-lib.lua`):

- `pktdebug` — печатает весь `desync` (большой вывод)
- `argdebug` — печатает только `desync.arg`
- `posdebug` — печатает счётчики conntrack и наличие `reasm/decrypt/replay`

Минимальные “учебные” вставки:

```bash
--lua-desync=argdebug
--lua-desync=posdebug
```

## 5) Что такое “standard args”

Многие стратегии (`fake`, `multisplit`, `multidisorder`) принимают одинаковые “блоки” аргументов:

- direction (dir=in/out/any)
- payload (payload=...)
- fooling (ttl, md5, flags, badsum, …)
- ipid (ip_id=seq/rnd/…)
- rawsend (repeats/ifout/fwmark)
- ipfrag (ipfrag_pos_tcp/…)

Почему так сделано:
- проще комбинировать техники,
- один и тот же механизм отправки/реконструкции применяет эти опции одинаково.

## 6) Что читать дальше

- `[[Zapret2 - 05 - Payload types, reasm/replay и маркеры]]`
- `[[Zapret2 - lua-desync]]`


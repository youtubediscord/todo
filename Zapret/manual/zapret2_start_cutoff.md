---
date: 2026-01-21
tags:
  - zapret
  - zapret2
  - winws2
  - nfqws2
  - learning
aliases:
  - Zapret2 start cutoff
  - Zapret2 n2 n3 clienthello
---
# Zapret2: start/cutoff и почему `n2<n3` “вдруг” попадает на ClientHello

Эта заметка — ответ на типичную ситуацию:

```text
--filter-tcp=443 --payload=all --out-range="n1<n2" --lua-desync=send:ip_ttl=1
```
→ дюпается SYN

```text
--filter-tcp=443 --payload=all --out-range="n2<n3" --lua-desync=send:ip_ttl=1
```
→ дюпается ClientHello, хотя “по идее должен ACK”

## 1) Ключевой факт: `n` — это номер ПЕРЕХВАЧЕННОГО пакета, а не “всех пакетов TCP”

`--out-range` работает по счётчикам conntrack **внутри движка**.
Счётчик `n` увеличивается только на те исходящие пакеты, которые:

1) реально перехвачены (NFQUEUE/WinDivert), и
2) реально дошли до обработки профилем (фильтры не выкинули их раньше).

Если какой-то пакет “не попал” — он **не существует** для счётчика `n`.

## 2) Почему именно ACK часто “пропадает”

### Windows / winws2
В winws2 по умолчанию часто включено:

- `--wf-tcp-empty=0`

Это не перехватывает пустые TCP ACK (ACK без payload).
Сильный профит по CPU, но `n` перестаёт совпадать с тем, что вы ожидаете как “номер пакета в соединении”.

Итог: исходящий порядок “в движке” становится таким:

- `n1` = SYN (перехвачен)
- `n2` = ClientHello (первый перехваченный packet с данными)

А “реальный” handshake ACK существует, но не перехвачен.

### Linux / nfqws2
Если ваши правила NFQUEUE (nft/iptables) перехватывают только “пакеты с данными” или только часть фаз — ситуация аналогичная:
ACK просто не попадёт в userspace, и `n` сдвинется.

## 3) Вторая причина (реже): ACK может быть “склеен” с ClientHello

Иногда стек может отправить ACK на SYN-ACK вместе с первым сегментом данных (ACK+payload).
Тогда “второй исходящий пакет” реально будет ClientHello (и это нормально).
Проверяется только захватом трафика (Wireshark).

## 4) Эквивалент `nfqws1 --dup-start=n2 --dup-cutoff=n3` в zapret2

Если вы хотите **строго** применить действие к “2-му исходящему пакету” по счётчику `n`:

```bash
--out-range="n2<n3" --lua-desync=send:ip_ttl=1
```

Но это будет работать “как ожидаете” только если этот пакет реально перехвачен.

## 5) Как применить “дурение” именно ко 2-му исходящему ACK (если он пустой)

### Вариант A (Windows / winws2): включить перехват пустых ACK

1) включить перехват пустых TCP пакетов:
```bash
--wf-tcp-empty=1
```

2) сузить по типу payload (очень полезно, чтобы убедиться что вы бьёте именно по пустому):
```bash
--payload=empty --out-range="n2<n3" --lua-desync=send:ip_ttl=1
```

Если после этого “ничего не дюпается” — значит либо ACK не перехвачен фильтрами, либо ACK не пустой.

### Вариант B: если цель — “первый пакет с данными” (ClientHello), используйте `d`

Это устойчиво даже если пустые ACK не перехватываются:

```bash
--payload=tls_client_hello --out-range="d1<d2" --lua-desync=send:ip_ttl=1
```

## 6) Самый быстрый способ понять, что реально происходит

Добавьте на время дебага:

```bash
--lua-desync=posdebug
--lua-desync=luaexec:code="DLOG('flags '..tostring(desync.dis.tcp and desync.dis.tcp.th_flags)..' payload '..#desync.dis.payload..' l7payload '..tostring(desync.l7payload))"
```

И смотрите:
- какая длина payload у “n2”
- какой `l7payload` (empty/tls_client_hello/unknown)
- увеличивается ли `n` на пустых ACK


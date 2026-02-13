---
date:
tags:
link:
aliases:
img:
---
# Внутренние фильтры WinDivert
В `zapret\windivert.filter\*.txt` лежат WinDivert raw-фильтры — они отбирают пакеты по L3/L4 (ip/ipv6, tcp/udp, порты, inbound/outbound) и иногда по «сигнатурам» в payload. Доменного имени в IP‑пакетах нет, поэтому напрямую “по домену” в WinDivert‑фильтре обычно не фильтруют.

Домены: делаются на уровне winws/winws2 через [[Zapret2 - filter#10. **`--hostlist`** - Включающий список доменов|--hostlist]] / [[Zapret2 - filter#11. **`--hostlist-domains`** - Фиксированный список доменов|--hostlist-domains]].

IP/подсети: можно фильтровать и в WinDivert‑фильтре (ip.DstAddr, ip.SrcAddr, ipv6.DstAddr, ipv6.SrcAddr), и (часто удобнее) через --ipset.

--wf-raw-part в запрете (и --wf-raw) используют обычный язык фильтров WinDivert — это и есть “raw фильтр”.

Подсети делать можно, но обычно через диапазон адресов, т.к. в WinDivert нет побитовых операций (маской “& 255.255.255.0” не сделать).

Пример raw-part (исходящие на 80/443 TCP и 443 UDP, только в одну подсеть /24):
```
outbound and ip and
(
  (tcp and (tcp.DstPort == 80 or tcp.DstPort == 443)) or
  (udp and udp.DstPort == 443)
) and
(ip.DstAddr >= 93.184.216.0 and ip.DstAddr <= 93.184.216.255)
```
Несколько подсетей — просто or:
```
outbound and ip and tcp and (tcp.DstPort == 443) and
(
  (ip.DstAddr >= 93.184.216.0 and ip.DstAddr <= 93.184.216.255) or
  (ip.DstAddr >= 151.101.0.0 and ip.DstAddr <= 151.101.255.255)
)
```

Шпаргалка по диапазонам:
```
A.B.C.0/24 -> >= A.B.C.0 и <= A.B.C.255
A.B.0.0/16 -> >= A.B.0.0 и <= A.B.255.255
```

пример как у LAN: `172.16.0.0/12 -> 172.16.0.0...172.31.255.255`

## Зачем это нужно?
Благодаря фильтрам можно добиться идеальной производительности даже если вы активно раздаете торренты

![[Pasted image 20260213230109.png]]

Без фильтров иногда программе бывает тяжело

![[Pasted image 20260213230115.png]]
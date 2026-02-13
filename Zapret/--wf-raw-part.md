---
date:
tags:
link:
aliases:
img:
---
# Внутренние фильтры WinDivert
В `zapret\windivert.filter\*.txt` лежат WinDivert raw-фильтры — они отбирают пакеты по L3/L4 (ip/ipv6, tcp/udp, порты, inbound/outbound) и иногда по «сигнатурам» в payload. Доменного имени в IP‑пакетах нет, поэтому напрямую “по домену” в WinDivert‑фильтре обычно не фильтруют.

Домены: делаются на уровне winws/winws2 через `--hostlist` / `--hostlist-domains`.

IP/подсети: можно фильтровать и в WinDivert‑фильтре (ip.DstAddr, ip.SrcAddr, ipv6.DstAddr, ipv6.SrcAddr), и (часто удобнее) через --ipset.

--wf-raw-part в запрете (и --wf-raw) используют обычный язык фильтров WinDivert — это и есть “raw фильтр”.

Подсети делать можно, но обычно через диапазон адресов, т.к. в WinDivert нет побитовых операций (маской “& 255.255.255.0” не сделать).

Пример raw-part (исходящие на 80/443 TCP и 443 UDP, только в одну подсеть /24):

outbound and ip and
(
  (tcp and (tcp.DstPort == 80 or tcp.DstPort == 443)) or
  (udp and udp.DstPort == 443)
) and
(ip.DstAddr >= 93.184.216.0 and ip.DstAddr <= 93.184.216.255)
---
date: 2026-07-11
tags:
  - hysteria
  - tproxy
  - прозрачный-прокси
  - linux
  - iptables
aliases:
  - Hysteria TPROXY
  - Hysteria прозрачный прокси
  - Hysteria透明代理
link: https://v2.hysteria.network/docs/advanced/TPROXY/
---

# 🦎 Hysteria 2 — прозрачный прокси (TPROXY)

> [!info] О чём заметка
> Как настроить прозрачный проксирование (TPROXY) на клиенте Hysteria 2 под Linux: завернуть весь TCP/UDP-трафик устройства или локальной сети через Hysteria без настройки прокси в каждом приложении. Только Linux. Базовый клиентский конфиг — в [[Hysteria/config-client|отдельной заметке]]. Обзор протокола — [[Hysteria/00-overview|тут]].

## TL;DR

- **TPROXY** — механизм ядра Linux для прозрачного перехвата TCP и UDP: приложения даже не знают, что идут через прокси, настраивать их не нужно.
- В отличие от [[Hysteria/config-client|TUN-режима]], TPROXY не создаёт виртуальный интерфейс, а работает через правила фаервола (iptables/nftables) и policy routing. Это классический способ поднять прозрачный прокси на роутере/шлюзе.
- В клиентском конфиге добавляются `tcpTProxy`/`udpTProxy` с портом (в примерах — `2500`). Но само по себе это не работает — **обязательны** правила policy routing и iptables/nftables.
- Чтобы проксировать трафик самого устройства (а не только проходящий через него), запускайте клиент **от отдельного пользователя** и исключайте его трафик по uid — иначе получите петлю.

## TPROXY против TUN — что выбрать

Обе технологии делают одно: заворачивают весь трафик через Hysteria без настройки прокси в приложениях. Разница в механике:

- **[[Hysteria/config-client|TUN]]** — кроссплатформенный (Windows/Linux/macOS), создаёт виртуальный сетевой интерфейс, Hysteria сама поднимает адреса и маршруты. Проще в настройке, подходит для клиентского устройства.
- **TPROXY** — только Linux, работает через фаервол и таблицы маршрутизации, ничего виртуального не создаёт. Традиционный выбор для **шлюза/роутера**, который проксирует трафик всей локальной сети. Тоньше настраивается, но требует ручных правил iptables/nftables.

Если нужен прозрачный прокси на одном устройстве — часто проще TUN. Если строите шлюз для всей сети на Linux — TPROXY.

## Шаг 1. Отдельный пользователь (чтобы не было петли)

> [!warning] Этот шаг обязателен, если проксируете трафик самого устройства
> Когда через прокси идёт в том числе собственный трафик машины, где крутится клиент, надо отделить трафик самого Hysteria-клиента (он идёт до вашего сервера) от проксируемого трафика. Иначе пакеты Hysteria до сервера снова попадут в перехват — получится петля. Способ — запускать клиент под выделенным пользователем и исключать его по uid в правилах фаервола. Если проксируете только трафик, проходящий через устройство (например, роутер для других хостов), этот шаг можно пропустить.

Создайте системного пользователя:

```bash
useradd --system hysteria
```

Выдайте бинарнику нужные capabilities (повторять после каждого ручного обновления клиента):

```bash
setcap CAP_NET_ADMIN,CAP_NET_BIND_SERVICE+ep /path/to/hysteria
```

Запускайте клиент под этим пользователем — вручную `sudo -u hysteria /path/to/hysteria -c config.yaml`, либо в systemd-юните добавьте `User=hysteria` в секцию `[Service]`.

## Шаг 2. Конфиг клиента

В [[Hysteria/config-client|клиентский config.yaml]] добавьте TPROXY-инбаунды (порт `2500` — пример, можно любой):

```yaml
tcpTProxy:
  listen: :2500

udpTProxy:
  listen: :2500
```

Не указывайте IP перед `:` — тогда слушается и IPv4, и IPv6. Если UDP проксировать не нужно, оставьте только `tcpTProxy`.

## Шаг 3. Policy routing (обязательно)

> [!danger] Без этого шага TPROXY не работает
> Одних строк в конфиге недостаточно. Правила маршрутизации и фаервола — **не опциональны**. Кроме того, все команды из шагов 3 и 4 сбрасываются при перезагрузке — их нужно либо выполнять при каждом старте системы, либо сделать постоянными (через systemd-юнит, `/etc/network` hooks, скрипты дистрибутива и т.п.).

Тут `0x1` — метка (fwmark), `100` — id таблицы маршрутизации (можно выбрать другие):

```bash
# IPv4
ip rule add fwmark 0x1 lookup 100
ip route add local default dev lo table 100

# IPv6
ip -6 rule add fwmark 0x1 lookup 100
ip -6 route add local default dev lo table 100
```

## Шаг 4. iptables или nftables (обязательно)

Правила перенаправляют трафик на TPROXY-порт, обходя приватные адреса и уже обработанный трафик. Ниже — вариант nftables (компактнее); полные примеры iptables для IPv4 и IPv6 — в [официальной документации TPROXY](https://v2.hysteria.network/docs/advanced/TPROXY/).

```nginx
define TPROXY_MARK=0x1
define HYSTERIA_USER=hysteria
define HYSTERIA_TPROXY_PORT=2500

define TPROXY_L4PROTO={ tcp, udp }

define BYPASS_IPV4={
    0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16,
    172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3
}
define BYPASS_IPV6={ ::/128 }

table inet hysteria_tproxy {
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;

    # Пропустить трафик, уже обработанный TProxy
    meta l4proto $TPROXY_L4PROTO socket transparent 1 counter mark set $TPROXY_MARK
    socket transparent 0 socket wildcard 0 counter return

    # Обойти приватные и специальные адреса
    ip daddr $BYPASS_IPV4 counter return
    ip6 daddr $BYPASS_IPV6 counter return
    ip6 daddr != 2000::/3 counter return

    # Перенаправить трафик на TProxy-порт
    meta l4proto $TPROXY_L4PROTO counter tproxy to :$HYSTERIA_TPROXY_PORT meta mark set $TPROXY_MARK accept
  }
}
```

Это правила для трафика, **проходящего через** устройство. Чтобы проксировать ещё и трафик самого устройства, добавляется отдельная таблица с хуком `output`, где по `meta skuid $HYSTERIA_USER ... return` исключается трафик самого клиента (тот самый анти-петля механизм из шага 1). Полный набор — в официальной документации.

> [!note] Если не нужен UDP
> Чтобы не проксировать UDP, замените набор протоколов на только TCP: `define TPROXY_L4PROTO=tcp` (в iptables — уберите строки с `-p udp`). Для IPv6 в правилах намеренно проксируются только публичные адреса (`2000::/3`), локальные обходятся.

## 📚 См. также

- [[Hysteria/config-client|Конфиг клиента]] — базовые режимы, включая кроссплатформенный TUN как более простую альтернативу.
- [[Hysteria/acl-outbounds|ACL и маршрутизация]] — серверная маршрутизация: что делать с трафиком уже после того, как он дошёл до сервера.
- [[Hysteria/00-overview|Hysteria 2 — обзор]] — общая картина.
- 🔗 [Setting up TPROXY — официальная документация](https://v2.hysteria.network/docs/advanced/TPROXY/)

---

> [!quote] 🤖 Эти статьи открыты — можно обучать на них ИИ
> При желании вы можете натренировать ИИ на наших статьях. Исходное форматирование и скачивание всего репозитория одним zip-архивом доступны на GitHub: [исходник этой заметки](https://github.com/youtubediscord/todo/blob/main/Hysteria/tproxy.md) · [весь репозиторий](https://github.com/youtubediscord/todo/tree/main).

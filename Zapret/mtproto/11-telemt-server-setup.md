---
date: 2026-06-08
tags:
  - mtproto
  - mtproxy
  - telemt
  - dpi
  - tspu
  - runbook
  - ufw
  - firewall
aliases:
  - telemt продакшн-развёртывание
  - telemt 3 инстанса UFW
  - telemt client_mss tspu
  - telemt rate-limit per-port
  - telemt keepalive iOS
  - telemt gamma 5223 профиль
link: https://assyoucandy.github.io/telemt-server-guide/
---

# 🚀 telemt — продакшн-развёртывание (3 инстанса + UFW + анти-DPI)

> [!info] О чём заметка
> Боевой runbook установки **telemt** (Rust MTProxy) с нуля на Ubuntu: несколько инстансов на разных портах и доменах, systemd-автозапуск, и **три слоя защиты от DPI ТСПУ** — настоящий TLS-фронтинг, `client_mss="tspu"` (дробление ClientHello аномально малым MSS) и **per-port rate-limit входящих SYN** на фаерволе. Плюс отдельный фикс зависаний на iOS. Базовая установка telemt (Docker, REST API) — в [[Zapret/mtproto/03-telemt|03-telemt]]; здесь — про *развёртывание под нагрузку и закалку от блокировок*.

> [!warning] Что из этого реально лечит, а что нет
> `client_mss` и rate-limit **не меняют JA4-почерк** клиента Telegram. `client_mss` лишь мешает цензору *извлечь* почерк из первого пакета (а сам малый MSS — уже аномалия, см. Шаг 4); rate-limit троттлит только повторные SYN **с одного IP** (первый SYN всегда проходит; распределённое зондирование и агрегатный «залп» от множества клиентов он не трогает). Против DPI с полной пересборкой TCP-потока фрагментация не спасает. Полный разбор, кто и почему может сменить JA4/SNI, — в [[mtproxy/ja4-sni-client-side|ja4-sni-client-side]]. Параметры детекта — наблюдения сообщества (июнь 2026), не спецификация ТСПУ.

---

## Термины (чтобы заметка читалась без контекста)

- **MTProxy / telemt** — прокси для Telegram. telemt — реализация на Rust с «настоящим» TLS-фронтингом: реально подтягивает и эмулирует сертификат маскировочного домена (apple.com, cloudflare.com), а не подделывает его.
- **ClientHello** — первый, ещё не зашифрованный пакет TLS-рукопожатия от клиента; в нём шифры, расширения и **SNI** (имя домена). По нему DPI считает **JA4**.
- **JA4** — хеш-отпечаток ClientHello; по нему DPI узнаёт программу-источник.
- **MSS** (Maximum Segment Size) — максимальный размер TCP-сегмента. Маленький MSS заставляет клиента **резать ClientHello на несколько пакетов**.
- **ТСПУ** — DPI-оборудование у российских операторов.
- **xt_recent** — модуль ядра Linux, ведёт список «кто недавно стучался»; на нём строится rate-limit «не больше 1 нового соединения в секунду с одного IP».
- **UFW** — обёртка над iptables/nftables; правила живут в `/etc/ufw/before.rules`.

---

## TL;DR

1. Ставим telemt-бинарник, поднимаем **3 инстанса** (порты 443 / 5223 / 8530, домены cloudflare / apple / microsoft) — запас, если один порт начнут душить.
2. Каждый инстанс — отдельный **systemd-сервис** под пользователем `telemt` (не root), с автоперезапуском.
3. **Анти-DPI слой 1 — TLS-фронтинг** (`tls_emulation`, `unknown_sni_action`): на чужой/зондирующий SNI отвечаем как настоящий веб-сервер.
4. **Анти-DPI слой 2 — `client_mss="tspu"` (MSS=92)**: ClientHello рвётся на куски, и DPI не вычитывает JA4 из первого пакета (ставка на то, что он не пересобирает поток; сам малый MSS — аномалия). Тот же приём, что [[mtproxy/mtproto-zig-setup#Шаг 4. TCPMSS — дробление ClientHello|TCPMSS=88 в mtproto.zig]] и `TCP_MAXSEG=256` в teleproxy (256 дробит грубее — 2-3 сегмента против 5-6).
5. **Анти-DPI слой 3 — UFW rate-limit**: не больше **1 нового SYN/сек с одного IP на каждый порт** (через `xt_recent`) — троттлит быстрые реконнекты и простое зондирование **с фиксированного IP**; против распределённого зондирования и агрегатного «залпа» от множества клиентов почти не помогает (первый SYN проходит).
6. **Фикс iOS** — ускоренный TCP keepalive через sysctl: ядро быстро рвёт мёртвый сокет, клиент делает чистый реконнект.
7. Главные грабли: **разреши SSH до `ufw enable`**; **загрузи `xt_recent` до `ufw reload`** (иначе UFW молча выбросит правила); rate-limit — **раздельные списки на каждый порт**, иначе переключение прокси в Telegram рвёт коннект.

---

## Шаг 1. Подготовка системы

```bash
apt update
apt install -y wget tar jq ufw python3 iptables

# отдельный системный пользователь без shell + рабочие директории
id telemt &>/dev/null || useradd -r -s /usr/sbin/nologin -d /opt/telemt telemt
mkdir -p /opt/telemt /etc/telemt
chown -R telemt:telemt /opt/telemt /etc/telemt
```

> [!tip] Почему не под root
> Демон, смотрящий в интернет, не должен иметь прав root. Отдельный пользователь `telemt` + `NoNewPrivileges` в systemd (ниже) ограничивают ущерб при взломе.

---

## Шаг 2. Установка бинарника

```bash
cd /tmp
wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-x86_64-linux-gnu.tar.gz" | tar -xz
mv /tmp/telemt /bin/telemt
chmod +x /bin/telemt
/bin/telemt --version    # должно вывести: telemt 3.4.15 (или новее)
```

---

## Шаг 3. Генерация секретов

Секрет MTProxy — 16 байт = 32 hex-символа. На каждый инстанс — свой:

```bash
for i in 1 2 3; do echo "user$i = $(openssl rand -hex 16)"; done
```

Запиши вывод — каждая строка `user1 = a1b2c3…` пойдёт в свой конфиг. Полную клиентскую ссылку (`ee` + 32 hex + hex домена) telemt соберёт сам, отдаст через API.

---

## Шаг 4. Конфиги инстансов

Гайд генерирует три `.toml` одной python-командой (надёжнее, чем `cat << EOF`, который на мобильных SSH-клиентах склеивает строки). **Подставь свои секреты** из шага 3 в блок `configs`:

```python
python3 << 'PYEOF'
# номер: (порт, домен, api_порт, секрет_32hex) — ПОДСТАВЬ СВОИ СЕКРЕТЫ
configs = {
    1: (443,  "www.cloudflare.com", 9091, "СЕКРЕТ_1"),
    2: (5223, "www.apple.com",      9092, "СЕКРЕТ_2"),
    3: (8530, "www.microsoft.com",  9093, "СЕКРЕТ_3"),
}
for n, (port, domain, api, secret) in configs.items():
    cfg = f"""[general]
fast_mode = true
use_middle_proxy = false
[general.modes]
classic = false
secure = false
tls = true
[network]
ipv4 = true
ipv6 = false
prefer = 4
[server]
port = {port}
listen_addr_ipv4 = "0.0.0.0"
client_mss = "tspu"
[server.api]
enabled = true
listen = "127.0.0.1:{api}"
whitelist = ["127.0.0.1/32"]
[censorship]
tls_domain = "{domain}"
mask = true
mask_port = 443
tls_emulation = true
unknown_sni_action = "reject_handshake"
fake_cert_len = 2048
[access]
replay_check_len = 65536
ignore_time_skew = false
[access.users]
user{n} = "{secret}"
"""
    open(f"/etc/telemt/telemt{n}.toml", "w").write(cfg)
    print(f"telemt{n}: порт {port}, {domain}, api {api} — OK")
PYEOF
chown -R telemt:telemt /etc/telemt
```

Что делают ключевые параметры:

| Параметр | Что делает |
|---|---|
| `client_mss = "tspu"` | MSS=92 — режет ClientHello на куски, чтобы stateless-DPI не вычитал JA4 из первого пакета (сам малый MSS аномален, см. ниже) |
| `tls_emulation = true` | подтягивает **реальный** сертификат домена и эмулирует его |
| `unknown_sni_action = "reject_handshake"` | на «левый»/зондирующий SNI отвечает как обычный веб-сервер (анти-probing) |
| `mask = true` / `mask_port = 443` | куда telemt ходит за маской: реальный сайт `tls_domain` на 443 (одинаков для всех инстансов — это норма) |
| `fast_mode = true` | упрощённый прямой режим; за отсутствие рекламной статистики отвечает именно `use_middle_proxy = false` (middle-proxy подмешивает спонсорские каналы) |
| `replay_check_len = 65536` | защита от replay-атак активного зондирования |
| `server.api` | локальный API статистики и ссылок, **только** `127.0.0.1` |

> [!example] `client_mss="tspu"` на пальцах — и чего он НЕ делает
> Представь, что визитку гостя (ClientHello с JA4) охранник читает, только если она пришла **одним листом**. MSS=92 заставляет клиента порезать визитку на ~5-6 узких полосок-пакетов: охранник, читающий лишь первый, **не собирает почерк**. Но JA4 при этом **не изменился** — если у охранника есть «склейка» (полная пересборка TCP-потока), он соберёт полоски и прочтёт всё. Поэтому это **выигрыш времени и обход простого DPI**, а не смена почерка.
>
> ⚠️ И это **не маскировка под браузер**: настоящие браузеры шлют сегменты ~1380 байт, а MSS=92 — глубоко аномальное значение, которого в обычном вебе не бывает, то есть **сам по себе может быть признаком** (в исходниках mtproto.zig это прямо отмечено про MSS=88). Плюс мелкий MSS клампит **все** сегменты к клиенту, не только ClientHello — это накладные расходы на каждый пакет; если связь деградирует, подними значение или отключи `client_mss`. Кто реально может сменить JA4 — [[mtproxy/ja4-sni-client-side|только клиент]].

---

## Шаг 5. systemd-сервисы

По сервису на инстанс, автозапуск + перезапуск при падении + капабилити для bind на привилегированные порты (443):

```python
python3 << 'PYEOF'
descs = {1: "443 cloudflare", 2: "5223 apple", 3: "8530 microsoft"}
for n, d in descs.items():
    svc = f"""[Unit]
Description=Telemt Proxy {n} ({d})
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=telemt
Group=telemt
WorkingDirectory=/opt/telemt
ExecStart=/bin/telemt /etc/telemt/telemt{n}.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=65536
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
[Install]
WantedBy=multi-user.target
"""
    open(f"/etc/systemd/system/telemt{n}.service", "w").write(svc)
PYEOF
systemctl daemon-reload
```

`CAP_NET_BIND_SERVICE` нужен для bind на привилегированный порт 443 (юзер `telemt` — не root). `CAP_NET_ADMIN` присутствует в юните из гайда **без объяснения**, и для `client_mss` он, скорее всего, **не требуется**: MSS на сокете задаётся через `setsockopt(TCP_MAXSEG)` — это непривилегированная опция (там, где MSS клампят netfilter-правилом, как `--set-mss 88` в mtproto.zig, это отдельный install-шаг от root, а не капабилити демона).

> [!warning] CAP_NET_ADMIN — широкая капабилити, не «узкий доступ к MSS»
> Она даёт управление **всей** сетевой подсистемой (интерфейсы, маршрутизация, netfilter, BPF, promisc) — при RCE это почти эквивалентно root по сети и обнуляет смысл запуска не под root. Если telemt стартует без неё — **убери `CAP_NET_ADMIN`** из `AmbientCapabilities`/`CapabilityBoundingSet`, оставив только `CAP_NET_BIND_SERVICE`. Если без неё не стартует (`EPERM` в `journalctl`) — оставь, но как наблюдение, а не как «нужна для MSS».

---

## Шаг 6. UFW — порты и защита от зондирования

> [!danger] Сначала SSH, потом enable
> Разреши SSH-порт **до** `ufw enable`, иначе отрежешь себе доступ к серверу. Если SSH не на 22 — поставь свой.

```bash
ufw allow 22/tcp           # SSH — первым делом
ufw allow 443/tcp
ufw allow 5223/tcp
ufw allow 8530/tcp
ufw --force enable
ufw status
```

### Rate-limit: 1 SYN/сек с IP на каждый порт

Троттлит быстрые реконнект-штормы и простое зондирование **с одного IP**. Важно честно понимать границы (правило пропускает первый SYN и считает по source-IP):

- ❌ **не** ловит распределённое зондирование РКН (1 probe = 1 SYN с нового IP — проходит);
- ❌ **не** размывает агрегатный «залп» от множества клиентов (его ТСПУ считает по SNI на своей стороне, а не по source-IP на сервере — это работа pacing/разных портов, см. [[Zapret/mtproto/10-telemt-logs-dpi|10-telemt-logs-dpi]]);
- ✅ реально режет шторм реконнектов/коннектов с **одного** адреса.

> [!danger] Осторожно за CGNAT (мобильные операторы РФ)
> За одним публичным IP оператора сидят десятки-сотни абонентов. Жёсткий лимит «1 SYN/сек на IP» будет **дропать коннекты легитимных пользователей** с того же адреса (а целевая аудитория прокси — как раз мобильные RU-сети). Туда же — ретрансмит SYN при потерях на канале (повтор в окне 1 с попадёт под DROP и затянет установку). При жалобах на нестабильность ослабь правило (подними `--seconds`/добавь `--hitcount`) или сними rate-limit с части портов.

Сначала — модуль ядра и бэкап:

```bash
modprobe xt_recent
echo xt_recent > /etc/modules-load.d/xt_recent.conf
cp /etc/ufw/before.rules /etc/ufw/before.rules.bak.$(date +%s)
lsmod | grep xt_recent      # ДОЛЖЕН вывести строку — иначе правила не подтянутся
```

> [!danger] Без `xt_recent` правила тихо пропадают
> Если `lsmod | grep xt_recent` пустой — модуль не загружен, и UFW при `reload` **молча выбросит** правила с `-m recent`. Сначала добейся, чтобы `modprobe` прошёл и `lsmod` показал модуль, и только потом `ufw reload`.

Вставка правил в `ufw-before-input` (после established). **Каждому порту — свой список** (`mtp443`, `mtp5223`…):

```python
python3 << 'PYEOF'
PORTS = [443, 5223, 8530]   # ← СВОИ ПОРТЫ
path = "/etc/ufw/before.rules"
lines = open(path).readlines()
if any("MTProto rate-limit" in l for l in lines):
    print("правила уже есть, пропуск"); raise SystemExit
idx = None
for i, l in enumerate(lines):
    if "ufw-before-input -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT" in l:
        idx = i + 1; break
if idx is None:
    print("ОШИБКА: точка вставки не найдена"); raise SystemExit
block = ["\n# === MTProto rate-limit (1 SYN/сек на IP per-port) ===\n"]
for p in PORTS:
    block.append(f"-A ufw-before-input -p tcp --dport {p} --syn -m recent --name mtp{p} --rcheck --seconds 1 -j DROP\n")
    block.append(f"-A ufw-before-input -p tcp --dport {p} --syn -m recent --name mtp{p} --set -j ACCEPT\n")
block.append("# === конец MTProto rate-limit ===\n")
lines[idx:idx] = block
open(path, "w").writelines(lines)
PYEOF
ufw reload
```

> [!warning] Тонкость per-port — иначе Telegram «отваливается»
> Один общий список на все порты ломает переключение прокси: Telegram при смене прокси шлёт SYN на несколько портов **одновременно с одного IP в одну секунду**, общий лимит рубит лишние — и прокси отваливается. Раздельные списки решают это.

> [!note] Связь с лимитом SYN-ACK
> Здесь ограничиваются **входящие** SYN (по IP-источнику). Это родственник, но не то же самое, что **исходящий** лимит SYN-ACK из [[Zapret/mtproto/10-telemt-logs-dpi#Лимит SYN-ACK — помогает или нет|10-telemt-logs-dpi]] (там цель — заставить DPI ретрансмитить и десинхронизироваться). Считают они по-разному (входной SYN-лимит — по **source-IP**, SYN-ACK-лимит — **по порту**), но **ни один не агрегирует по SNI** на стороне сервера — поэтому против межклиентского «залпа» на один SNI оба бессильны; для этого нужны pacing и разнос по портам/доменам.

---

## Шаг 7. Запуск и проверка

```bash
systemctl enable telemt1 telemt2 telemt3
systemctl start  telemt1 telemt2 telemt3
sleep 3
systemctl is-active telemt1 telemt2 telemt3        # три раза active

ss -tlnp | grep -E ':443|:5223|:8530'              # порты слушает telemt
iptables -L ufw-before-input -n | grep recent      # правила rate-limit живы
ls -la /opt/telemt/tlsfront/                        # подтянутые серты доменов (.json, десятки КБ)
journalctl -u telemt1 -n 20 --no-pager | grep -iE "error|panic|bind"
```

**Признаки успеха:** три `active`; в `/opt/telemt/tlsfront/` лежат `www.apple.com.json` и др.; `Skipping IPv6 listener` — это норма (IPv6 выключен).

> [!tip] Если правил rate-limit не видно (grep по recent пустой)
> Две частые причины: (1) **`xt_recent` не был загружен** на момент `ufw reload` — UFW тихо отбросил правила → `modprobe xt_recent` + `ufw reload`; (2) система на **nftables** (Ubuntu 22.04+) — правило работает, просто `iptables -L` его не показывает; смотри через `nft list chain inet filter ufw-before-input | grep -i recent`.

---

## Шаг 8. Ссылки для клиентов

Ссылки telemt собирает сам — берём из API каждого инстанса (только IPv4-вариант):

```bash
for p in 9091 9092 9093; do
  curl -s http://127.0.0.1:$p/v1/users \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['data'][0]['links']['tls'][0])"
done
```

Вывод — готовые `tg://proxy?server=IP&port=…&secret=ee…`, открываются в один тап. IP можно заменить на домен, если он указывает на сервер.

---

## Фикс зависаний на iOS (отдельный слой)

**Симптом:** на iOS Telegram перестаёт коннектиться к прокси после сворачивания приложения — помогает только переключение на другой прокси.

**Причина:** iOS усыпляет приложение и рвёт сокет «не чисто». Сервер держит мёртвый `established`-коннект, при возврате клиент залипает на нём.

**Решение:** ускоренный TCP keepalive. telemt ставит `SO_KEEPALIVE`, и ядро само быстро пробивает тихий коннект, рвёт его RST-ом за ~105с (60 + 15×3, **худший случай при полном молчании сокета** — при активном трафике таймер сбрасывается) — клиент делает чистый реконнект. Это **системные дефолты** keepalive: применятся к любому сокету с `SO_KEEPALIVE` (в т.ч. `sshd`), а не только к telemt — но затрагивают лишь интервалы проб тишины, активные соединения не рвут:

```bash
cat > /etc/sysctl.d/99-tg-keepalive.conf << 'EOF'
net.ipv4.tcp_keepalive_time = 60
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_keepalive_probes = 3
EOF
sysctl --system
```

> [!note] Это другой слой
> Keepalive лечит **залипание клиента на мёртвом сокете**, а не DPI-детект выше по пути. Не путать со слоями анти-DPI.

---

## Управление и обновление

```bash
# статистика по инстансу
curl -s http://127.0.0.1:9091/v1/users | jq '.data[] | {user:.username, conns:.current_connections, ips:.active_unique_ips}'
curl -s http://127.0.0.1:9091/v1/stats/summary | jq '.data'

# обновление telemt (с остановкой инстансов)
cd /tmp
wget -qO- "https://github.com/telemt/telemt/releases/latest/download/telemt-x86_64-linux-gnu.tar.gz" | tar -xz
systemctl stop  telemt1 telemt2 telemt3
mv /tmp/telemt /bin/telemt && chmod +x /bin/telemt
systemctl start telemt1 telemt2 telemt3
/bin/telemt --version

# рестарт / логи
systemctl restart telemt{1,2,3}      # все сразу
journalctl -u telemt1 -f             # логи в реальном времени
```

После правки конфига — `systemctl restart telemtN`. Активные клиенты переподключатся не сразу (возможно, придётся переоткрыть Telegram). Ссылки не меняются, если не трогал секрет / порт / домен.

---

## Боевой профиль Gamma / 5223: самый удачный вариант из тестов

На сервере `150.241.74.213` лучший практический результат дал не максимально жёсткий профиль из базового гайда, а более мягкая настройка **второго инстанса** `telemt2` на порту `5223`:

```toml
[server]
public_port = 5223
port = 5223
client_mss = ""

[censorship]
tls_domain = "www.apple.com"
mask = true
mask_port = 443
unknown_sni_action = "mask"
```

Что здесь важно:

| Настройка | Почему так |
|---|---|
| `5223` | запасной порт Telegram/Apple Push, часто выглядит менее подозрительно, чем случайный высокий порт |
| `tls_domain = "www.apple.com"` | маскировка под обычный TLS к Apple; для `5223` в тесте это оказалось устойчивее |
| `unknown_sni_action = "mask"` | на неожиданный SNI не рубим рукопожатие, а отвечаем маской; это помогло реальным клиентам, у которых SNI приходил неидеально |
| `client_mss = ""` | отключаем MSS-дробление именно на `5223`; в тесте это снизило пинг и не ломало соединение |
| `mask = true` / `mask_port = 443` | telemt ходит за настоящей TLS-маской на сайт из `tls_domain` |

> [!important] Почему это не противоречит базовому гайду
> `client_mss="tspu"` и `unknown_sni_action="reject_handshake"` — хороший **жёсткий анти-DPI профиль**, но он может ухудшать реальную пользовательскую связь: первый коннект становится дольше, пинг растёт, а часть клиентов чаще упирается в `Telegram handshake timeout`. Для рабочего публичного прокси цель не «максимально жёстко любой ценой», а **достаточно похоже на обычный трафик и при этом не ломает пользователей**. Поэтому `5223` лучше держать мягким и быстрым, а более жёсткие варианты оставить на других портах как запас.

### Сетевой профиль ядра для меньшего пинга

На этом же сервере заметное улучшение дал BBR + fq:

```bash
cat > /etc/sysctl.d/98-vpnbot-telemt-bbr.conf << 'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
EOF

cat > /etc/modules-load.d/vpnbot-telemt-bbr.conf << 'EOF'
tcp_bbr
sch_fq
EOF

modprobe tcp_bbr
modprobe sch_fq
sysctl --system
```

- **BBR** — алгоритм управления TCP-скоростью: старается держать канал заполненным, но не раздувать очередь пакетов до огромной задержки.
- **fq** — дисциплина очереди, которая честнее раскладывает пакеты по потокам.
- `tcp_slow_start_after_idle = 0` — после паузы TCP не начинает заново слишком осторожный «разгон», поэтому прокси быстрее оживает после простоя.

Проверка:

```bash
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc net.ipv4.tcp_slow_start_after_idle
```

Ожидаемо:

```text
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
net.ipv4.tcp_slow_start_after_idle = 0
```

### Firewall для 5223: оставить строгий per-port rate-limit

Парадоксальный, но важный результат теста: **полное снятие rate-limit с `5223` ухудшило первое подключение**. В логах пошёл шквал:

```text
Telegram handshake timeout
```

Поэтому рабочий вариант — оставить именно per-port правило `1 SYN/сек`:

```text
-A ufw-before-input -p tcp --dport 5223 --syn -m recent --name mtp5223 --rcheck --seconds 1 -j DROP
-A ufw-before-input -p tcp --dport 5223 --syn -m recent --name mtp5223 --set -j ACCEPT
```

Смысл такой: Telegram-клиент при плохом старте может быстро плодить новые подключения. Без ограничения это превращается в волну незавершённых рукопожатий. Строгий per-port лимит не ускоряет сам TLS/MTProto, но помогает не устраивать локальный шторм попыток с одного IP.

### Проверка, что профиль здоровый

```bash
systemctl is-active telemt2
ss -tlnp | grep ':5223'
journalctl -u telemt2 --since "10 min ago" --no-pager
ss -tan sport = :5223 | grep ESTAB
```

Хорошая картина:

- `telemt2` — `active`;
- `Listening on 0.0.0.0:5223`;
- в старте есть строки `Telegram DC Connectivity`;
- ближайшие DC около `30-40 ms`;
- есть `ESTAB`-соединения от реальных клиентов;
- отдельные `Telegram handshake timeout` допустимы, если сервис живой и есть устойчивые `ESTAB`-сессии.

Плохая картина:

- сервис постоянно перезапускается;
- нет `Listening on 0.0.0.0:5223`;
- порт закрыт с прод-бота;
- все попытки от одного реального клиента превращаются только в `Telegram handshake timeout`, без появления `ESTAB`.

Итоговый принцип для продакшена: **443/8530 можно держать более жёсткими как запасные анти-DPI профили, а 5223 держать как основной быстрый профиль для реальных пользователей**.

---

## Чем этот runbook отличается от [[Zapret/mtproto/03-telemt|03-telemt]]

| | 03-telemt | этот runbook |
|---|---|---|
| Развёртывание | Docker, один инстанс | бинарник + systemd, **3 инстанса** |
| Анти-DPI | базовый `tls_emulation` | + `client_mss="tspu"` + **UFW rate-limit per-port** |
| Запас на блокировку порта | нет | разные порты/домены на инстанс |
| iOS-залипание | — | sysctl keepalive |
| Фокус | API и управление юзерами | **закалка от ТСПУ под нагрузкой** |

---

> [!note] Что из этого — дословно из гайда, а что авторская сборка
> Из гайда assyoucandy подтверждены `client_mss="tspu"`→MSS=92, `tls_emulation`, per-port rate-limit на `xt_recent`, sysctl-keepalive и грабли с SSH/`xt_recent`. Конкретный systemd-юнит, схема 3 инстансов и часть пояснений (семантика флагов, назначение капабилити) — адаптация/реконструкция: на лендинге гайда они дословно не приведены, детали — «в полном гайде».

## 📚 См. также

- [[Zapret/mtproto/03-telemt|03-telemt]] — базовая установка telemt, REST API, per-user лимиты
- [[Zapret/mtproto/10-telemt-logs-dpi|Чтение логов и лимит SYN-ACK]] — как по логам поймать активный детект ТСПУ, per-port pacing
- [[mtproxy/ja4-sni-client-side|Кто может менять JA4/SNI]] — почему `client_mss`/rate-limit не меняют почерк, а чистый обход только клиентский
- [[mtproxy/mtproto-zig-setup|Настройка mtproto.zig (runbook)]] — тот же приём фрагментации (TCPMSS=88) и SYN-приёмы на Zig
- [[Zapret/mtproto/02-implementations|Реализации MTProxy]] — telemt в ряду других
- [[Zapret/mtproto/05-censorship|ТСПУ: каскад детекции MTProto]]
- 🔗 [Источник: telemt-server-guide (assyoucandy)](https://assyoucandy.github.io/telemt-server-guide/) — оригинальный гайд
- 🔗 [Фикс keepalive (iOS)](https://assyoucandy.github.io/telemt-server-guide/telemt-keepalive-guide.html)

---
date:
tags:
link:
aliases:
  - пресет
  - конфиги
img:
---
# Что такое пресеты в [[Zapret2]] GUI?
**Пресет** (*часто называемые конфигами*) — это txt файл с настройками программы, вместо использования GUI (*формат такой же как у `winws2.exe`, чтобы программы могли быстро считать и изменить настройки программы*). Они доступны в программе начиная с `Zapret2 v20.3`.

Пресеты загружаются в ядро программы `winws2.exe` через флаг `@<config_file>` — чтение опций командной строки из файла. все остальные опции из командной строки игнорируются.

Активный пресет заменяется в файл по пути `%AppData%\ZapretTwoDev\preset-zapret2.txt`. Он используется всегда и этот файл просто хранит активный пресет. Сам по себе пресетом не является. Все пресеты пользователя находятся в папке `presets`. По умолчанию используется пресет `Default`. Также существует стоковый пресет `Gaming`.

> [!NOTE]
> Вы можете обмениваться напрямую этими пресетами, чтобы быстро изменить настройки программы. Для этого есть специальная [группа](https://t.me/zaprethelp/66952).


> [!WARNING] Почему пресеты плохи?
> По умолчанию в пресетах жёстко захардкоржены стратегии для каждой фильтра, и как следовательно для хостлиста (*сайта*). Это приводит к тому что один сайт на пресете загружается, а второй перестаёт работать. А на пресете номер 2 работает второй сайт, но не работает первый. Это проблема решается путём изучение и подбора стратегия для каждой категории и хостлиста отдельно.
> И называется она — прямой запуск.

## Структура пресета
Пресет делится на три логических части:

### 1. Заголовок и метаданные
```bash
# Preset: 1
# ActivePreset: 1
# Modified: 2026-01-22T16:09:12.572985
```

Служебная информация для GUI — номер пресета, активен ли он, когда изменён.

### 2. Глобальные настройки
```bash
--lua-init=@lua/zapret-lib.lua      # Библиотека хелперов
--lua-init=@lua/zapret-antidpi.lua  # Библиотека стратегий DPI-обхода
--lua-init=@lua/zapret-auto.lua     # Автоматизация и оркестрация
--lua-init=@lua/custom_funcs.lua    # Пользовательские функции
--lua-init=@lua/custom_diag.lua     # Диагностика
```

Это загрузка Lua-библиотек с готовыми функциями. Без них ничего работать не будет. Это нужно чтобы Вы не писали свои техники дурения, а использовали готовый набор. В частности это [[fake]], [[multisplit]], [[multidisorder]] и другие.

Дополнительные служебные флаги чтобы кэшировать hostlist'ы, а также правильнее отслеживать количества пакетов:

```bash
--ctrack-disable=0        # Включён connection tracking (отслеживание соединений)
--ipcache-lifetime=8400   # Кэш IP живёт 8400 секунд (~2.3 часа)
--ipcache-hostname=1      # Кэшировать hostname → IP
```

Далее следуют [[Zapret2 - wf|глобальные фильтры WinDivert]], на языке [[Zapret2]] они имеют направление (`-in`, `-out`). По умолчанию (как правило) хватает только `-out`.

```bash
--wf-tcp-out=80,443,1080,2053,2083,2087,2096,8443  # Перехват TCP на этих портах
--wf-udp-out=80,443                                  # Перехват UDP
--wf-raw-part=@windivert.filter/...                  # Дополнительные фильтры windivert
```

Порты:
- `80` — HTTP
- `443` — HTTPS/QUIC
- `1080` — SOCKS (*часто использует Discord*)
- `2053, 2083, 2087, 2096, 8443` — альтернативные порты Discord для загрузки медиа-контента

### 3. [[Zapret2 - blob|Блобы]] (заготовки данных)
```bash
--blob=tls_google:@bin/tls_clienthello_www_google_com.bin
--blob=tls7:@bin/tls_clienthello_7.bin
--blob=fake_tls:@bin/fake_tls_1.bin
--blob=fake_default_udp:0x00000000000000000000000000000000
```

[[Zapret2 - blob|Блоб]] — это заранее подготовленные данные (*для удобства в готовом пресете сразу перечисляются все блоб файлы. Это необязательно!*):
- `tls_google` — настоящий TLS ClientHello от google.com (для TTL-спуфинга)
- `tls1..tls18` — различные варианты ClientHello
- `fake_tls_*` — поддельные пакеты для отправки в качестве фейков
- `quic_*` — QUIC-пакеты
- `0x00...` — просто нулевые байты (hex-формат)

### 4. [[Zapret2 - filter|Профили]] (стратегии обхода)
После глобальных настроек идут профили, разделённые --new. Каждый профиль — отдельная стратегия для определённого трафика ([[Создание своей категории|категории]]).

Профили могут быть любыми, однако для удобства по умолчанию в программе выставлен следующий порядок: `YouTube -> Discord -> Голосовой трафик -> Остальные https сайты -> Игры (протокол UDP)`.

#### Профиль 1: YouTube (TCP)
```bash
--filter-tcp=80,443
--hostlist=lists/youtube.txt
--out-range=-d8
--lua-desync=multisplit:pos=2,midsld-2:seqovl=1:seqovl_pattern=tls7
```

| Параметр | Значение |
|----------|----------|
| `--filter-tcp=80,443` | Применять только к TCP портам 80 и 443 |
| `--hostlist=lists/youtube.txt` | Только для доменов из файла youtube.txt |
| `--out-range=-d8` | Работать только на первых 8 пакетах с данными |
| `--lua-desync=multisplit:...` | Техника разрезания пакета |

**[[multisplit]]** разрезает пакет на части:
- `pos=2,midsld-2` — позиции разреза: 2-й байт и середина домена второго уровня минус 2
- `seqovl=1` — sequence overlap на 1 байт (смещение TCP sequence)
- `seqovl_pattern=tls7` — паттерн для overlap берётся из блоба tls7

#### Профиль 2: YouTube QUIC (UDP)
```bash
--filter-udp=443
--ipset=lists/ipset-youtube.txt
--out-range=-n8
--payload=all
--lua-desync=fake:repeats=6:blob=fake_default_quic
```

Для QUIC нельзя фильтровать по домену (он зашифрован), поэтому используется **ipset** — список IP-адресов.

**fake** — отправка фейковых пакетов:
- `repeats=6` — отправить 6 фейков
- `blob=fake_default_quic` — использовать стандартный QUIC-фейк

#### Профиль 3: Googlevideo

> [!WARNING] ВАЖНО!
> Для CDN-серверов (`*.googlevideo.com`) используется отдельная стратегия. Подробнее об этом писали [здесь](https://t.me/bypassblock/1269). Это нужно чтобы применить разные техники дурения к разным серверам, чтобы не дать ТСПУ быстро распознать сигнатуры Zapret'a и уменьшить шанс на блокировку активной стратегии.

```bash
--filter-tcp=80,443
--hostlist-domains=googlevideo.com
--out-range=-d8
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1
```

**[[multidisorder]]** — как [[multisplit]], но отправляет сегменты в **обратном порядке**. DPI часто ожидает пакеты по порядку и путается.

Позиции разреза используют **маркеры**:
- `host+2` — начало hostname + 2 байта
- `sld+2` — начало домена второго уровня + 2
- `sniext+1` — SNI extension + 1
- `endhost-2` — конец hostname - 2

#### Профиль 4: Discord (обычный)
```bash
--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--hostlist=lists/discord.txt
--out-range=-n10
--lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=1000
--lua-desync=multidisorder_legacy:seqovl=652:seqovl_pattern=tls5
```

Комбинация двух техник `lua-desync` (*или же фаз, их можно выбирать несколько*):
1. **fake** с `blob=tls_google` — отправить фейк, выглядящий как запрос к google.com
2. **multidisorder_legacy** — старая версия disorder с большим seqovl=652

#### Профиль 5: Discord Media (сложный)
Это профиль для серверов с голосовыми каналами. Из-за специфичности их блокировки они также блокируются отдельно.

```bash
--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--hostlist-domains=discord.media
--out-range=-d8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=multisplit:pos=1:repeats=10:tcp_ack=-66000:tcp_ts_up:ip_ttl=4:ip6_ttl=4
```

Три техники подряд:
1. **send:repeats=2** — отправить оригинал 2 раза
2. **[[syndata]]** — вложить данные в SYN-пакет с автоподбором TTL
3. **multisplit** с низким TTL=4 (пакет дойдёт до ТСПУ, но не до сервера)

#### Профиль 6: STUN/Discord голос (UDP)
```bash
--filter-l7=stun,discord
--payload=stun,discord_ip_discovery
--out-range=-n8
--lua-desync=fake:blob=fake_default_udp
```

Для голосовых звонков Discord. Фильтрация по **протоколу L7** (уровень приложения):
- `stun` — протокол для NAT traversal
- `discord_ip_discovery` — специфичный протокол Discord

#### Профиль 7-11: Остальные сервисы
Аналогичные техники для:
- Конкретного IP `130.255.77.28`
- Списков `other.txt`, `russia-blacklist.txt`  
- Порно-сайтов (`ipset-porn.txt`)
- Танки X (`ipset-tankix.txt`)

Основные техники (краткая справка)

| Техника               | Описание                                       |
| --------------------- | ---------------------------------------------- |
| **[[fake]]**          | Отправить поддельный пакет перед настоящим     |
| **[[multisplit]]**    | Разрезать пакет на части по указанным позициям |
| **[[multidisorder]]** | Разрезать и отправить в обратном порядке       |
| **[[syndata]]**       | Вложить данные в SYN-пакет                     |
| **send**              | Просто отправить пакет (с модификациями)       |
| **fakedsplit**        | Разрезать с замешиванием фейков между частями  |

## Итоговый пример
Итоговые ПОЛНЫЕ примеры `txt` файлов представлен ниже.

### Пример 1
```bash
# Preset: 1
# ActivePreset: 1
# Modified: 2026-01-22T16:09:12.572985

--lua-init=@lua/zapret-lib.lua
--lua-init=@lua/zapret-antidpi.lua
--lua-init=@lua/zapret-auto.lua
--lua-init=@lua/custom_funcs.lua
--lua-init=@lua/custom_diag.lua
--ctrack-disable=0
--ipcache-lifetime=8400
--ipcache-hostname=1
--wf-tcp-out=80,443,1080,2053,2083,2087,2096,8443
--wf-udp-out=80,443
--wf-raw-part=@windivert.filter/windivert_part.discord_media.txt
--wf-raw-part=@windivert.filter/windivert_part.stun.txt
--wf-raw-part=@windivert.filter/windivert_part.wireguard.txt
--blob=tls_google:@bin/tls_clienthello_www_google_com.bin
--blob=tls1:@bin/tls_clienthello_1.bin
--blob=tls2:@bin/tls_clienthello_2.bin
--blob=tls2n:@bin/tls_clienthello_2n.bin
--blob=tls3:@bin/tls_clienthello_3.bin
--blob=tls4:@bin/tls_clienthello_4.bin
--blob=tls5:@bin/tls_clienthello_5.bin
--blob=tls6:@bin/tls_clienthello_6.bin
--blob=tls7:@bin/tls_clienthello_7.bin
--blob=tls8:@bin/tls_clienthello_8.bin
--blob=tls9:@bin/tls_clienthello_9.bin
--blob=tls10:@bin/tls_clienthello_10.bin
--blob=tls11:@bin/tls_clienthello_11.bin
--blob=tls12:@bin/tls_clienthello_12.bin
--blob=tls13:@bin/tls_clienthello_13.bin
--blob=tls14:@bin/tls_clienthello_14.bin
--blob=tls17:@bin/tls_clienthello_17.bin
--blob=tls18:@bin/tls_clienthello_18.bin
--blob=tls_sber:@bin/tls_clienthello_sberbank_ru.bin
--blob=tls_vk:@bin/tls_clienthello_vk_com.bin
--blob=tls_vk_kyber:@bin/tls_clienthello_vk_com_kyber.bin
--blob=tls_deepseek:@bin/tls_clienthello_chat_deepseek_com.bin
--blob=tls_max:@bin/tls_clienthello_max_ru.bin
--blob=tls_iana:@bin/tls_clienthello_iana_org.bin
--blob=tls_4pda:@bin/tls_clienthello_4pda_to.bin
--blob=tls_gosuslugi:@bin/tls_clienthello_gosuslugi_ru.bin
--blob=syndata3:@bin/tls_clienthello_3.bin
--blob=syn_packet:@bin/syn_packet.bin
--blob=dtls_w3:@bin/dtls_clienthello_w3_org.bin
--blob=quic_google:@bin/quic_initial_www_google_com.bin
--blob=quic_vk:@bin/quic_initial_vk_com.bin
--blob=quic1:@bin/quic_1.bin
--blob=quic2:@bin/quic_2.bin
--blob=quic3:@bin/quic_3.bin
--blob=quic4:@bin/quic_4.bin
--blob=quic5:@bin/quic_5.bin
--blob=quic6:@bin/quic_6.bin
--blob=quic7:@bin/quic_7.bin
--blob=quic_test:@bin/quic_test_00.bin
--blob=fake_tls:@bin/fake_tls_1.bin
--blob=fake_tls_1:@bin/fake_tls_1.bin
--blob=fake_tls_2:@bin/fake_tls_2.bin
--blob=fake_tls_3:@bin/fake_tls_3.bin
--blob=fake_tls_4:@bin/fake_tls_4.bin
--blob=fake_tls_5:@bin/fake_tls_5.bin
--blob=fake_tls_6:@bin/fake_tls_6.bin
--blob=fake_tls_7:@bin/fake_tls_7.bin
--blob=fake_tls_8:@bin/fake_tls_8.bin
--blob=fake_quic:@bin/fake_quic.bin
--blob=fake_quic_1:@bin/fake_quic_1.bin
--blob=fake_quic_2:@bin/fake_quic_2.bin
--blob=fake_quic_3:@bin/fake_quic_3.bin
--blob=fake_default_udp:0x00000000000000000000000000000000
--blob=http_req:@bin/http_iana_org.bin
--blob=hex_0e0e0f0e:0x0E0E0F0E
--blob=hex_0f0e0e0f:0x0F0E0E0F
--blob=hex_0f0f0f0f:0x0F0F0F0F
--blob=hex_00:0x00

--filter-tcp=80,443
--hostlist=lists/youtube.txt
--out-range=-d8
--lua-desync=multisplit:pos=2,midsld-2:seqovl=1:seqovl_pattern=tls7

--new

--filter-udp=443
--ipset=lists/ipset-youtube.txt
--out-range=-n8
--payload=all
--lua-desync=fake:repeats=6:blob=fake_default_quic

--new

--filter-tcp=80,443
--hostlist-domains=googlevideo.com
--out-range=-d8
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=443
--hostlist-domains=updates.discord.com
--out-range=-d10
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--hostlist=lists/discord.txt
--out-range=-n10
--lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=1000
--lua-desync=multidisorder_legacy:seqovl=652:seqovl_pattern=tls5

--new

--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--hostlist-domains=discord.media
--out-range=-d8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=multisplit:pos=1:repeats=10:tcp_ack=-66000:tcp_ts_up:ip_ttl=4:ip6_ttl=4

--new

--filter-l7=stun,discord
--payload=stun,discord_ip_discovery
--out-range=-n8
--lua-desync=fake:blob=fake_default_udp

--new

--filter-tcp=80,443
--ipset-ip=130.255.77.28
--out-range=-d9
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=443
--hostlist-exclude=lists/netrogat.txt
--hostlist=lists/other.txt
--hostlist=lists/other2.txt
--hostlist=lists/russia-blacklist.txt
--out-range=-n10
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google
--lua-desync=fake:blob=tls_google:repeats=6:tcp_ts=1000
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=80,443
--ipset=lists/ipset-porn.txt
--out-range=-n8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google
--lua-desync=fake:blob=fake_default_http:repeats=4:ip_autottl=2,3-20:ip6_autottl=2,3-20:tcp_md5
--lua-desync=multidisorder:pos=host+1

--new

--filter-tcp=80,443
--ipset=lists/ipset-tankix.txt
--out-range=-n8
--lua-desync=fake:blob=fake_default_http:repeats=4:ip_autottl=2,3-20:ip6_autottl=2,3-20:tcp_md5
--lua-desync=multidisorder:pos=host+1
```

### Пример 2
```bash
# Preset: 1
# Created: 2026-01-21T19:15:55.706763
# Modified: 2026-01-21T19:15:55.707605
# Description: 

--lua-init=@lua/zapret-lib.lua
--lua-init=@lua/zapret-antidpi.lua
--lua-init=@lua/zapret-auto.lua
--lua-init=@lua/custom_funcs.lua
--lua-init=@lua/custom_diag.lua
--ctrack-disable=0
--ipcache-lifetime=8400
--ipcache-hostname=1
--wf-tcp-out=80,443,1080,2053,2083,2087,2096,8443
--wf-udp-out=80,443
--wf-raw-part=@windivert.filter/windivert_part.discord_media.txt
--wf-raw-part=@windivert.filter/windivert_part.stun.txt
--wf-raw-part=@windivert.filter/windivert_part.wireguard.txt
--blob=tls_google:@bin/tls_clienthello_www_google_com.bin
--blob=tls1:@bin/tls_clienthello_1.bin
--blob=tls2:@bin/tls_clienthello_2.bin
--blob=tls2n:@bin/tls_clienthello_2n.bin
--blob=tls3:@bin/tls_clienthello_3.bin
--blob=tls4:@bin/tls_clienthello_4.bin
--blob=tls5:@bin/tls_clienthello_5.bin
--blob=tls6:@bin/tls_clienthello_6.bin
--blob=tls7:@bin/tls_clienthello_7.bin
--blob=tls8:@bin/tls_clienthello_8.bin
--blob=tls9:@bin/tls_clienthello_9.bin
--blob=tls10:@bin/tls_clienthello_10.bin
--blob=tls11:@bin/tls_clienthello_11.bin
--blob=tls12:@bin/tls_clienthello_12.bin
--blob=tls13:@bin/tls_clienthello_13.bin
--blob=tls14:@bin/tls_clienthello_14.bin
--blob=tls17:@bin/tls_clienthello_17.bin
--blob=tls18:@bin/tls_clienthello_18.bin
--blob=tls_sber:@bin/tls_clienthello_sberbank_ru.bin
--blob=tls_vk:@bin/tls_clienthello_vk_com.bin
--blob=tls_vk_kyber:@bin/tls_clienthello_vk_com_kyber.bin
--blob=tls_deepseek:@bin/tls_clienthello_chat_deepseek_com.bin
--blob=tls_max:@bin/tls_clienthello_max_ru.bin
--blob=tls_iana:@bin/tls_clienthello_iana_org.bin
--blob=tls_4pda:@bin/tls_clienthello_4pda_to.bin
--blob=tls_gosuslugi:@bin/tls_clienthello_gosuslugi_ru.bin
--blob=syndata3:@bin/tls_clienthello_3.bin
--blob=syn_packet:@bin/syn_packet.bin
--blob=dtls_w3:@bin/dtls_clienthello_w3_org.bin
--blob=quic_google:@bin/quic_initial_www_google_com.bin
--blob=quic_vk:@bin/quic_initial_vk_com.bin
--blob=quic1:@bin/quic_1.bin
--blob=quic2:@bin/quic_2.bin
--blob=quic3:@bin/quic_3.bin
--blob=quic4:@bin/quic_4.bin
--blob=quic5:@bin/quic_5.bin
--blob=quic6:@bin/quic_6.bin
--blob=quic7:@bin/quic_7.bin
--blob=quic_test:@bin/quic_test_00.bin
--blob=fake_tls:@bin/fake_tls_1.bin
--blob=fake_tls_1:@bin/fake_tls_1.bin
--blob=fake_tls_2:@bin/fake_tls_2.bin
--blob=fake_tls_3:@bin/fake_tls_3.bin
--blob=fake_tls_4:@bin/fake_tls_4.bin
--blob=fake_tls_5:@bin/fake_tls_5.bin
--blob=fake_tls_6:@bin/fake_tls_6.bin
--blob=fake_tls_7:@bin/fake_tls_7.bin
--blob=fake_tls_8:@bin/fake_tls_8.bin
--blob=fake_quic:@bin/fake_quic.bin
--blob=fake_quic_1:@bin/fake_quic_1.bin
--blob=fake_quic_2:@bin/fake_quic_2.bin
--blob=fake_quic_3:@bin/fake_quic_3.bin
--blob=fake_default_udp:0x00000000000000000000000000000000
--blob=http_req:@bin/http_iana_org.bin
--blob=hex_0e0e0f0e:0x0E0E0F0E
--blob=hex_0f0e0e0f:0x0F0E0E0F
--blob=hex_0f0f0f0f:0x0F0F0F0F
--blob=hex_00:0x00

--filter-tcp=80,443
--hostlist=lists/youtube.txt
--out-range=-d8
--lua-desync=multisplit:pos=2,midsld-2:seqovl=1:seqovl_pattern=tls7

--new

--filter-udp=443
--ipset=lists/ipset-youtube.txt
--out-range=-n8
--payload=all
--lua-desync=fake:repeats=6:blob=fake_default_quic

--new

--filter-tcp=80,443
--hostlist-domains=googlevideo.com
--out-range=-d8
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=443
--hostlist-domains=updates.discord.com
--out-range=-d10
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--hostlist=lists/discord.txt
--out-range=-n10
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google
--lua-desync=fake:blob=tls7:tcp_ack=-66000:tcp_ts_up:tls_mod=rnd
--lua-desync=multisplit:seqovl=700:seqovl_pattern=tls_google:tcp_flags_unset=ack

--new

--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--hostlist-domains=discord.media
--out-range=-d8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=multisplit:pos=1:repeats=10:tcp_ack=-66000:tcp_ts_up:ip_ttl=4:ip6_ttl=4

--new

--filter-l7=stun,discord
--payload=stun,discord_ip_discovery
--out-range=-n8
--lua-desync=fake:blob=fake_default_udp

--new

--filter-tcp=80,443
--ipset-ip=130.255.77.28
--out-range=-d9
--lua-desync=multidisorder:pos=1,host+2,sld+2,sld+5,sniext+1,sniext+2,endhost-2:seqovl=1

--new

--filter-tcp=443
--hostlist-exclude=lists/netrogat.txt
--hostlist=lists/other.txt
--hostlist=lists/other2.txt
--hostlist=lists/russia-blacklist.txt
--out-range=-n10
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google
--lua-desync=hostfakesplit:host=ozon.ru:tcp_ts=-1000:tcp_md5:repeats=4

--new

--filter-tcp=80,443
--ipset=lists/ipset-tankix.txt
--out-range=-n8
--lua-desync=fake:blob=fake_default_http:repeats=4:ip_autottl=2,3-20:ip6_autottl=2,3-20:tcp_md5
--lua-desync=multidisorder:pos=host+1
```

### Пример 3 (игровой для игр)
```bash
# Preset: Gaming
# ActivePreset: Gaming

--lua-init=@lua/zapret-lib.lua
--lua-init=@lua/zapret-antidpi.lua
--lua-init=@lua/zapret-auto.lua
--lua-init=@lua/custom_funcs.lua
--ipcache-lifetime=8400
--ipcache-hostname=1 
--wf-tcp-out=80,444-65535
--wf-udp-out=80,444-65535
--wf-raw-part=@windivert.filter/windivert_part.discord_media.txt
--wf-raw-part=@windivert.filter/windivert_part.stun.txt
--wf-raw-part=@windivert.filter/windivert_part.wireguard.txt
--blob=tls_google:@bin/tls_clienthello_www_google_com.bin
--blob=tls1:@bin/tls_clienthello_1.bin
--blob=tls2:@bin/tls_clienthello_2.bin
--blob=tls2n:@bin/tls_clienthello_2n.bin
--blob=tls3:@bin/tls_clienthello_3.bin
--blob=tls4:@bin/tls_clienthello_4.bin
--blob=tls5:@bin/tls_clienthello_5.bin
--blob=tls6:@bin/tls_clienthello_6.bin
--blob=tls7:@bin/tls_clienthello_7.bin
--blob=tls8:@bin/tls_clienthello_8.bin
--blob=tls9:@bin/tls_clienthello_9.bin
--blob=tls10:@bin/tls_clienthello_10.bin
--blob=tls11:@bin/tls_clienthello_11.bin
--blob=tls12:@bin/tls_clienthello_12.bin
--blob=tls13:@bin/tls_clienthello_13.bin
--blob=tls14:@bin/tls_clienthello_14.bin
--blob=tls17:@bin/tls_clienthello_17.bin
--blob=tls18:@bin/tls_clienthello_18.bin
--blob=tls_sber:@bin/tls_clienthello_sberbank_ru.bin
--blob=tls_vk:@bin/tls_clienthello_vk_com.bin
--blob=tls_vk_kyber:@bin/tls_clienthello_vk_com_kyber.bin
--blob=tls_deepseek:@bin/tls_clienthello_chat_deepseek_com.bin
--blob=tls_max:@bin/tls_clienthello_max_ru.bin
--blob=tls_iana:@bin/tls_clienthello_iana_org.bin
--blob=tls_4pda:@bin/tls_clienthello_4pda_to.bin
--blob=tls_gosuslugi:@bin/tls_clienthello_gosuslugi_ru.bin
--blob=syndata3:@bin/tls_clienthello_3.bin
--blob=syn_packet:@bin/syn_packet.bin
--blob=dtls_w3:@bin/dtls_clienthello_w3_org.bin
--blob=quic_google:@bin/quic_initial_www_google_com.bin
--blob=quic_vk:@bin/quic_initial_vk_com.bin
--blob=quic1:@bin/quic_1.bin
--blob=quic2:@bin/quic_2.bin
--blob=quic3:@bin/quic_3.bin
--blob=quic4:@bin/quic_4.bin
--blob=quic5:@bin/quic_5.bin
--blob=quic6:@bin/quic_6.bin
--blob=quic7:@bin/quic_7.bin
--blob=quic_test:@bin/quic_test_00.bin
--blob=fake_tls:@bin/fake_tls_1.bin
--blob=fake_tls_1:@bin/fake_tls_1.bin
--blob=fake_tls_2:@bin/fake_tls_2.bin
--blob=fake_tls_3:@bin/fake_tls_3.bin
--blob=fake_tls_4:@bin/fake_tls_4.bin
--blob=fake_tls_5:@bin/fake_tls_5.bin
--blob=fake_tls_6:@bin/fake_tls_6.bin
--blob=fake_tls_7:@bin/fake_tls_7.bin
--blob=fake_tls_8:@bin/fake_tls_8.bin
--blob=fake_quic:@bin/fake_quic.bin
--blob=fake_quic_1:@bin/fake_quic_1.bin
--blob=fake_quic_2:@bin/fake_quic_2.bin
--blob=fake_quic_3:@bin/fake_quic_3.bin
--blob=fake_default_udp:0x00000000000000000000000000000000
--blob=http_req:@bin/http_iana_org.bin
--blob=hex_0e0e0f0e:0x0E0E0F0E
--blob=hex_0f0e0e0f:0x0F0E0E0F
--blob=hex_0f0f0f0f:0x0F0F0F0F
--blob=hex_00:0x00

--filter-tcp=80,443
--ipset=lists/ipset-youtube.txt
--out-range=-n8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=multidisorder_legacy:pos=1,midsld

--new

--filter-udp=443
--ipset=lists/ipset-youtube.txt
--out-range=-n8
--payload=all
--lua-desync=fake:repeats=6:blob=fake_default_quic

--new

--filter-tcp=80,443,1080,2053,2083,2087,2096,8443
--ipset=lists/ipset-discord.txt
--out-range=-n8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=multidisorder_legacy:pos=1,midsld

--new

--filter-l7=stun,discord
--payload=stun,discord_ip_discovery
--out-range=-n8
--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10

--new

--filter-tcp=80,443
--ipset=lists/ipset-telegram.txt
--out-range=-n8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=pass

--new

--filter-tcp=80,443
--ipset-ip=130.255.77.28
--out-range=-n20
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=fake:blob=tls14:tcp_ack=-66000:tcp_ts_up:ip_autottl=-1,3-20:ip6_autottl=-1,3-20:tls_mod=rnd,dupsid,sni=fonts.google.com
--lua-desync=multidisorder:pos=7,sld+1:tcp_ack=-66000:tcp_ts_up:ip_autottl=-1,3-20:ip6_autottl=-1,3-20

--new

--filter-tcp=80,443
--hostlist=lists/roblox.txt
--out-range=-n8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=fake:blob=tls_google:tcp_ts=1:repeats=8:payload=tls_client_hello
--lua-desync=multisplit:pos=1:seqovl=681:seqovl_pattern=tls_google:payload=tls_client_hello

--new

--filter-udp=443,49152-65535
--ipset=lists/ipset-roblox.txt
--out-range=-n8
--payload=all
--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10

--new

--filter-tcp=80,443-65535
--ipset=lists/russia-youtube-rtmps.txt
--ipset=lists/ipset-all.txt
--ipset=lists/ipset-base.txt
--ipset=lists/ipset-discord.txt
--ipset-exclude=lists/ipset-dns.txt
--out-range=-n8
--lua-desync=send:repeats=2
--lua-desync=syndata:blob=tls_google:ip_autottl=-2,3-20
--lua-desync=multisplit:seqovl=700:seqovl_pattern=tls_google:tcp_flags_unset=ack

--new

--filter-udp=*
--ipset=lists/ipset-all.txt
--ipset=lists/ipset-base.txt
--ipset=lists/cloudflare-ipset.txt
--ipset=lists/ipset-cloudflare1.txt
--ipset=lists/ipset-cloudflare.txt
--ipset-exclude=lists/ipset-dns.txt
--out-range=-n8
--payload=all
--lua-desync=fake:blob=quic_google:ip_autottl=-2,3-20:ip6_autottl=-2,3-20:payload=all:repeats=10
```
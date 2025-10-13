---
tags:
  - zapret
aliases:
---

```base
views:
  - type: table
    name: Table
    filters:
      and:
        - file.inFolder("Zapret/ToDo")
    order:
      - file.name
      - tags
    columnSize:
      file.name: 488

```

## [[Privacy]]

[[Базовые аргументы (режимы фильтрации WinDivert)]]
[[ZapretTeam]]
[[Ошибка запуска - Не удалось запустить DPI]]
[[Как скачать Zapret GUI]]
[[Zapret VPN - что это такое и все тарифы]]
[[Как пользоваться Zapret VPN (VLESS)]]
[[Как пользоваться Zapret]]
[[Манифест Zapret]]

[[Zapret VPN (Telegram bot)]]

### [[Дорожная карта]]

## YTDisBystro
[[YTDisBystro_v3.5]]

## [[Dronatar]]
## [[Youtube + Discord]]

[[ipset-ovh.txt]]

[[LordSlon]]
[[telegram calls]]

```embed
title: "Add batch files to manage ipsets by ekungurov · Pull Request #3448 · Flowseal/zapret-discord-youtube"
image: "https://opengraph.githubassets.com/a25494058d39257330874556588cc1289f50ae8e6f2769452d6cef75f8109cd7/Flowseal/zapret-discord-youtube/pull/3448"
description: "Разбил исходный ipset-all.txt на части. Добавил шелл скрипт для объединения частей в один большой файл. Разбиение сделано в качестве примера, файл ipset-other.txt всё ещё большой. Особенно после св..."
url: "https://github.com/Flowseal/zapret-discord-youtube/pull/3448"
favicon: "https://github.githubassets.com/favicons/favicon-dark.svg"
aspectRatio: "50"
parser: "local"
date: "2025-10-05"
custom_date: "2025-10-05 19:54:42"
```





```base
views:
  - type: table
    name: Table
    filters:
      and:
        - file.inFolder("Notes/Privacy/Zapret")
    order:
      - file.name
      - file.tags
    columnSize:
      file.name: 634

```



```bash
–wf-tcp=80,443 --wf-udp=443,50000-50099 ^  
–filter-tcp=80 --dpi-desync=fake -dpi-desync-ttl=2 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=0x80000000 --new ^  
–filter-tcp=443 --hostlist=“list-youtube.txt” --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls=“tls_clienthello_www_google_com.bin” --new ^  
–filter-udp=443 --hostlist=“list-youtube.txt” --dpi-desync=fake -dpi-desync-ttl=4 --dpi-desync-repeats=9 --dpi-desync-fake-quic=0x00000000 --new ^  
–filter-tcp=443 --hostlist-exclude=“list-youtube.txt” --dpi-desync=fake --dpi-desync-fooling=badseq --dpi-desync-repeats=6 --dpi-desync-badseq-increment=0x80000000 --dpi-desync-fake-tls=“tls_clienthello_www_google_com.bin” --new ^  
–filter-udp=443 --hostlist-exclude=“list-youtube.txt” --dpi-desync=fake,disorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=6 --dpi-desync-fake-quic=“quic_ietf_www_google_com.bin” --new ^  
–wf-udp=50000-50099 --filter-udp=50000-50099 --ipset=“ipset-discord.txt” --dpi-desync=fake,tamper --dpi-desync-any-protocol --dpi-desync-fake-quic=“quic_initial_www_google_com.bin”
```
P.S. Ростелеком, Москва, кстати.

```embed
title: "Бан от Google | Ошибки плеера | Не работает YouTube со всеми стратегиями Zapret - Community software / Zapret - NTC"
image: "https://ntc.party/uploads/default/original/1X/c3dcc2e0e229cb0e06f291b5459ba086b1452779.png"
description: "Жесть, мужееееки.  Как я говорил у меня preset_russia.  Внес некоторые изменения в него от себя, в частности TCP/UDP вернул из своего старого конфига, т.к. те что в пресете - немного тупорылят.  Те что в самом пресете, под Ютуб, - оставил, но подрезал, добавил ttl=4 (как будто бы так стабильнее, если больше то начинает срать ошибками, если меньше 3-ёх то мало, на 3 подвисает чаще, на 4 как будто бы больше стабильности).  На свои же стратегии по TCP/UDP добавил хостлист exclude - list-youtube, ..."
url: "https://ntc.party/t/%D0%B1%D0%B0%D0%BD-%D0%BE%D1%82-google-%D0%BE%D1%88%D0%B8%D0%B1%D0%BA%D0%B8-%D0%BF%D0%BB%D0%B5%D0%B5%D1%80%D0%B0-%D0%BD%D0%B5-%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D0%B0%D0%B5%D1%82-youtube-%D1%81%D0%BE-%D0%B2%D1%81%D0%B5%D0%BC%D0%B8-%D1%81%D1%82%D1%80%D0%B0%D1%82%D0%B5%D0%B3%D0%B8%D1%8F%D0%BC%D0%B8-zapret/14070/129"
```

```embed
title: "Бан от Google | Ошибки плеера | Не работает YouTube со всеми стратегиями Zapret - Community software / Zapret - NTC"
image: "https://ntc.party/uploads/default/original/1X/c3dcc2e0e229cb0e06f291b5459ba086b1452779.png"
description: "Надо заметить, что nfqws в рутере с тем же конфигом не дает этих лишних полсекунды-секунду, хорошо работают альтернативные приложения, в том числе андройдовые по вайфаю.    <details><summary>Если не самый, то один из простых случаев</summary>AtrM_preset.cmd (2,2 КБ)  youtube.txt (404 байта)  block1.txt (79 байтов)  block2.txt (119 байтов)  quic.bin (144 байта)  tls_goog.bin (240 байтов)  tlsmix1.bin (1,0 КБ)  Нужные домены вносятся в block1.txt или в block2.txt</details>"
url: "https://ntc.party/t/%D0%B1%D0%B0%D0%BD-%D0%BE%D1%82-google-%D0%BE%D1%88%D0%B8%D0%B1%D0%BA%D0%B8-%D0%BF%D0%BB%D0%B5%D0%B5%D1%80%D0%B0-%D0%BD%D0%B5-%D1%80%D0%B0%D0%B1%D0%BE%D1%82%D0%B0%D0%B5%D1%82-youtube-%D1%81%D0%BE-%D0%B2%D1%81%D0%B5%D0%BC%D0%B8-%D1%81%D1%82%D1%80%D0%B0%D1%82%D0%B5%D0%B3%D0%B8%D1%8F%D0%BC%D0%B8-zapret/14070/130"
```

```embed
title: "Сборка YTDisBystro на основе zapret для Windows: Обсуждение - NTC"
image: "https://ntc.party/uploads/default/original/1X/c3dcc2e0e229cb0e06f291b5459ba086b1452779.png"
description: "YTDisBystro v2.4.1   версия zapret для скачивания заменена на 69.7 в ipset для Дискорда добавлен IP сайта stable.dl2.discordapp.net с которого Дискорд тянет обновы 1_preset_russia и 2_service_install_reinstall переведены в кодировку UTF-8, чтобы комментарии на русском отображались на виндовс без русской локали в !!!get_zapret_first!!! добавлен прыжок сразу на распаковку, если в папке YTDisBystro присутствует zip-архив zapret (не винбандл!) версии, указанной в переменной zapret_ver (для параноико..."
url: "https://ntc.party/t/%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0-ytdisbystro-%D0%BD%D0%B0-%D0%BE%D1%81%D0%BD%D0%BE%D0%B2%D0%B5-zapret-%D0%B4%D0%BB%D1%8F-windows-%D0%BE%D0%B1%D1%81%D1%83%D0%B6%D0%B4%D0%B5%D0%BD%D0%B8%D0%B5/13251/410"
```

```embed
title: "Сборка YTDisBystro на основе zapret для Windows: Обсуждение - NTC"
image: "https://ntc.party/uploads/default/original/1X/c3dcc2e0e229cb0e06f291b5459ba086b1452779.png"
description: "YTDisBystro v2.4.2   удален russia-youtubeGV.txt из lists - нет смысла его держать ради одного домена, все стратегии с ним переделаны добавлена еще одна стратегия для дискорда отсюда (не по умолчанию) добавлена ультимативная стратегия ZMESS от i-no для гуглвидео (для специалистов, знающих как узнать свои пулы GGC и перевести их в IP-диапазон вида XXX.XXX.XXX.XXX/XX), не по умолчанию, конечно, ибо требуется в крайне редких случаях в myhostlist.txt добавлено несколько тихо заблоченных на днях доме..."
url: "https://ntc.party/t/%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0-ytdisbystro-%D0%BD%D0%B0-%D0%BE%D1%81%D0%BD%D0%BE%D0%B2%D0%B5-zapret-%D0%B4%D0%BB%D1%8F-windows-%D0%BE%D0%B1%D1%81%D1%83%D0%B6%D0%B4%D0%B5%D0%BD%D0%B8%D0%B5/13251/522"
```

```bash
--wf-tcp=80,443 --wf-udp=443,50000-50099 ^
--filter-tcp=80 --dpi-desync=fakeddisorder --dpi-desync-ttl=1 --dpi-desync-autottl=2 --dpi-desync-split-pos=method+2 --new ^
--filter-tcp=443 --hostlist="%~dp0unblock.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="%~dp0tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=midsld --dpi-desync-repeats=6 --dpi-desync-fooling=badseq,md5sig --new ^
--filter-udp=443 --hostlist="%~dp0unblock.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="%~dp0quic_initial_www_google_com.bin" --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 ^ --new ^
--filter-udp=50000-50099 --ipset="%~dp0ipset-discord.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-any-protocol --dpi-desync-cutoff=n4
```
https://ntc.party/t/726/4029


```embed
title: "Сборка YTDisBystro на основе zapret для Windows: Обсуждение - NTC"
image: "https://ntc.party/uploads/default/original/1X/c3dcc2e0e229cb0e06f291b5459ba086b1452779.png"
description: "YTDisBystro v2.5 наконец-то поднял свою ленивую *опу и написал инструкцию к сборке ) Она в архиве. Рекомендую ознакомиться версия запрета в cmd изменена на 69.9 (есть там полезные фиксы для режима disorder) убрал из netrogat.txt домен upload.youtube.com ибо его начали замедлять, теперь нужен обход переделал стратегию для Ютуба с QUIC добавил 2 запасных стратегии для Ютуба с QUIC (переменная YTDB_YTQC) YTDisBystro_v2.5.zip (841,2 КБ) MD5: 7F604CF10975DB8D3D22C1338224C01A SHA-256: 00B86065943…"
url: "https://ntc.party/t/%D1%81%D0%B1%D0%BE%D1%80%D0%BA%D0%B0-ytdisbystro-%D0%BD%D0%B0-%D0%BE%D1%81%D0%BD%D0%BE%D0%B2%D0%B5-zapret-%D0%B4%D0%BB%D1%8F-windows-%D0%BE%D0%B1%D1%81%D1%83%D0%B6%D0%B4%D0%B5%D0%BD%D0%B8%D0%B5/13251/584"
```

## ZapretDebug

### presetOrig.cmd
```bash
@echo off
:: Проверка наличия прав администратора
net session >nul 2>&1
if %errorLevel% == 0 (
    echo NOT RUN PRESET WITH PRAVA ADMIN!
    pause
    exit /b
) else (
    echo DONE ADMIN PRAVE!
)

tasklist /FI "IMAGENAME eq winws.exe" | find "winws.exe" > nul
if %errorlevel% == 0 (
    echo ERROR: ANOTHER winws.exe START! PLEASE CLOSE ANOTHER CONSONE!
    pause
    exit /b
) else (
    echo DONE START!
)

start "presetOrig" /min "winws.exe" ^
--wf-tcp=80,443 --wf-udp=443,50000-50099 ^
--filter-tcp=80 --dpi-desync=fake,fakedsplit --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-youtube.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=midsld --dpi-desync-repeats=6 --dpi-desync-fooling=badseq,md5sig --new ^
--filter-udp=443 --hostlist="list-youtube.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --new ^
--filter-udp=50000-50099 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-any-protocol --dpi-desync-cutoff=n4 --new ^
--filter-tcp=443 --hostlist="faceinsta.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="tls_clienthello_chat_deepseek_com.bin"
```
### preset1.cmd
```bash
@echo off
:: Проверка наличия прав администратора
net session >nul 2>&1
if %errorLevel% == 0 (
    echo NOT RUN PRESET WITH PRAVA ADMIN!
    pause
    exit /b
) else (
    echo DONE ADMIN PRAVE!
)

tasklist /FI "IMAGENAME eq winws.exe" | find "winws.exe" > nul
if %errorlevel% == 0 (
    echo ERROR: ANOTHER winws.exe START! PLEASE CLOSE ANOTHER CONSONE!
    pause
    exit /b
) else (
    echo DONE START!
)

start "zapret: http,https,quic" /min "%~dp0winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=443 --wf-udp=443,50000-65535 ^
--filter-udp=443 --hostlist="%~dp0list-youtube.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="%~dp0quic_initial_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="%~dp0list-youtube.txt" --dpi-desync=split --dpi-desync-split-seqovl=1 --dpi-desync-split-tls=sniext --dpi-desync-fake-tls="%~dp0tls_clienthello_www_google_com.bin" --dpi-desync-ttl=1 --new ^
--filter-tcp=443 --hostlist="%~dp0list-discord.txt" --dpi-desync=fake,split2 --dpi-desync-split-seqovl=1 --dpi-desync-split-tls=sniext --dpi-desync-fake-tls="%~dp0tls_clienthello_www_google_com.bin" --dpi-desync-ttl=4 --new ^
--filter-udp=443 --hostlist="%~dp0list-discord.txt" --dpi-desync=fake,split2 --dpi-desync-udplen-increment=10 --dpi-desync-repeats=6 --dpi-desync-udplen-pattern=0xDEADBEEF --dpi-desync-fake-quic="%~dp0quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-65535 --dpi-desync=fake,tamper --dpi-desync-any-protocol --dpi-desync-fake-quic="%~dp0quic_initial_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="%~dp0other.txt" --dpi-desync=fake,split2 --dpi-desync-split-seqovl=1 --dpi-desync-split-tls=sniext --dpi-desync-fake-tls="%~dp0tls_clienthello_www_google_com.bin" --dpi-desync-ttl=3 --new ^
--filter-tcp=443 --hostlist="%~dp0faceinsta.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="%~dp0tls_clienthello_www_google_com.bin"
```

https://t.me/oisi_rezerv
https://t.me/material_oisi/20
## Virus
```embed
title: "Zapret-Discord-YouTube/README.md at main · https://github.com/Detoools/Zapret-Discord-YouTube"
image: "https://opengraph.githubassets.com/c68998f316cbaccf390d5edf04409f58c0ebdce55d2e623797790e98f250486b/Detoools/Zapret-Discord-YouTube"
description: "Best Zapret. Contribute to Detoools/Zapret-Discord-YouTube development by creating an account on GitHub."
url: "https://github.com/Detoools/Zapret-Discord-YouTube"
```

[[Базовые аргументы (режимы фильтрации WinDivert)]]
[[ZapretTeam]]


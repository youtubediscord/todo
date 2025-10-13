---
tags:
  - zapret
  - zapret/inprogress
---

```embed
title: "🔴 Обход YouTube · Flowseal/zapret-discord-youtube · Discussion #251"
image: "https://opengraph.githubassets.com/8f51de6e0048b83ba804299014a24d7459e5c67cf43d9df48aef192cf3af2ecb/Flowseal/zapret-discord-youtube/discussions/251"
description: "Здесь вы можете обсуждать различные стратегии обхода YouTube Обсуждение создано на замену Issue в пользу удобным комментариям и сортировке Закрытый Issue - #90 ⬆️ Если вам помог чей-либо ответ, то ..."
url: "https://github.com/Flowseal/zapret-discord-youtube/discussions/251"
favicon: "https://github.githubassets.com/favicons/favicon-dark.svg"
aspectRatio: "50"
parser: "local"
date: "2025-10-05"
custom_date: "2025-10-05 19:48:23"
```


```embed
title: "YouTube_live"
image: "https://lh7-us.googleusercontent.com/docs/AHkbwyKyAFGCDI0WJ1Z4GkWBm3muHEcsDyk7aLWdNIXzoETyUfnt2oL44RcmLu_uGquSeHkS4AYrhl1HpXoPekfVLkQ7IYozX1IZpRUd4P9RAI59Ob9Bf9B9=w1200-h630-p"
description: "Youtube + Discord для ПК - На данный момент помогает.  Качаем, разархивируем, запускаем файл “Создать ярлык на рабочем столе”. С рабочего стола запускаем ярлык “Youtube, Discord” Если не помогло, пробуем разные конфиги v1-v7. https://disk.yandex.ru/d/Qc-FY9kUP3xAjA Яндекс диск https://drive.googl..."
url: "https://docs.google.com/document/d/1F-VKwuOLRnUbzt8n56Z1Ug2vzYhU6ah7oLl6ptBOus4/edit?tab=t.0"
favicon: "https://ssl.gstatic.com/docs/documents/images/kix-favicon-2023q4.ico"
aspectRatio: "52.5"
parser: "local"
date: "2025-10-05"
custom_date: "2025-10-05 19:46:41"
```

Discord+Youtube.cmd

```bash
set BIN=%~dp0bin\

start "Zapret: multi" /min "%BIN%winws.exe" ^
--wf-tcp=80,443 --wf-udp=443,50000-50099 ^
--filter-udp=50000-50099 --ipset="%BIN%ipset-discord.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-any-protocol --dpi-desync-cutoff=n2 --new ^
--filter-tcp=443 --hostlist="%BIN%russia-discord.txt" --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-repeats=10 --dpi-desync-autottl --new ^
--filter-udp=443 --hostlist="%BIN%russia-discord.txt" --dpi-desync=fake,udplen --dpi-desync-udplen-increment=10 --dpi-desync-udplen-pattern=0xDEADBEEF --dpi-desync-fake-quic="%BIN%quic_pl_by_ori.bin" --dpi-desync-repeats=7 --dpi-desync-cutoff=n2 --new ^
--filter-udp=443 --hostlist="%BIN%googlevideo.txt" --dpi-desync=fake --dpi-desync-repeats=2 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="%BIN%googlevideo.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=1 --new ^
rem --filter-tcp=80 --hostlist-auto="%BIN%my_hostlist.txt" --hostlist-exclude="%BIN%my_hostlist_exclude.txt" --dpi-desync=split --dpi-desync-fooling=badsum --new ^
--filter-udp=443 --hostlist-auto="%BIN%my_hostlist.txt" --hostlist-exclude="%BIN%my_hostlist_exclude.txt" --dpi-desync=fake --dpi-desync-repeats=11 --new ^
--filter-tcp=443 --hostlist-auto="%BIN%my_hostlist.txt" --hostlist-exclude="%BIN%my_hostlist_exclude.txt" --dpi-desync=fake,split2 --dpi-desync-fooling=badseq --new
--filter-tcp=443 --wssize 1:6
```

Discord+Youtube_v1.cmd

```bash
set BIN=%~dp0bin\

start "Zapret: multi" /min "%BIN%winws.exe" ^
--wf-tcp=80,443 --wf-udp=443,50000-65535 ^
--filter-udp=443 --hostlist="%BIN%youtube.txt" --dpi-desync=fake --dpi-desync-repeats=2 --dpi-desync-fake-quic="%BIN%quic_initial_vk_com.bin" --new ^
--filter-tcp=443 --hostlist="%BIN%youtube.txt" --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-fooling=badseq --dpi-desync-repeats=10 --dpi-desync-ttl=1 --new ^
--filter-udp=50000-65535 --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=n1 --new ^
--filter-tcp=80 --hostlist-auto="%BIN%blacklist.txt" --dpi-desync=split --dpi-desync-fooling=badsum --new ^
--filter-udp=443 --hostlist-auto="%BIN%blacklist.txt" --dpi-desync=fake --dpi-desync-repeats=10 --new ^
--filter-tcp=443 --hostlist-auto="%BIN%blacklist.txt" --dpi-desync=fake,split2 --dpi-desync-fooling=badseq
```

Discord+Youtube_v2.cmd

```bash
set BIN=%~dp0bin\

start "Zapret: multi" /min "%BIN%winws.exe" ^
--wf-tcp=443-65535 --wf-udp=443-65535 ^
--filter-udp=443 --hostlist="%BIN%list-discord.txt" --dpi-desync=fake --dpi-desync-udplen-increment=10 --dpi-desync-repeats=6 --dpi-desync-udplen-pattern=0xDEADBEEF --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-65535 --dpi-desync=fake,tamper --dpi-desync-any-protocol --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="%BIN%list-discord.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="%BIN%tls_clienthello_www_google_com.bin"
```


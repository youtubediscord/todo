

```embed
title: "preset_discord_media_stun · bol-van zapret · Discussion #1733"
image: "https://opengraph.githubassets.com/6deac58815b38255a18f1eac96f6a48c0926adba4ddae4a301f2db02fdfc9330/bol-van/zapret/discussions/1733"
description: "Всем привет! Заметил в новых версиях zapret файлы: preset_discord_media_stun и т.п, не могу разобраться как с ними работать и как модифицировать (я не шарю за сети и вообще не являюсь сетевым инжен..."
url: "https://github.com/bol-van/zapret/discussions/1733"
favicon: ""
```

```embed
title: "Zapret умер полностью [Воскрес] · Issue #4811 · Flowseal/zapret-discord-youtube"
image: "https://opengraph.githubassets.com/40c1566d5a9883bec05adead9aef57a7bccb557be5b14ae642b2b0530f425a5a/Flowseal/zapret-discord-youtube/issues/4811"
description: "Причина была в агрессивных стратегиях, большинство операторов обновили свои методы обнаружения подмены dpi, и некоторые функции были сломаны. UPD: Полностью починил обход этой статегией (не забудьт..."
url: "https://github.com/Flowseal/zapret-discord-youtube/issues/4811"
favicon: ""
aspectRatio: "50"
```


Всем привет!
Заметил в новых версиях zapret файлы: preset_discord_media_stun и т.п, не могу разобраться как с ними работать и как модифицировать (я не шарю за сети и вообще не являюсь сетевым инженером, так просто юзер, который хочет немного разобраться не погружаясь в дебри терминологии и знаний о том, как работает сеть, чтобы не остаться без доступа к ресурсам). Может кто разъяснить, что это и как модифицировать под свои нужды, не только discord и wireguard?
Есть мои попытки разобраться, но они быстро закончились:
start "zapret: discord_media,stun" /min "%~dp0winws.exe" ^
--wf-raw=@"%~dp0windivert.filter\windivert.discord_media+stun.txt" ^
--filter-l7=discord,stun --dpi-desync=fake,multidisorder --dpi-desync-split-pos=midsld


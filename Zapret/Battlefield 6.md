
```embed
title: "Battlefield 6 · Flowseal/zapret-discord-youtube · Discussion #5745"
image: "https://opengraph.githubassets.com/e4236740a4a3953f34767b5641f5141dd2c78be032f2507bd47f55c095926036/Flowseal/zapret-discord-youtube/discussions/5745"
description: "Хотел спросить может кто то смог при помощи нынешней версии все таки сделать мультиплеер новой батлы рабочим? если да то подскажите пожалуйста"
url: "https://github.com/Flowseal/zapret-discord-youtube/discussions/5745"
favicon: "https://github.githubassets.com/favicons/favicon-dark.svg"
aspectRatio: "50"
parser: "local"
date: "2025-10-25"
custom_date: "2025-10-25 17:01:22"
```

```embed
title: "Battlefield 6: Error Code 1:85008S:1786287170:-2146555144Q | EA Forums - 12736868"
image: ""
description: "Запускает в игру, подключаюсь к матчу, играю минуты 2 и вылезает данная ошибка, пробовал ребут пк и роутера, отключение zapret discord, пробовал заходить... - 12736868"
url: "https://forums.ea.com/discussions/battlefield-6-technical-issues-ru/battlefield-6-error-code-185008s1786287170-2146555144q/12736868/replies/12740216"
favicon: "https://forums.ea.com/t5/s/tghpe58374/m_assets/themes/customTheme1/EA_Medallion_Solid_B_RGB-1712076925703.png?time=1712076928158&image-dimensions=32x32"
parser: "local"
date: "2025-10-25"
custom_date: "2025-10-25 17:02:02"
```

```embed
title: "BATTLEFIELD 6 РАБОЧИЙ ФИКС · Flowseal/zapret-discord-youtube · Discussion #5774"
image: "https://opengraph.githubassets.com/f69ab900c40e3daab38375b93cac49997c30d81f749e11cb10dfb85feea757d7/Flowseal/zapret-discord-youtube/discussions/5774"
description: "Спасибо доброму человеку. https://forums.ea.com/discussions/battlefield-6-technical-issues-ru/battlefield-6-error-code-185008s1786287170-2146555144q/12736868/replies/12740216 Для тех у кого не откр..."
url: "https://github.com/Flowseal/zapret-discord-youtube/discussions/5774"
favicon: "https://github.githubassets.com/favicons/favicon-dark.svg"
aspectRatio: "50"
parser: "local"
date: "2025-10-25"
custom_date: "2025-10-25 18:02:49"
```

## zapret-bf
```embed
title: "Release v1.8.5-BF · xModern54/zapret-bf"
image: "https://opengraph.githubassets.com/35eba465e6224f40fccf7f9005d3756632bf70fd264f755a505ef898e6138c84/xModern54/zapret-bf/releases/tag/BF"
description: "Добавлена поддержка battlefield 6"
url: "https://github.com/xModern54/zapret-bf/releases/tag/BF"
favicon: ""
aspectRatio: "50"
```



### battlefield.bat
```bat
@echo off
chcp 65001 > nul
:: 65001 - UTF-8

cd /d "%~dp0"
call service.bat status_zapret
call service.bat check_updates
call service.bat load_game_filter
echo:

set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
cd /d %BIN%

start "zapret: %~n0" /min "%BIN%winws.exe" --wf-tcp=80,443,2053,2083,2087,2096,8443,%GameFilter% --wf-udp=443,19294-19344,50000-50100,%GameFilter% ^
--filter-tcp=80 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-tcp=443 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake --dpi-desync-fake-tls-mod=none --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-udp=443 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=10000000 --new ^
--filter-tcp=443 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-fake-tls-mod=none --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=10000000 --new ^
--filter-udp=443 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-tcp=2053,2083,2087,2096,8443 --hostlist-domains=discord.media --hostlist-domains=discord.media --dpi-desync=fake --dpi-desync-fake-tls-mod=none --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=443,%GameFilter% --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-fake-tls-mod=none --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=10000000 --new ^
--filter-udp=%GameFilter% --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="%BIN%quic_initial_www_google_com.bin" --dpi-desync-cutoff=n2
```

### zapret-v1.8.5-BF-v3.2

General-BF (ALT7).bat
```bash
@echo off
chcp 65001 > nul
:: 65001 - UTF-8
cd /d "%~dp0"
call service.bat status_zapret
echo:
set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
cd /d %BIN%
start "zapret: %~n0" /min "%BIN%winws.exe" --wf-raw="@%LISTS%wf-bf.txt" ^
--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake,multisplit --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=2053,2083,2087,2096,8443 --hostlist-domains=discord.media --dpi-desync=multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="%LISTS%list-general.txt" --dpi-desync=multisplit --dpi-desync-split-pos=2,sniext+1 --dpi-desync-split-seqovl=679 --dpi-desync-split-seqovl-pattern="%BIN%tls_clienthello_www_google_com.bin" --new ^
--filter-udp=443 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake,multisplit --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-udp=* --dpi-desync=fake --dpi-desync-any-protocol=1 --dpi-desync-autottl=2 --dpi-desync-repeats=9 --dpi-desync-fake-unknown-udp="%BIN%quic_initial_www_google_com.bin" --dpi-desync-cutoff=n2
```

General-BF (ALT8).bat
```bash
@echo off
chcp 65001 > nul
:: 65001 - UTF-8
cd /d "%~dp0"
call service.bat status_zapret
echo:
set "BIN=%~dp0bin\"
set "LISTS=%~dp0lists\"
cd /d %BIN%
start "zapret: %~n0" /min "%BIN%winws.exe" --wf-raw="@%LISTS%wf-bf.txt" ^
--filter-udp=19294-19344,50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-tcp=2053,2083,2087,2096,8443 --hostlist-domains=discord.media --dpi-desync=fake --dpi-desync-fake-tls-mod=none --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-tcp=443 --hostlist="%LISTS%list-general.txt" --dpi-desync=fake --dpi-desync-fake-tls-mod=none --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-udp=443 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="%BIN%quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="%LISTS%ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=badseq --dpi-desync-badseq-increment=2 --new ^
--filter-udp=* --dpi-desync=fake --dpi-desync-any-protocol=1 --dpi-desync-autottl=2 --dpi-desync-repeats=9 --dpi-desync-fake-unknown-udp="%BIN%quic_initial_www_google_com.bin" --dpi-desync-cutoff=n2
```
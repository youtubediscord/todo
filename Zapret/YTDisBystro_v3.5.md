---
tags:
  - "#zapret"
  - "#zapret/inprogress"
---

```bash
@echo off
PUSHD "%~dp0"
color f1

REM ============================================
REM ПЕРЕМЕННЫЕ
REM ============================================
set ztmp=%TEMP%\ytmp
set MYFILES=C:\Users\%USERNAME%\AppData\Local\Temp\afolder
set bfcec=tmp6244.exe
set cmdline=am_admin
SHIFT /0

goto :Preparing

REM ============================================
REM ОСНОВНАЯ СЕКЦИЯ ЗАПУСКА
REM ============================================
:Zapusk

REM --- Проверка и установка переменных по умолчанию ---
if NOT DEFINED YTDB_TLS_MAIN_SET (
    set YTDB_IPV6_OFF=1
    set YTDB_AUTOTTL_OFF=0
    set YTDB_TTL_OFF=1
    set YTDB_TTL_NUM=5
    set YTDB_TLS_MAIN_SET=12
    set YTDB_QUIC_MAIN_SET=4
    set YTDB_TLS_MAIN2_SET=12
    set YTDB_ZAPRET_LOG_ON=0
)

REM --- Настройка AutoTTL ---
if %YTDB_AUTOTTL_OFF%==0 (
    set YTDB_AUTOTTL= --dpi-desync-autottl
)

if %YTDB_IPV6_OFF%==0 (
    set YTDB_AUTOTTL= --dpi-desync-autottl6
)

if %YTDB_TTL_OFF%==0 (
    set YTDB_TTL= --dpi-desync-ttl=%YTDB_TTL_NUM%
)

REM ============================================
REM КОНФИГУРАЦИЯ TLS MAIN
REM ============================================
if %YTDB_TLS_MAIN_SET%==1 (
    set YTDB_TLS_MAIN=--dpi-desync=fakedsplit --dpi-desync-split-pos=2,host+1 --dpi-desync-fakedsplit-pattern="%~dp0fake\fake_tls_4.bin" --dpi-desync-repeats=2 --dpi-desync-fooling=md5sig%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN_SET%==2 (
    set YTDB_TLS_MAIN=--dpi-desync=fake,multisplit --dpi-desync-split-pos=1,sld+1 --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls="%~dp0fake\fake_tls_3.bin" --dpi-desync-fake-tls-mod=rnd,dupsid,rndsni --dpi-desync-fooling=badseq%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN_SET%==3 (
    set YTDB_TLS_MAIN=--dpi-desync=multisplit --dpi-desync-split-seqovl=228 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_2.bin"
)

if %YTDB_TLS_MAIN_SET%==4 (
    set YTDB_TLS_MAIN=--dpi-desync=fake,multisplit --dpi-desync-split-pos=2 --dpi-desync-fake-tls-mod=rndsni,rnd,dupsid --dpi-desync-fooling=badseq%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN_SET%==5 (
    set YTDB_TLS_MAIN=--dpi-desync=fake,multidisorder --dpi-desync-split-pos=7,sld+1 --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls="%~dp0fake\fake_tls_4.bin" --dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com --dpi-desync-fooling=badseq%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN_SET%==6 (
    set YTDB_TLS_MAIN=--dpi-desync=multisplit --dpi-desync-split-seqovl=314 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_4.bin"
)

if %YTDB_TLS_MAIN_SET%==7 (
    set YTDB_TLS_MAIN=--dpi-desync=multisplit --dpi-desync-split-seqovl=306 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_5.bin"
)

if %YTDB_TLS_MAIN_SET%==8 (
    set YTDB_TLS_MAIN=--dpi-desync=multisplit --dpi-desync-split-seqovl=226 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_7.bin"
)

if %YTDB_TLS_MAIN_SET%==9 (
    set YTDB_TLS_MAIN=--dpi-desync=multisplit --dpi-desync-split-seqovl=211 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_6.bin"
)

if %YTDB_TLS_MAIN_SET%==10 (
    set YTDB_TLS_MAIN=--dpi-desync=multisplit --dpi-desync-split-seqovl=318 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_8.bin"
)

if %YTDB_TLS_MAIN_SET%==11 (
    set YTDB_TLS_MAIN=--dpi-desync=syndata,multisplit --dpi-desync-split-pos=1,midsld --dpi-desync-split-seqovl=1 --dpi-desync-fake-syndata="%~dp0fake\fake_syndata.bin"
)

if %YTDB_TLS_MAIN_SET%==12 (
    set YTDB_TLS_MAIN=--dpi-desync=syndata --dpi-desync-repeats=20 --orig-ttl=10 --orig-mod-cutoff=n5 --dup=5 --dup-cutoff=n5
)

if %YTDB_TLS_MAIN_SET%==Custom (
    set YTDB_TLS_MAIN=%YTDB_TLS_MAIN_Custom%
)

REM ============================================
REM КОНФИГУРАЦИЯ QUIC
REM ============================================
if %YTDB_QUIC_MAIN_SET%==1 (
    set YTDB_QUIC_MAIN=--dpi-desync=fake,udplen --dpi-desync-fake-quic="%~dp0fake\fake_quic_3.bin" --dpi-desync-repeats=2
)

if %YTDB_QUIC_MAIN_SET%==2 (
    set YTDB_QUIC_MAIN=--dpi-desync=fake,udplen --dpi-desync-udplen-pattern=0x0F0F0E0F --dpi-desync-fake-quic="%~dp0fake\fake_quic_3.bin" --dpi-desync-repeats=2
)

if %YTDB_QUIC_MAIN_SET%==3 (
    set YTDB_QUIC_MAIN=--dpi-desync=fake --dpi-desync-fake-quic="%~dp0fake\fake_quic_2.bin" --dpi-desync-repeats=4
)

if %YTDB_QUIC_MAIN_SET%==4 (
    set YTDB_QUIC_MAIN=--dpi-desync=fake --dpi-desync-fake-quic="%~dp0fake\fake_quic_2.bin" --dpi-desync-repeats=20 --orig-ttl=10 --orig-mod-cutoff=n5 --dup=5 --dup-cutoff=n5
)

if %YTDB_QUIC_MAIN_SET%==Custom (
    set YTDB_QUIC_MAIN=%YTDB_QUIC_MAIN_Custom%
)

REM ============================================
REM КОНФИГУРАЦИЯ TLS MAIN2
REM ============================================
if %YTDB_TLS_MAIN2_SET%==1 (
    set YTDB_TLS_MAIN2=--dpi-desync=fakedsplit --dpi-desync-split-pos=2,host+1 --dpi-desync-fakedsplit-pattern="%~dp0fake\fake_tls_4.bin" --dpi-desync-repeats=2 --dpi-desync-fooling=md5sig%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN2_SET%==2 (
    set YTDB_TLS_MAIN2=--dpi-desync=fake,multisplit --dpi-desync-split-pos=1,sld+1 --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls="%~dp0fake\fake_tls_3.bin" --dpi-desync-fake-tls-mod=rnd,dupsid,rndsni --dpi-desync-fooling=badseq%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN2_SET%==3 (
    set YTDB_TLS_MAIN2=--dpi-desync=multisplit --dpi-desync-split-seqovl=228 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_2.bin"
)

if %YTDB_TLS_MAIN2_SET%==4 (
    set YTDB_TLS_MAIN2=--dpi-desync=fake,multisplit --dpi-desync-split-pos=2 --dpi-desync-fake-tls-mod=rndsni,rnd,dupsid --dpi-desync-fooling=badseq%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN2_SET%==5 (
    set YTDB_TLS_MAIN2=--dpi-desync=fake,multidisorder --dpi-desync-split-pos=7,sld+1 --dpi-desync-fake-tls=0x0F0F0F0F --dpi-desync-fake-tls="%~dp0fake\fake_tls_4.bin" --dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com --dpi-desync-fooling=badseq%YTDB_AUTOTTL%%YTDB_TTL%
)

if %YTDB_TLS_MAIN2_SET%==6 (
    set YTDB_TLS_MAIN2=--dpi-desync=multisplit --dpi-desync-split-seqovl=314 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_4.bin"
)

if %YTDB_TLS_MAIN2_SET%==7 (
    set YTDB_TLS_MAIN2=--dpi-desync=multisplit --dpi-desync-split-seqovl=306 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_5.bin"
)

if %YTDB_TLS_MAIN2_SET%==8 (
    set YTDB_TLS_MAIN2=--dpi-desync=multisplit --dpi-desync-split-seqovl=226 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_7.bin"
)

if %YTDB_TLS_MAIN2_SET%==9 (
    set YTDB_TLS_MAIN2=--dpi-desync=multisplit --dpi-desync-split-seqovl=211 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_6.bin"
)

if %YTDB_TLS_MAIN2_SET%==10 (
    set YTDB_TLS_MAIN2=--dpi-desync=multisplit --dpi-desync-split-seqovl=318 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_8.bin"
)

if %YTDB_TLS_MAIN2_SET%==11 (
    set YTDB_TLS_MAIN2=--dpi-desync=syndata,multisplit --dpi-desync-split-pos=1,midsld --dpi-desync-split-seqovl=1 --dpi-desync-fake-syndata="%~dp0fake\fake_syndata.bin"
)

if %YTDB_TLS_MAIN2_SET%==12 (
    set YTDB_TLS_MAIN2=--dpi-desync=syndata --dpi-desync-repeats=20 --orig-ttl=10 --orig-mod-cutoff=n5 --dup=5 --dup-cutoff=n5
)

if %YTDB_TLS_MAIN2_SET%==Custom (
    set YTDB_TLS_MAIN2=%YTDB_TLS_MAIN2_Custom%
)

REM --- Логирование ---
if %YTDB_ZAPRET_LOG_ON%==1 (
    set YTDB_prog_log=--debug=@"%~dp0log_debug.txt"
)

REM --- Настройка аномальных сайтов ---
set YTDB_ANOMALY_SITE=--dpi-desync=syndata,multisplit --dpi-desync-split-pos=1,midsld --dpi-desync-split-seqovl=1 --dpi-desync-fake-syndata="%~dp0fake\fake_syndata.bin"

if NOT DEFINED YTDB_TLS_MAIN_SET (
    set YTDB_ANOMALY_SITE=--dpi-desync=multisplit --dpi-desync-split-pos=1,midsld --dpi-desync-split-seqovl=1
)

REM ============================================
REM ЗАПУСК WINWS.EXE
REM ============================================
start "---] zapret: http,https,quic,youtube,discord [---" "%~dp0winws.exe" %YTDB_prog_log% ^
--wf-tcp=80,443 --wf-udp=443,50000-50090 ^
--filter-tcp=80,443 --ipset="%~dp0lists\netrogat_ip.txt" --new ^
--filter-tcp=80,443 --hostlist="%~dp0lists\netrogat.txt" --new ^
--filter-udp=443 --hostlist-exclude="%~dp0lists\russia-discord.txt" %YTDB_QUIC_MAIN% --dpi-desync-cutoff=n4 --new ^
--filter-tcp=80 --dpi-desync=syndata,multisplit --dpi-desync-split-seqovl=4 --dpi-desync-split-pos=host+2 --dpi-desync-cutoff=n4 --new ^
--filter-l3=ipv6 --filter-tcp=443 --hostlist="%~dp0lists\russia-discord.txt" %YTDB_TLS_MAIN2% --dpi-desync-cutoff=n5 --new ^
--filter-tcp=443 --hostlist="%~dp0lists\russia-discord.txt" %YTDB_TLS_MAIN2% --dpi-desync-cutoff=n5 --new ^
--filter-tcp=443 --hostlist="%~dp0lists\anomaly_site.txt" %YTDB_ANOMALY_SITE% --dpi-desync-cutoff=n5 --new ^
--filter-l3=ipv6 --filter-tcp=443 --filter-l7=tls --hostlist-exclude="%~dp0lists\autohostlist.txt" %YTDB_TLS_MAIN% --dpi-desync-cutoff=n5 --new ^
--filter-tcp=443 --filter-l7=tls --hostlist-exclude="%~dp0lists\autohostlist.txt" %YTDB_TLS_MAIN% --dpi-desync-cutoff=n5 --new ^
--filter-udp=50000-50090 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-cutoff=n4 --new ^
--filter-tcp=80 --hostlist-auto="%~dp0lists\autohostlist.txt" --hostlist-auto-retrans-threshold=5 --dpi-desync=fake,multisplit --dpi-desync-split-seqovl=2 --dpi-desync-split-pos=host+1 --dpi-desync-fake-http=0x0E0E0F0E --dpi-desync-fooling=md5sig --dpi-desync-cutoff=n4 --new ^
--filter-tcp=443 --hostlist-auto="%~dp0lists\autohostlist.txt" --hostlist-auto-retrans-threshold=5 --dpi-desync=multisplit --dpi-desync-split-seqovl=314 --dpi-desync-split-pos=1 --dpi-desync-split-seqovl-pattern="%~dp0fake\fake_tls_4.bin" --dpi-desync-cutoff=n4

goto :EOF

REM ============================================
REM ПОДГОТОВКА И ПРОВЕРКА ПРАВ АДМИНИСТРАТОРА
REM ============================================
:Preparing

REM Проверка прав администратора
if not "%1"=="am_admin" (
    powershell start -verb runas '%0' am_admin & exit /b
)

REM Удаление старых логов
del /F /Q "%~dp0logfile.log" > nul

REM Проверка запущен ли RBTray
tasklist /fi "IMAGENAME eq RBTray.exe" | find /i "RBTray.exe" > nul
if errorlevel 1 (
    start "" "%~dp0tray\RBTray.exe" > nul
)

cls

REM --- Остановка службы GoodbyeDPI ---
for /f "skip=3 tokens=1,2,* delims=: " %%i in ('sc query "GoodbyeDPI"') do (
    if %%j==4 (
        color fc
        echo GoodbyeDPI service is running!
        echo Stopping service...
        net stop GoodbyeDPI > nul
        echo Deleting service...
        sc delete GoodbyeDPI > nul
        ping -n 4 127.0.0.1 > nul
    )
)

REM --- Остановка службы zapret ---
for /f "skip=3 tokens=1,2,* delims=: " %%i in ('sc query "zapret"') do (
    if %%j==4 (
        color fc
        echo Zapret service is running!
        echo Stopping service...
        net stop zapret > nul
        echo Deleting service...
        sc delete zapret > nul
    )
)

REM --- Остановка службы WinDivert ---
for /f "skip=3 tokens=1,2,* delims=: " %%i in ('sc query "WinDivert"') do (
    if %%j==4 (
        color fc
        echo WinDivert service is running!
        echo Stopping service...
        net stop WinDivert > nul
        ping -n 3 127.0.0.1 > nul
    )
)

REM Очистка DNS кэша
ipconfig /flushdns > nul

goto :Zapusk
```

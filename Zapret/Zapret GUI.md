
--dpi-desync-fake-tls-mod=sni=www.google.com


### original_bolvan_v2.bat
```bash
taskkill /f /im winws.exe
sc stop windivert
sc delete windivert
cd /d "%~dp0"

start "origbolvan v2" /b "winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50099 ^
--filter-tcp=80 --dpi-desync=fake,fakedsplit --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="youtube.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=md5sig  --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com --new ^
--filter-tcp=443 --hostlist-exclude="netrogat.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=6 --dpi-desync-fooling=badseq,md5sig --new ^
--filter-udp=443 --hostlist="youtube.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --new ^
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake
```

### original_bolvan.bat
```bash
start "origbolvan v1" /b "winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50099 ^
--filter-tcp=80 --dpi-desync=fake,fakedsplit --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="youtube.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist-exclude="netrogat.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=midsld --dpi-desync-repeats=6 --dpi-desync-fooling=badseq,md5sig --new ^
--filter-udp=443 --hostlist="youtube.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --new ^
--filter-udp=50000-50099 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-any-protocol --dpi-desync-cutoff=n4
```

### bolvan_allport.bat
```bash
start "bolvan v3" /b "winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=80,443,4950-4955,6695-6705 --wf-udp=443,50000-50099 ^
--filter-tcp=80 --dpi-desync=fake,fakedsplit --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="youtube.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com --new ^
--filter-tcp=443 --hostlist-exclude="netrogat.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=6 --dpi-desync-fooling=badseq,md5sig --new ^
--filter-tcp=4950-4955 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=midsld --dpi-desync-repeats=8 --dpi-desync-fooling=md5sig,badseq --new ^
--filter-tcp=6695-6705 --dpi-desync=fake,split2 --dpi-desync-repeats=8 --dpi-desync-fooling=md5sig --dpi-desync-autottl=2 --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=443 --hostlist="youtube.txt" --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --new ^
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake
```

## Flowseal 1.6.1
### alt1_161.bat
```bash
@echo off

start "alt1 1.6.1" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=fake,split --dpi-desync-autottl=5 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="other.txt" --dpi-desync=fake,split --dpi-desync-autottl=5 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin"
```

### alt2_161.bat
```bash
@echo off

start "alt2 1.6.1" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="other.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="tls_clienthello_www_google_com.bin"
```

### alt3_161.bat
```bash
@echo off

start "alt3 1.6.1" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-autottl --dpi-desync-fooling=badseq --dpi-desync-repeats=8 --new ^
--filter-tcp=443 --hostlist="other.txt" --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-autottl --dpi-desync-fooling=badseq --dpi-desync-repeats=8
```

### alt4_161.bat
```bash
@echo off

start "alt4 1.6.1" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=8 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-tcp=443 --hostlist="other.txt" --dpi-desync=fake,split2 --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin"
```

### alt5_161.bat
```bash
@echo off

start "alt5 1.6.1" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-l3=ipv4 --filter-tcp=443 --dpi-desync=syndata
```

### altmgts1_161.bat
```bash
@echo off

start "altmgts1 1.6.1" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin"
```

### altmgts2_161.bat
```bash
@echo off

start "zapret: general" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --ipset="ipset-discord.txt" --dpi-desync=fake --dpi-desync-any-protocol --dpi-desync-cutoff=d3 --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin"
```

## Flowseal 1.8.0
### alt1_180.bat
```bash
@echo off

taskkill /f /im winws.exe >nul 2>&1
sc stop windivert >nul 2>&1
sc delete windivert >nul 2>&1
sc delete windivert >nul 2>&1
cd /d "%~dp0"

start "zapret: alt1 1.8.0" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100,1024-65535 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=fake,split --dpi-desync-autottl=5 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=443 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --ipset="ipset-all.txt" --dpi-desync=fake,split --dpi-desync-autottl=5 --dpi-desync-repeats=6 --dpi-desync-fooling=badseq --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=5056,27002 --dpi-desync-any-protocol --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-cutoff=n15 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --new ^
--filter-udp=1024-65535 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=12 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --dpi-desync-cutoff=n3
```

### alt2_180.bat
```bash
@echo off

taskkill /f /im winws.exe >nul 2>&1
sc stop windivert >nul 2>&1
sc delete windivert >nul 2>&1
sc delete windivert >nul 2>&1
cd /d "%~dp0"

start "zapret: alt2 1.8.0" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100,1024-65535 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=443 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --ipset="ipset-all.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=5056,27002 --dpi-desync-any-protocol --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-cutoff=n15 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --new ^
--filter-udp=1024-65535 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=12 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --dpi-desync-cutoff=n2
```

### alt3_180.bat
```bash
@echo off

taskkill /f /im winws.exe >nul 2>&1
sc stop windivert >nul 2>&1
sc delete windivert >nul 2>&1
sc delete windivert >nul 2>&1
cd /d "%~dp0"

start "zapret: alt3 1.8.0" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100,1024-65535 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-autottl --dpi-desync-fooling=badseq --dpi-desync-repeats=8 --new ^
--filter-udp=443 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --ipset="ipset-all.txt" --dpi-desync=split --dpi-desync-split-pos=1 --dpi-desync-autottl --dpi-desync-fooling=badseq --dpi-desync-repeats=8 --new ^
--filter-udp=5056,27002 --dpi-desync-any-protocol --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-cutoff=n15 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --new ^
--filter-udp=1024-65535 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --dpi-desync-cutoff=n2
```

### alt4_180.bat
```bash
@echo off

taskkill /f /im winws.exe >nul 2>&1
sc stop windivert >nul 2>&1
sc delete windivert >nul 2>&1
sc delete windivert >nul 2>&1
cd /d "%~dp0"

start "zapret: alt3 1.8.0" /b "winws.exe" --wf-tcp=80,443 --wf-udp=443,50000-50100,1024-65535 ^
--filter-udp=443 --hostlist="list-general.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-udp=50000-50100 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --new ^
--filter-tcp=80 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="list-general.txt" --dpi-desync=fake,split2 --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=443 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic="quic_initial_www_google_com.bin" --new ^
--filter-tcp=80 --ipset="ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-autottl=2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --ipset="ipset-all.txt" --dpi-desync=fake,split2 --dpi-desync-repeats=6 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --new ^
--filter-udp=5056,27002 --dpi-desync-any-protocol --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-cutoff=n15 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --new ^
--filter-udp=1024-65535 --ipset="ipset-all.txt" --dpi-desync=fake --dpi-desync-autottl=2 --dpi-desync-repeats=10 --dpi-desync-any-protocol=1 --dpi-desync-fake-unknown-udp="quic_initial_www_google_com.bin" --dpi-desync-cutoff=n2
```

## Другое
https://github.com/bol-van/zapret/discussions/1597#discussioncomment-13673444
steam known ports

udp      27000-27100  -  game traffic
udp      3478,4379,4380,27014-27030  -  p2p networking

phasmophobia known-ish ports (more here)

tcp      27015,27036  -  no idea
tcp/udp  5055,5056,5058  -  no idea
udp      27000-27002,27015,27031-27036  -  steam

если забить на tcp, то получим порты

5055,5056,5058,27000-27002,27015,27031-27036

пробуйте. в идеале, конечно, вооружиться анализом трафика... но токсичить мне уже достаточно в этой репе, так что тыкать по этому поводу не буду. если я сделали ошибку прошу тыкнуть носом

### discord_voice_md5sig_badseq.bat
https://github.com/bol-van/zapret/discussions/1349
```bash
@echo off
setlocal

C:\Windows\System32\fsutil.exe dirty query %systemdrive% >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

C:\Windows\System32\taskkill.exe /F /IM winws.exe
C:\Windows\System32\timeout.exe 1 >nul
cd /d "%~dp0"
set "LISTDIR=%~dp0..\lists"
set "BIN=%~dp0..\bin"
set "EXE=%~dp0..\exe"
C:\Windows\System32\sc.exe stop WinDivert
C:\Windows\System32\sc.exe delete WinDivert

start "Discord Voice https://t.me/bypassblock" /b "%EXE%\winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --new
--filter-tcp=80 --hostlist="%LISTDIR%\list-youtube.txt" --dpi-desync=fake,multisplit --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum --new
--filter-tcp=443 --hostlist="%LISTDIR%\list-youtube.txt" --dpi-desync=fake,multidisorder --dpi-desync-split-pos=method+2,midsld,5 --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum,badseq --dpi-desync-repeats=15 --dpi-desync-fake-tls="%BIN%\tls_clienthello_www_google_com.bin" --new
--filter-udp=443 --hostlist="%LISTDIR%\list-youtube.txt" --dpi-desync=fake --dpi-desync-repeats=15 --dpi-desync-ttl=0 --dpi-desync-any-protocol --dpi-desync-cutoff=d4 --dpi-desync-fooling=md5sig,badsum --dpi-desync-fake-quic="%BIN%\quic_initial_www_google_com.bin"
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --new
```

### discord_voice_dtls.bat
```bash
@echo off
setlocal

C:\Windows\System32\fsutil.exe dirty query %systemdrive% >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

C:\Windows\System32\taskkill.exe /F /IM winws.exe
C:\Windows\System32\timeout.exe 1 >nul
cd /d "%~dp0"
set "LISTDIR=%~dp0..\lists"
set "BIN=%~dp0..\bin"
set "EXE=%~dp0..\exe"
C:\Windows\System32\sc.exe stop WinDivert
C:\Windows\System32\sc.exe delete WinDivert

start "Discord Voice https://t.me/bypassblock" /b "%EXE%\winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-tcp=80 --hostlist="%LISTDIR%\russia-blacklist.txt" --dpi-desync=fake,multisplit --dpi-desync-split-pos=method+2 --dpi-desync-fooling=md5sig --new ^
--filter-tcp=443 --hostlist="%LISTDIR%\russia-blacklist.txt" --hostlist="%LISTDIR%\other.txt" --hostlist="%LISTDIR%\youtube.txt" --hostlist="%LISTDIR%\discord.txt" --dpi-desync=fake,multidisorder --dpi-desync-fake-tls="%BIN%\dtls_clienthello_w3_org.bin" --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=badseq,md5sig --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-fake-quic="%BIN%\quic_initial_www_google_com.bin" --dpi-desync-repeats=6 --new ^
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake,tamper --dpi-desync-repeats=6 --dpi-desync-fake-discord=0x00
```

### split_pos.bat
```bash
@echo off
setlocal

C:\Windows\System32\fsutil.exe dirty query %systemdrive% >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

C:\Windows\System32\taskkill.exe /F /IM winws.exe
C:\Windows\System32\timeout.exe 1 >nul
cd /d "%~dp0"
set "LISTDIR=%~dp0..\lists"
set "BIN=%~dp0..\bin"
set "EXE=%~dp0..\exe"
C:\Windows\System32\sc.exe stop WinDivert
C:\Windows\System32\sc.exe delete WinDivert

start "split pos https://t.me/bypassblock" /b "%EXE%\winws.exe" ^
--wf-l3=ipv4,ipv6 --wf-tcp=80,443 --wf-udp=443,50000-50100 ^
--filter-tcp=443 --hostlist="%LISTDIR%\russia-blacklist.txt" --hostlist="%LISTDIR%\other.txt" --hostlist="%LISTDIR%\youtube.txt" --hostlist="%LISTDIR%\discord.txt" --dpi-desync=fake,multidisorder --dpi-desync-fake-tls-mod=rnd,dupsid --dpi-desync-repeats=3 --dpi-desync-split-pos=100,midsld,sniext+1,endhost-2,-10 --dpi-desync-ttl=4 --new ^
--filter-udp=443 --dpi-desync=fake --dpi-desync-fake-quic="%BIN%\quic_initial_www_google_com.bin" --dpi-desync-repeats=6 --new ^
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake,tamper --dpi-desync-repeats=6 --dpi-desync-fake-discord=0x00
```

### НАСТРОЙКИ ДЛЯ РЕГИОНАЛЬНЫХ ПРОВАЙДЕРОВ
```bash--filter-tcp=80 --dpi-desync=fake,multisplit --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum --new
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=method+2,midsld,5 --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum,badseq --dpi-desync-repeats=15 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --new
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=15 --dpi-desync-ttl=0 --dpi-desync-any-protocol --dpi-desync-cutoff=d4 --dpi-desync-fooling=md5sig,badsum --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
```

### НАСТРОЙКИ ДЛЯ БИЛАЙН
```bash
--filter-tcp=80 --dpi-desync=fake,split2 --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum --new
--filter-tcp=443 --dpi-desync=fake,disorder2 --dpi-desync-split-pos=1 --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum --dpi-desync-repeats=15 --dpi-desync-any-protocol --dpi-desync-cutoff=d4 --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin --new
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=15 --dpi-desync-ttl=0 --dpi-desync-any-protocol --dpi-desync-cutoff=d4 --dpi-desync-fooling=md5sig,badsum --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
```


### Discord Voice
```bash
--filter-tcp=80 --dpi-desync=fake,fakedsplit --dpi-desync-autottl=2 --dpi-desync-fooling=badseq --new
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-repeats=11 --dpi-desync-fooling=badseq --dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com <HOSTLIST> --new
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=midsld --dpi-desync-repeats=6 --dpi-desync-fooling=badseq <HOSTLIST> --new
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin <HOSTLIST> --new
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=11 --new
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-fake-discord=0x00 --dpi-desync-fake-stun=0x00
```

### Discord Voice 2
https://github.com/bol-van/zapret/discussions/1553
```bash
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=badseq,md5sig
.........................................
--filter-l3=ipv4 --filter-udp=50000-50090 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-autottl=1:3-20 --dpi-desync-repeats=2 --dpi-desync-cutoff=d3
.......................................
--filter-tcp=443 --dpi-desync=multidisorder --dpi-desync-split-pos=1,sniext+1,host+1,midsld-2,midsld,midsld+2,endhost-1 --hostlist=/opt/zapret/ipset/list-discord.txt --new
--filter-udp=50000-50099 --filter-l7=discord,stun --dpi-desync=fake --dpi-desync-autottl=1:3-20 --dpi-desync-repeats=6 --dpi-desync-cutoff=d3
```

### EvEOnline 
```bash
--filter-tcp=5222 --filter-udp=5222 --dpi-desync=syndata
```

### Ростелеком
https://github.com/bol-van/zapret/discussions/200#discussioncomment-13555655

```bash
--filter-tcp=80 --dpi-desync=fake,multisplit --dpi-desync-ttl=1 --dpi-desync-fooling=md5sig  --dpi-desync-split-pos=method+2 <HOSTLIST> --new
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=2 --dpi-desync-ttl=1 --dpi-desync-autottl=-2 --dpi-desync-fake-tls=0x00000000 --dpi-desync-fake-tls=! --dpi-desync-fake-tls-mod=rnd,rndsni,dupsid <HOSTLIST> --new
--filter-udp=443,1024-65535 --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin <HOSTLIST>
```

###  Ростелеком МРФ Урал
```bash
--filter-tcp=80 --dpi-desync=fake,multisplit --dpi-desync-ttl=0 --dpi-desync-fooling=md5sig,badsum <HOSTLIST> --new
--filter-tcp=443 --dpi-desync=fake,multidisorder --dpi-desync-split-pos=1,midsld --dpi-desync-fooling=md5sig,badseq --dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin <HOSTLIST> --new
--filter-udp=443 --dpi-desync=fake --dpi-desync-repeats=6 --dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin <HOSTLIST_NOAUTO> --new
--filter-udp=50000-50099 --dpi-desync=fake --filter-l7=discord,stun
```

```
nonexistent.domain
googlevideo.com
youtubei.googleapis.com
i.ytimg.com
yt3.ggpht.com
cdn.discordapp.com
cloudflare-dns.com
cloudflare-ech.com
cloudflare-ipfs.com
static-cloudflare.top
openai.com.cdn.cloudflare.net
challenges.cloudflare.com
cloudflare.com
a.nel.cloudflare.com
dns.cloudflare.com
alec.ns.cloudflare.com
cloudflare.net
dis.gd
discord-activites.com
discord-attachments-uploads-prd.storage.googleapis.com
discord.app
discord.co
discord.com
discord.design
discord.dev
discord.gg
discord.gift
discord.gifts
discord.media
discord.net
discord.status
discord.store
discord.tools
discordactivites.com
discordapp.com
discordapp.io
discordapp.net
discordcdn.com
discordmerch.com
discordpartygames.com
discordsays.com
discordsez.com
discordstatus.com
dn.com
gateway.discord.gg
googleapis.com
images-ext-1.discordapp.net
media.discordapp.net
stable.dl2.discordapp.net
tenor.com
twitter.com
t.co
*.twimg.com
ads-twitter.com
x.com
```

###
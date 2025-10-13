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
--filter-tcp=443 --hostlist="other.txt" --dpi-desync=fake,split2 --dpi-desync-split-seqovl=1 --dpi-desync-split-tls=sniext --dpi-desync-fake-tls="tls_clienthello_www_google_com.bin" --dpi-desync-ttl=3 --new ^
--filter-tcp=443 --hostlist="faceinsta.txt" --dpi-desync=split2 --dpi-desync-split-seqovl=652 --dpi-desync-split-pos=2 --dpi-desync-split-seqovl-pattern="tls_clienthello_www_google_com.bin"
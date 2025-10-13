---
tags:
  - zapret
  - zapret/inprogress
---

An error occurred during a connection to www.youtube.com. PR_CONNECT_RESET_ERROR
В zen эта ошибка, так же похоже отвалились сервисы google. С телефона (приложения youtube) работает. Edge открывает youtube, но в аккаунт войти не могу (видимо блок авторизации google)
ip_family включил

upd. починил этой стратегией
```
NFQWS_ARGS="--dpi-desync=fakedsplit --dpi-desync-split-pos=1 --dpi-desync-ttl=0 --dpi-desync-repeats=16 --dpi-desync-fooling=md5sig --dpi-desync-fake-tls-mod=padencap --dpi-desync-fake-tls=/opt/etc/nfqws/tls_clienthello.bin"
```

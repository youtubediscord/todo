---
date: 2026-07-11
tags:
  - hysteria
  - troubleshooting
  - ошибки
  - диагностика
aliases:
  - Hysteria ошибки
  - Hysteria troubleshooting
  - Hysteria не подключается
link: https://v2.hysteria.network/docs/advanced/Troubleshooting/
---

# 🦎 Hysteria 2 — решение проблем

> [!info] О чём заметка
> Расшифровка типичных ошибок Hysteria 2 при настройке клиента и сервера и что с ними делать. Если ещё не подняли сервер/клиент — начните с [[Hysteria/config-server|серверного]] и [[Hysteria/config-client|клиентского]] конфигов. Обзор протокола — [[Hysteria/00-overview|тут]].

## TL;DR

- **timeout: no recent network activity** — клиент не достучался до сервера. Проверьте: запущен ли сервер, не режет ли UDP фаервол/провайдер, верны ли адрес и порт, совпадает ли пароль обфускации.
- **authentication error, HTTP status code: 404** — сервер отверг клиента. Почти всегда неверный пароль или подключение не к тому серверу.
- **certificate signed by unknown authority** — клиент не доверяет сертификату сервера. Для самоподписанного нужен `insecure` + `pinSHA256` на клиенте.
- **listen udp :443: bind: permission denied** — серверу не хватает прав на порт 443. Запуск от root или `setcap cap_net_bind_service`.
- Логи сервиса всегда под рукой: `journalctl --no-pager -e -u hysteria-server.service`.

## Ошибка: timeout (no recent network activity)

Полный текст: `failed to initialize client (connect error: timeout: no recent network activity)`.

Это значит, что клиент **не смог достучаться до сервера**. Частые причины:

- Сервер не запущен (проверьте `systemctl status hysteria-server.service`).
- Порт заблокирован фаерволом. Помимо системного фаервола, у многих хостеров есть **отдельный фаервол в панели управления VPS** — про него часто забывают.
- Сервер слушает другой адрес/порт, чем указан в клиенте.
- Сервер слушает на сети, недоступной клиенту.
- Домен не резолвится в правильный IP.
- **Неверные настройки обфускации.** Если включён [[Hysteria/obfs-port-hopping|obfs]], несовпадение пароля на клиенте и сервере даёт ровно такой таймаут — как будто сервера нет. Сверьте пароль обфускации на обеих сторонах.
- Слишком старое ядро Linux (известная проблема на CentOS 7). Обновите ядро или смените дистрибутив — см. [[Hysteria/install-server|требования к системе]].

> [!tip] Проверьте UDP отдельно
> Hysteria работает по UDP. Многие диагностические привычки (пинг, `telnet` на порт) проверяют ICMP/TCP и ничего не скажут про UDP. Если TCP до сервера идёт, а Hysteria — нет, вероятно, провайдер или фаервол режут именно UDP на этом порту. Обходные приёмы — [[Hysteria/obfs-port-hopping|обфускация и port hopping]]; если UDP зарезан полностью, поможет только TCP-решение вроде [[VLESS/dpi-tls-june-2026|VLESS+TLS]].

## Ошибка: authentication error (HTTP status code: 404)

Полный текст: `failed to initialize client (authentication error, HTTP status code: 404)`.

Клиент **дошёл до сервера, но был отвергнут**. Причины:

- Неверные учётные данные — пароль на клиенте не совпадает с `auth.password` на сервере.
- Подключение не к тому серверу.
- На сервере неправильно настроена секция `auth`.

Проверьте, что `auth` в [[Hysteria/config-client|клиенте]] в точности равен `auth.password` в [[Hysteria/config-server|сервере]] (а при `userpass`-аутентификации формат `username:password`).

## Ошибка: certificate signed by unknown authority

Полный текст: `connect error: CRYPTO_ERROR ... tls: failed to verify certificate: x509: certificate signed by unknown authority`.

Клиент **считает сертификат сервера невалидным**. Причины:

- Сервер использует самоподписанный сертификат, а на клиенте не добавлен доверенный CA и не включён `insecure`.
- В системном хранилище доверенных CA клиента нет центра, подписавшего сертификат.
- Вас атакуют «человеком посередине» (MITM).

Если сертификат самоподписанный — на клиенте укажите `insecure: true` вместе с `pinSHA256` (закрепление отпечатка защищает от подмены). Подробно — в [[Hysteria/config-client|конфиге клиента]], раздел про TLS. Лучший вариант вообще избежать этой ошибки — валидный сертификат через [[Hysteria/config-server|ACME]] на домен.

## Ошибка: bind permission denied на порт 443

Полный текст: `failed to load server config (invalid config: listen: listen udp :443: bind: permission denied)`.

У сервера **нет прав привязаться к порту 443** (порты ниже 1024 требуют привилегий). Два решения:

- Запускать сервер от root.
- Выдать бинарнику capability на привязку к привилегированным портам: `sudo setcap cap_net_bind_service=+ep ./hysteria` (подставьте реальное имя файла, например `hysteria-linux-amd64-avx`).

При установке [[Hysteria/install-server|официальным скриптом]] сервис обычно уже настроен на нужного пользователя — эта ошибка чаще возникает при ручном запуске бинарника.

## Где смотреть логи

Диагностику всегда начинайте с логов. Для systemd-сервиса:

```sh
systemctl status hysteria-server.service
journalctl --no-pager -e -u hysteria-server.service
```

Рабочий сервер пишет **«server up and running»**, рабочий клиент — **«connected to server»**. Отсутствие этих строк и есть первый признак, что что-то не так.

## 📚 См. также

- [[Hysteria/config-server|Конфиг сервера]] — правильная настройка `auth`, `tls`/`acme`, `listen`.
- [[Hysteria/config-client|Конфиг клиента]] — `insecure`/`pinSHA256`, адрес и пароль.
- [[Hysteria/obfs-port-hopping|Обфускация и port hopping]] — если UDP/QUIC режется провайдером.
- [[Hysteria/install-server|Установка сервера]] — требования к системе и правам.
- 🔗 [Troubleshooting — официальная документация](https://v2.hysteria.network/docs/advanced/Troubleshooting/)

---

> [!quote] 🤖 Эти статьи открыты — можно обучать на них ИИ
> При желании вы можете натренировать ИИ на наших статьях. Исходное форматирование и скачивание всего репозитория одним zip-архивом доступны на GitHub: [исходник этой заметки](https://github.com/youtubediscord/todo/blob/main/Hysteria/troubleshooting.md) · [весь репозиторий](https://github.com/youtubediscord/todo/tree/main).

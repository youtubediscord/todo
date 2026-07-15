---
date: 2026-07-11
tags:
  - hysteria
  - конфигурация
  - tls
  - acme
  - masquerade
aliases:
  - Конфиг сервера Hysteria 2
  - Hysteria server config
  - Hysteria masquerade
link: https://v2.hysteria.network/docs/getting-started/Server/
---

# 🦎 Hysteria 2 — конфиг сервера

> [!info] О чём заметка
> Как написать рабочий серверный `config.yaml` для Hysteria 2: получение TLS-сертификата (ACME или свой), пароль аутентификации, маскировка под сайт (`masquerade`) и запуск. Установка бинарника — в [[Hysteria/install-server|отдельной заметке]]. Полный справочник по всем полям — в [официальной документации Full Server Config](https://v2.hysteria.network/docs/advanced/Full-Server-Config/).

## TL;DR

- Конфиг — это YAML-файл (`/etc/hysteria/config.yaml` при установке скриптом). Минимум для рабочего сервера: сертификат + `auth` (пароль) + опционально `masquerade`.
- **С доменом** проще всего использовать `acme` — Hysteria сама получит и обновит бесплатный сертификат Let's Encrypt/ZeroSSL. **Без домена** — свой `tls` с самоподписанным сертификатом (тогда на клиенте нужен `insecure` + `pinSHA256`).
- **`masquerade`** заставляет сервер отвечать на HTTP-запросы как настоящий сайт (режим `proxy` «ворует» контент чужого сайта). Это ключ к обходу цензуры — без него сервер на любой HTTP-запрос отдаёт «404 Not Found», что выглядит подозрительно.
- Обязательно **замените пароль** на свой — это и есть единственная защита от чужих подключений.
- После правки конфига — `systemctl restart hysteria-server.service`.

## Где лежит конфиг и как запускается

При установке [[Hysteria/install-server|официальным скриптом]] конфиг — это `/etc/hysteria/config.yaml`, а сервис управляется через systemd (`systemctl restart hysteria-server.service`). При ручной установке вы сами кладёте `config.yaml` рядом с бинарником и запускаете `./hysteria server` (файл `config.yaml` подхватывается по умолчанию) или `./hysteria server -c whatever.yaml` для произвольного имени.

## Вариант A — сертификат через ACME (есть домен)

Это рекомендуемый путь: указываете домен и email, Hysteria сама получает валидный TLS-сертификат и автоматически его продлевает. Домен должен указывать на IP сервера (A/AAAA-запись).

```yaml
# listen: :443

acme:
  domains:
    - your.domain.net
  email: your@email.com

auth:
  type: password
  password: Se7RAuFZ8Lzg

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true
```

Что здесь что:

- **`listen`** — адрес и порт. По умолчанию `:443` (слушает и IPv4, и IPv6). Строку можно не указывать; раскомментируйте и поменяйте, только если нужен другой порт. `0.0.0.0:443` — только IPv4, `[::]:443` — только IPv6.
- **`acme.domains`** — ваш домен (можно несколько). **`acme.email`** — почта для регистрации в центре сертификации.
- **`auth`** — аутентификация клиентов. `type: password` — простой общий пароль. **Обязательно замените `password` на свой сильный пароль.** Он же указывается в клиенте.
- **`masquerade`** — маскировка (см. ниже).

## Вариант B — собственный сертификат

Если сертификат вы получаете сами (или он самоподписанный):

```yaml
# listen: :443

tls:
  cert: your_cert.crt
  key: your_key.key

auth:
  type: password
  password: Se7RAuFZ8Lzg

masquerade:
  type: proxy
  proxy:
    url: https://news.ycombinator.com/
    rewriteHost: true
```

`tls.cert` и `tls.key` — пути к файлам сертификата и ключа. Сертификаты перечитываются при каждом TLS-рукопожатии, поэтому обновлять файлы можно без перезапуска сервера. Если сертификат самоподписанный, на клиенте придётся указать `insecure: true` вместе с `pinSHA256` — подробнее в [[Hysteria/config-client|конфиге клиента]].

> [!tip] Нельзя одновременно `tls` и `acme`
> В конфиге может быть либо секция `acme`, либо секция `tls`, но не обе сразу. Выбираете один способ получения сертификата.

## Masquerade — маскировка под настоящий сайт

Одна из ключевых причин устойчивости Hysteria к цензуре — способность прикидываться обычным HTTP/3-трафиком. Мало того что пакеты выглядят как HTTP/3 для DPI — сервер ещё и **отвечает на HTTP-запросы как нормальный веб-сервер**. Но для правдоподобия сервер должен реально отдавать какой-то контент.

Проще всего — режим `proxy`: сервер работает обратным прокси и «ворует» контент чужого сайта. Поменяйте `url` на сайт, под который хотите мимикрировать. `rewriteHost: true` подменяет заголовок `Host` на адрес проксируемого сайта — это нужно, если целевой сервер по `Host` решает, какой сайт отдавать.

Другие режимы `masquerade`:

- **`file`** — раздавать статические файлы из каталога (`dir: /www/masq`).
- **`string`** — всегда возвращать заданную строку (`content: ...`, опционально свои `headers` и `statusCode`).
- **`proxy`** — обратный прокси на чужой сайт (пример выше).

> [!warning] Без masquerade сервер выдаёт «404»
> Если убрать секцию `masquerade` целиком, Hysteria на любой HTTP-запрос будет отвечать «404 Not Found». Само по себе это не ломает прокси, но для стороннего наблюдателя (или цензора, который решит постучаться на ваш домен браузером) сервер, отдающий голый 404 на всё, выглядит подозрительнее, чем нормальный сайт. Если обход цензуры — цель, оставляйте `masquerade`.

> [!note] Проверить маскировку можно браузером
> Чтобы убедиться, что маскировка работает, запустите Chrome с флагом форс-QUIC: `chrome --origin-to-force-quic-on=your.site.com:443` (перед этим полностью закройте все процессы Chrome, иначе флаг не подействует), затем откройте `https://your.site.com` — должна отобразиться замаскированная страница.

## Запуск и проверка

Если ставили скриптом — просто перезапустите сервис после правки конфига:

```sh
systemctl restart hysteria-server.service
journalctl --no-pager -e -u hysteria-server.service
```

Если запускаете бинарник вручную:

```bash
sudo setcap cap_net_bind_service=+ep ./hysteria   # разрешить порт 443 без root
./hysteria server                                 # config.yaml подхватится сам
```

Признак успеха — в логах строка **«server up and running»** без ошибок. Дальше настройте [[Hysteria/config-client|клиент]].

> [!tip] Полезные необязательные поля
> В [полном справочнике сервера](https://v2.hysteria.network/docs/advanced/Full-Server-Config/) есть много опций сверх минимума: несколько пользователей (`auth.type: userpass`), HTTP-аутентификация через свой бэкенд, лимиты скорости (`bandwidth` — см. [[Hysteria/bandwidth-brutal|Скорость и Brutal]]), [[Hysteria/acl-outbounds|ACL и outbound'ы]] для маршрутизации разного трафика по-разному, [[Hysteria/traffic-stats-api|Traffic Stats API]] для мониторинга, обфускация (см. [[Hysteria/obfs-port-hopping|Обфускация и port hopping]]). Если у сервера нет белого IP — его можно поднять за NAT через [[Hysteria/realms-nat|Realms]].

## 📚 См. также

- [[Hysteria/install-server|Установка сервера]] — предыдущий шаг: как получить бинарник и сервис.
- [[Hysteria/config-client|Конфиг клиента]] — следующий шаг: настройка устройства.
- [[Hysteria/bandwidth-brutal|Скорость и Brutal]] — про поле `bandwidth` и контроль перегрузки.
- [[Hysteria/obfs-port-hopping|Обфускация и port hopping]] — если QUIC режется провайдером.
- [[Hysteria/acl-outbounds|ACL и маршрутизация трафика]] — блокировка адресов и разведение по outbound'ам.
- [[Hysteria/traffic-stats-api|Traffic Stats API]] — мониторинг и управление пользователями.
- [[Hysteria/realms-nat|Realms: сервер за NAT]] — если нет белого IP.
- 🔗 [Server tutorial](https://v2.hysteria.network/docs/getting-started/Server/) · [Full Server Config](https://v2.hysteria.network/docs/advanced/Full-Server-Config/)

---

> [!quote] 🤖 Эти статьи открыты — можно обучать на них ИИ
> При желании вы можете натренировать ИИ на наших статьях. Исходное форматирование и скачивание всего репозитория одним zip-архивом доступны на GitHub: [исходник этой заметки](https://github.com/youtubediscord/todo/blob/main/Hysteria/config-server.md) · [весь репозиторий](https://github.com/youtubediscord/todo/tree/main).

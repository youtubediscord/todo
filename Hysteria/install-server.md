---
date: 2026-07-11
tags:
  - hysteria
  - установка
  - systemd
  - vps
aliases:
  - Установка сервера Hysteria 2
  - Hysteria install script
  - get.hy2.sh
link: https://v2.hysteria.network/docs/getting-started/Installation/
---

# 🦎 Hysteria 2 — установка сервера

> [!info] О чём заметка
> Практический гайд по установке серверной части Hysteria 2 на Linux-VPS: официальный bash-скрипт с systemd-сервисом, ручная установка бинарника и Docker. Обзор протокола и модели «клиент-сервер» — в [[Hysteria/00-overview|обзорной заметке]]. После установки нужно написать конфиг — см. [[Hysteria/config-server|Конфиг сервера]].

## TL;DR

- Проще всего — официальный скрипт: `bash <(curl -fsSL https://get.hy2.sh/)`. Он ставит бинарник и заводит systemd-сервис `hysteria-server.service`.
- Скрипт **только устанавливает** и создаёт пример конфига. Рабочий конфиг с доменом, паролем и сертификатом нужно [[Hysteria/config-server|написать вручную]] в `/etc/hysteria/config.yaml`, иначе сервис не запустится.
- Конфиг лежит в `/etc/hysteria/config.yaml`, запуск/перезапуск — через `systemctl`, логи — через `journalctl`.
- Нужен дистрибутив с systemd: Debian 11+, Ubuntu 22.04 LTS+, Rocky/CentOS Stream 8+, Fedora 37+. **CentOS 7 и busybox-системы (Alpine, OpenWrt) не поддерживаются.**
- Один и тот же бинарник `hysteria` — это и сервер, и клиент; режим выбирается аргументом (`hysteria server` / `hysteria client`).

## Требования

- **VPS с публичным IP** (IPv4 или IPv6 — оба подходят). Нет белого IP (дом, CGNAT, мобильный модем)? Сервер всё равно можно поднять — см. [[Hysteria/realms-nat|Realms: сервер за NAT]].
- **Домен, указывающий на IP сервера** (подойдёт и поддомен). Домен нужен, чтобы Hysteria автоматически получила TLS-сертификат через ACME (Let's Encrypt / ZeroSSL). Без домена придётся использовать самоподписанный сертификат — см. [[Hysteria/config-client|клиентский конфиг]], раздел про `insecure`/`pinSHA256`.
- Для скрипта установки: система на **systemd** (команда `systemctl`) и установленные `bash`, `grep`, `curl`, GNU Coreutils (не busybox-версии).

> [!tip] Какой дистрибутив выбрать новичку
> Для нового VPS берите стабильную версию мейнстрим-дистрибутива не старше 2 лет. Рекомендованные официальной документацией: **Debian 11+**, **Ubuntu 22.04 LTS+**, Rocky Linux 8+, CentOS Stream 8+, Fedora 37+. Явно **избегайте CentOS 7** (старое ядро ломает QUIC-соединения). Не поддерживаются busybox-системы: OpenWrt, Alpine Linux, NixOS.

## Способ 1 — официальный скрипт установки (рекомендуется)

Официальный bash-скрипт скачивает свежий бинарник, кладёт его в систему и настраивает systemd-сервис. Он аналогичен пакетному менеджеру: устанавливает и обновляет, но **сам сервис не настраивает до рабочего состояния** — генерирует только пример конфига.

### Установка или обновление

Установить (или обновить до последней версии):

```sh
bash <(curl -fsSL https://get.hy2.sh/)
```

Установить конкретную версию (например, `v2.9.3`):

```sh
bash <(curl -fsSL https://get.hy2.sh/) --version v2.9.3
```

### Удаление

```sh
bash <(curl -fsSL https://get.hy2.sh/) --remove
```

### Полезные варианты запуска скрипта

- **Установка из локального файла** — если VPS не может достучаться до GitHub Releases, скачайте бинарник вручную и передайте путь: `bash <(curl -fsSL https://get.hy2.sh/) --local /path/to/hysteria-linux-amd64`.
- **Указать архитектуру** (в основном для AVX-сборки, она быстрее на поддерживающих AVX процессорах): `ARCHITECTURE=amd64-avx bash <(curl -fsSL https://get.hy2.sh/)`.
- **Запуск от root** — если не хотите возиться с правами (например, при внешней генерации сертификатов): `HYSTERIA_USER=root bash <(curl -fsSL https://get.hy2.sh/)`. Вернуть обычного пользователя: `HYSTERIA_USER=hysteria bash <(curl -fsSL https://get.hy2.sh/)`.

> [!warning] Скрипт не «настроит всё сам»
> Официальный `get.hy2.sh` — это установщик, а не «мастер настройки под ключ». Он создаёт пример конфига, но не пропишет за вас домен, пароль и сертификат. Рабочий конфиг нужно написать самому (см. [[Hysteria/config-server|Конфиг сервера]]). Существуют сторонние «скрипты Hysteria 2», которые ставят и настраивают всё разом, но это чужой неофициальный код — запускать его от root на своём сервере стоит только осознанно и из доверенного источника.

## Управление сервисом (systemd)

После установки скриптом сервис называется `hysteria-server.service`.

Отредактировать конфиг:

```sh
nano /etc/hysteria/config.yaml
```

Включить автозапуск и сразу стартовать:

```sh
systemctl enable --now hysteria-server.service
```

Перезапустить (обычно после правки конфига):

```sh
systemctl restart hysteria-server.service
```

Проверить статус:

```sh
systemctl status hysteria-server.service
```

Посмотреть логи сервера:

```sh
journalctl --no-pager -e -u hysteria-server.service
```

> [!tip] Как понять, что сервер поднялся
> В логах должно появиться сообщение **«server up and running»** без ошибок. Если вместо этого видите ошибки про `permission denied` на порт 443 или про сертификат — загляните в [[Hysteria/troubleshooting|разбор проблем]].

## Способ 2 — ручная установка бинарника

Если systemd-скрипт не подходит (например, нестандартная система), можно скачать исполняемый файл напрямую. Ссылка вида `https://download.hysteria.network/app/latest/[имя файла]` всегда ведёт на последнюю версию — удобно для скриптов и автоматизации.

Имена файлов для Linux (выберите под свою архитектуру):

| Файл | Архитектура | Примечание |
| --- | --- | --- |
| `hysteria-linux-amd64` | x86-64 | обычный |
| `hysteria-linux-amd64-avx` | x86-64 | требует поддержки AVX (быстрее) |
| `hysteria-linux-arm64` | ARM64 | |
| `hysteria-linux-arm` | ARMv7 | |
| `hysteria-linux-386` | x86 | |

Есть также сборки под Windows, macOS (включая ARM/M1), FreeBSD и Android (последние — ELF-бинарники под NDK, а не APK). Полный список — в [официальной документации](https://v2.hysteria.network/docs/getting-started/Installation/).

Пример: скачать, сделать исполняемым и запустить как сервер с конфигом `config.yaml` в текущей папке:

```bash
curl -fsSL -o hysteria https://download.hysteria.network/app/latest/hysteria-linux-amd64-avx
chmod +x hysteria
./hysteria server -c config.yaml
```

> [!warning] Порт 443 требует привилегий
> Hysteria по умолчанию слушает 443 порт, а порты ниже 1024 недоступны обычному пользователю. Либо запускайте от root, либо выдайте бинарнику право привязываться к привилегированным портам: `sudo setcap cap_net_bind_service=+ep ./hysteria`. Подробнее об этой ошибке — в [[Hysteria/troubleshooting|разборе проблем]].

## Способ 3 — Docker

Официальный образ — [tobyxdd/hysteria](https://hub.docker.com/r/tobyxdd/hysteria). Пример `docker-compose.yaml`:

```yaml
version: "3.9"
services:
  hysteria:
    image: tobyxdd/hysteria
    container_name: hysteria
    restart: always
    network_mode: "host"
    cap_add:
      - NET_ADMIN
    volumes:
      - acme:/acme
      - ./hysteria.yaml:/etc/hysteria.yaml
    command: ["server", "-c", "/etc/hysteria.yaml"]
volumes:
  acme:
```

Capability `NET_ADMIN` нужна только если включён [[Hysteria/obfs-port-hopping|port hopping]] (серверу надо править правила фаервола). Для обычной работы её можно убрать.

## Что дальше

После установки бинарник есть, но сервис ещё не работает — нужен конфиг. Переходите к [[Hysteria/config-server|написанию серверного конфига]]: домен, ACME-сертификат, пароль аутентификации и маскировка под сайт.

## 📚 См. также

- [[Hysteria/00-overview|Hysteria 2 — обзор]] — что это за протокол и кому подходит.
- [[Hysteria/config-server|Конфиг сервера]] — следующий обязательный шаг после установки.
- [[Hysteria/troubleshooting|Решение проблем]] — если сервис не стартует.
- 🔗 [Installation — официальная документация](https://v2.hysteria.network/docs/getting-started/Installation/)
- 🔗 [Server Installation Script — детали скрипта](https://v2.hysteria.network/docs/getting-started/Server-Installation-Script/)

---

> [!quote] 🤖 Эти статьи открыты — можно обучать на них ИИ
> При желании вы можете натренировать ИИ на наших статьях. Исходное форматирование и скачивание всего репозитория одним zip-архивом доступны на GitHub: [исходник этой заметки](https://github.com/youtubediscord/todo/blob/main/Hysteria/install-server.md) · [весь репозиторий](https://github.com/youtubediscord/todo/tree/main).

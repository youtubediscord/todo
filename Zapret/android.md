---
date:
tags:
link:
aliases:
img:
---
![[Pasted image 20260131162140.png|900]]
# 🤖 Дурилки трафика (DPI) для Android
## Zapret / [[Zapret2]]

> [!WARNING] ВАЖНО!
> Для того чтобы поставить zapret на телефон андроид требуются рут права (так как zapret работает напрямую с инструментом linux — iptables)!
> А также установленное приложение [Magisk](https://github.com/topjohnwu/Magisk/releases). (для работы с IPTABLES)

### [Zapret 2 (Magisk модуль)](https://github.com/youtubediscord/magisk-zapret2)
Самый передовой модуль для обхода блокировок YouTube, Discord и других сайтов на Android.

![[Pasted image 20260131162343.png|800]]

### Способ 1. [Magisk модуль с zapret ImMALWARE ](https://github.com/ImMALWARE/zapret-magisk)
1. Скачайте модуль тут: https://github.com/ImMALWARE/zapret-magisk/releases/latest/download/zapret_module.zip
2. Установите модуль, перезагрузитесь, как обычно. zapret будет запущен автоматически.

### Способ 2. [zapret Pocket sevcator](https://github.com/sevcator/zapret-magisk)
1. Скачайте модуль: https://github.com/sevcator/zapret-pocket/releases/download/21.0/zapret-pocket.zip
2. Установите также как и в способе 1

## Способ 3. [zaprett](https://mailru.pro)

Вики по установке доступна здесь: https://mailru.pro/guide/install/app-module
Исходный код здесь: https://github.com/CherretGit/zaprett-app

[📣 Официальный Telegram-канал модуля](https://t.me/zaprett_module)

Представляет собой портированную версию [zapret](https://github.com/bol-van/zapret/) от [bol-van](https://github.com/bol-van/) для Android устройств.

Требования:
* Magisk 24.1+
* Прямые руки
* Termux или другой эмулятор терминала **И/ИЛИ**  [ремейк приложения zaprett от cherret](https://github.com/CherretGit/zaprett-app) ("оригинал" устарел и не обновляется, вместо этого мы вдвоём занимаемся версией на Kotlin!)

На данный момент модуль умеет:
+ Включать, выключать и перезапускать nfqws
+ Работать с листами, айписетами, стратегиями
+ Предлагать обновления через Magisk/KSU/KSU Next/APatch

Какую версию модуля выбрать?

В актуальных релизах есть 2 версии модуля, а именно:
- zaprett.zip
- zaprett-hosts.zip (с /etc/hosts)

Что такое /etc/hosts?
Говоря грубо, это файл, который влияет на работу нейросетей и других недоступных сервисов, перенаправляя ваш траффик на сторонние сервера.

Если вы используете модули, которые подменяют этот файл (например, всевозможные блокировщики рекламы и разблокировщики нейросетей), выбирайте версию <big>**без hosts**</big>, иначе модули будут конфликтовать друг с другом.

⚠️ Сервера, используемые в качестве прокси и указанные в файле hosts нам неподконтрольны, мы не несём за них отвественность, используйте с осторожностью

-----

Zaprett: https://github.com/egor-white/zaprett
Zaprett GUI: https://github.com/CherretGit/zaprett-app
Специальная тема: https://4pda.to/forum/index.php?showtopic=1108704

Для перенаправления hosts (ChatGPT, Notion и т.д.): https://github.com/AdAway/AdAway

## ByeByeDPI (без Root)
![[ByeByeDPI - Что это такое]]


## Перенаправление hosts
DNS от https://www.comss.ru/page.php?id=7315 или https://xbox-dns.ru или dns.malw.link

## Android TV
https://www.youtube.com/watch?v=q5fVssg6Wjw

### ☄️ Всё остальное тут: https://t.me/androidawesome

запрет для обхода блокировок discord и youtube, дискорда и ютуба, запретов нет, обход блокировки дискорд и ютуб
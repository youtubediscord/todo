---
height: 2500
---
# Как скачать [[Zapret2]] GUI

[[home|На главную]]

![[Как пользоваться Zapret#Словарь терминов (глоссарий)]]

[[Типичные ошибки#Ошибки при установке|Здесь]] можете посмотреть типичные ошибки при установке.

# Zapret GUI (windows 10+)

> [!DANGER]
> Zapret GUI доступен только для Windows 10 1809+ и выше. Для Windows 7, Windows 8 и Windows 10 1803 (и ниже) скачайте его [[🐳 Win 7 и 8|здесь]].
 

Всего существует 4 основных способа скачать Zapret GUI:

## Способ 1. Самый простой

Перейти по ссылке: https://t.me/bypassblock/399

И скачать `ZapretSetup.exe` после чего установить:

![[Pasted image 20250914200533.png]]

![[Pasted image 20250914200818.png]]

![[Pasted image 20250914200828.png]]

В итоге Zapret появится в меню пуск:

![[Pasted image 20250914200550.png]]

## Способ 2. Через Telegram канал

Перейти по ссылке: https://t.me/zapretnetdiscordyoutube

Скачать любую `dev` версию (обычно выходит часто) либо, ввести в поиске этого канала `🔄 Канал обновлений: STABLE`

После чего скачайте `exe` файл и проделайте ту же установку что и в способе 1:

![[Pasted image 20250914200725.png]]

## Способ 3. Через Telegram бота

Перейти по ссылке: https://t.me/zapretbypass_bot

Набрать команду `/get_stable`. В результате чего бот выдаст файл – далее установка как в способе 1.

![[Pasted image 20250914200938.png]]

## Способ 4. Через Github

Пройдите по ссылке: https://github.com/youtubediscord/zapret/releases/latest/download/ZapretSetup.exe

Файл с качается автоматически. Установка как в способе 1.

## Способ 5. Собрать Zapret самостоятельно

Пройдите по ссылке: https://github.com/youtubediscord/zapret/blob/main/docs/build.md

----

# Zapret (android)
Для того чтобы поставить zapret на телефон андроид требуются рут права (так как zapret работает напрямую с инструментом linux — iptables)!
А также установленное приложение [Magisk](https://github.com/topjohnwu/Magisk/releases).

## Способ 1. [Magisk модуль с zapret ImMALWARE](https://github.com/ImMALWARE/zapret-magisk)
1. Скачайте модуль тут: https://github.com/ImMALWARE/zapret-magisk/releases/latest/download/zapret_module.zip
2. Установите модуль, перезагрузитесь, как обычно. zapret будет запущен автоматически.

## Способ 2. [zapret Pocket sevcator](https://github.com/sevcator/zapret-pocket)
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
# Zapret (linux)

Всего существует несколько основных способов (в данном документе представлено 4):

## Способ 1. <a target="_blank" href="https://github.com/ImMALWARE/zapret-linux-easy">Однокнопочный zapret для Linux</a>

1. Скачайте и распакуйте [архив](https://github.com/ImMALWARE/zapret-linux-easy/archive/refs/heads/main.zip) (либо по команде `git clone https://github.com/ImMALWARE/zapret-linux-easy && cd zapret-linux-easy`)
2. Убедитесь, что у вас установлены пакеты curl, iptables и ipset (для FWTYPE=iptables) или curl и nftables (для FWTYPE=nftables)!
	1. Если нет — установите. Если вы не знаете как, спросите у ChatGPT!
3. Откройте терминал в папке,- куда архив был распакован
4. Выполните `./install.sh`

## Способ 2. <a target="_blank" href="https://github.com/Sergeydigl3/zapret-discord-youtube-linux">Zapret Sergeydigl3</a>

Это адаптер для запуска популярных конфигураций обхода замедления YouTube на базе Zapret Discord Youtube Flowseal.

Скрипт создан за пару вечеров с целью сделать его Plug-And-Play.


Как запустить

1. **Клонирование репозитория и запуск основного скрипта:**

```bash
git clone https://github.com/Sergeydigl3/zapret-discord-youtube-linux.git
cd zapret-discord-youtube-linux
sudo bash main_script.sh
```

   Скрипт:
   - Спросит, нужно ли обновление (если папка zapret-latest уже существует).
   - Предложит выбрать стратегию из bat-файлов (например, `general.bat`, `general_mgts2.bat`, `general_alt5.bat`).  
     (При этом bat-файлы автоматически переименовываются через `rename_bat.sh`.)
   - Попросит выбрать сетевой интерфейс.

2. **Сохранение параметров:** Ответы можно сохранить в файле `conf.env` и потом запускать скрипт в неинтерактивном режиме:
   
```bash
sudo bash main_script.sh -nointeractive
```
   
   Для отладки парсинга используйте флаг `-debug`.

   Пример содержимого файла `conf.env`:
   
   ```bash
   strategy=general.bat
   auto_update=false
   interface=enp0s3
   ```
   
Если требуется автообновление, установите auto_update=true.

3. **Как посмотреть список интерфейсов:**

   ```bash
   ls /sys/class/net
   ```

Важно
- Скрипт работает только с **nftables**.
- При остановке скрипта все добавленные правила фаервола очищаются, а фоновые процессы `nfqws` останавливаются.
- Если у вас настроены кастомные правила в nftables, сделайте их резервное копирование — скрипт может удалить их при запуске.

## Способ 3. <a target="_blank" href="https://github.com/Snowy-Fluffy/zapret.installer">Snowy-Fluffy/zapret.installer</a>

Облегчает установку zapret для новичков и тех, кто не хочет разбираться в его работе.  
Устанавливает [zapret из оффициального репозитория](https://github.com/bol-van/zapret), CLI панель управления и [репозиторий со стратегиями и списками доменов](https://github.com/Snowy-Fluffy/zapret.cfgs).

🔽 Установка  

Запуск скрипта установки (необходимо наличие *curl* в системе):  
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Snowy-Fluffy/zapret.installer/refs/heads/main/installer.sh)"
```

Вызов панели управления:  
```bash
zapret
```

## Способ 4. <a target="_blank" href="https://t.me/linux_hi/57">Линукс - привет!</a>

Выполните:
```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Snowy-Fluffy/zapret.installer/refs/heads/main/installer.sh)"
```
После установки запрета моей командой можно запускать меню управления запретом с помощью команды zapret в терминале


## Способ 5. <a target="_blank" href="https://github.com/kartavkun/zapret-discord-youtube">🚀 Zapret</a>

**Автоматическая установка одним командой:**

```bash
bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh)
```

> [!TIP]
> Если команда выше не работает, попробуйте альтернативный вариант:
> ```bash
> bash <(curl -s https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/main/setup.sh | psub)
> ```

**Что делает скрипт установки:**
- ✅ Автоматически определяет ваш дистрибутив Linux
- 📦 Устанавливает необходимые зависимости (wget, git)
- ⬇️ Скачивает последнюю версию zapret с официального репозитория
- 🛠️ Настраивает систему для работы zapret
- 🎯 Предлагает интерактивный выбор конфигурации

----

![[ZapretTeam]]

# Установка Zapret на linux
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

## Способ 3. <a target="_blank" href="https://t.me/linux_hi/57">Линукс - привет!</a> | <a target="_blank" href="https://github.com/Snowy-Fluffy/zapret.installer">Snowy-Fluffy/zapret.installer</a>

Облегчает установку zapret для новичков и тех, кто не хочет разбираться в его работе.  
Устанавливает [zapret из официального репозитория](https://github.com/bol-van/zapret), CLI панель управления и [репозиторий со стратегиями и списками доменов](https://github.com/Snowy-Fluffy/zapret.cfgs).

🔽 Установка  

Запуск скрипта установки (необходимо наличие *curl* в системе):  
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Snowy-Fluffy/zapret.installer/refs/heads/main/installer.sh)"
```
После установки данной командой можно легко запускать меню управления запретом в терминале с помощью команды:  
```bash
zapret
```

Телеграм канал: https://t.me/linux_hi/


## Способ 4. <a target="_blank" href="https://github.com/kartavkun/zapret-discord-youtube">🚀 Zapret</a>

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

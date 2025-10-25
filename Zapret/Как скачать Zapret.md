---
height: 2200
---

![[Как пользоваться Zapret#Словарь терминов (глоссарий)]]

<h1 style="font-size: 40px; padding: 15px; border: 1px dashed #800072;">Zapret GUI (windows 10+)</h1> 
> [!danger] ВАЖНО!
> Zapret GUI доступен только для Windows 10 1809+ и выше. Для Windows 7, Windows 8 и Windows 10 1803 (и ниже) пройдите по ссылке: https://t.me/bypassblock/666
 

Всего существует 4 основных способа скачать Zapret GUI:

<h1 style="font-size: 40px;">Способ 1. Самый простой</h1>

Перейти по ссылке: https://t.me/bypassblock/399

И скачать `ZapretSetup.exe` после чего установить:

![[Pasted image 20250914200533.png]]

![[Pasted image 20250914200818.png]]

![[Pasted image 20250914200828.png]]

В итоге Zapret появится в меню пуск:

![[Pasted image 20250914200550.png]]

<h1 style="font-size: 40px;">Способ 2. Через Telegram канал</h1>

Перейти по ссылке: https://t.me/zapretnetdiscordyoutube

Скачать любую `dev` версию (обычно выходит часто) либо, ввести в поиске этого канала `🔄 Канал обновлений: STABLE`

После чего скачайте `exe` файл и проделайте ту же установку что и в способе 1:

![[Pasted image 20250914200725.png]]

<h1 style="font-size: 40px;">Способ 3. Через Telegram бота</h1>

Перейти по ссылке: https://t.me/zapretbypass_bot

Набрать команду `/get_stable`. В результате чего бот выдаст файл – далее установка как в способе 1.

![[Pasted image 20250914200938.png]]

<h1 style="font-size: 40px;">Способ 4. Через Github</h1>

Пройдите по ссылке: https://github.com/youtubediscord/zapret/releases/latest/download/ZapretSetup.exe

Файл с качается автоматически. Установка как в способе 1.

----

<h1 style="font-size: 40px; padding: 15px; border: 1px dashed #800072;">Zapret (linux)</h1>
Всего существует несколько основных способов (в данном документе представлено 4):

<h1 style="font-size: 40px;">Способ 1. <a target="_blank" href="https://github.com/ImMALWARE/zapret-linux-easy">Однокнопочный zapret для Linux</a></h1>

1. Скачайте и распакуйте [архив](https://github.com/ImMALWARE/zapret-linux-easy/archive/refs/heads/main.zip) (либо по команде `git clone https://github.com/ImMALWARE/zapret-linux-easy && cd zapret-linux-easy`)
2. Убедитесь, что у вас установлены пакеты curl, iptables и ipset (для FWTYPE=iptables) или curl и nftables (для FWTYPE=nftables)!
	1. Если нет — установите. Если вы не знаете как, спросите у ChatGPT!
3. Откройте терминал в папке,- куда архив был распакован
4. Выполните `./install.sh`

<h1 style="font-size: 40px;">Способ 2. <a target="_blank" href="https://github.com/Sergeydigl3/zapret-discord-youtube-linux">Zapret Sergeydigl3</a></h1>

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

<h1 style="font-size: 40px;">Способ 3. <a target="_blank" href="https://github.com/Snowy-Fluffy/zapret.installer">Snowy-Fluffy/zapret.installer</a></h1>

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

<h1 style="font-size: 40px;">Способ 4. <a target="_blank" href="https://t.me/linux_hi/57">Линукс - привет!</a></h1>

Выполните:
```
sh -c "$(curl -fsSL https://raw.githubusercontent.com/Snowy-Fluffy/zapret.installer/refs/heads/main/installer.sh)"
```
После установки запрета моей командой можно запускать меню управления запретом с помощью команды zapret в терминале

----

![[ZapretTeam]]

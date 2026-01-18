
[[Zapret]] [[Telegram]] [[VPS]]

```
apt install python3.13-venv
python3 -m venv venv
source venv/bin/activate
pip install paramiko pytz aiogram aiohttp aiohttp_cors yoomoney requests python-dotenv timezones wireguard certbot schedule filelock playwright timedelta qrcode qrcode[pil]
nano /etc/systemd/system/vpnbot.service
```

```
[Unit]
Description=VPN Telegram Bot
After=network.target zapret-api.service
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/vpnbot
ExecStart=/root/vpnbot/venv/bin/python /root/vpnbot/bot.py

# Перезапуск при падении
Restart=always
RestartSec=10

# Лимиты (отдельные от API!)
LimitNOFILE=32768
LimitNPROC=2048
TasksMax=2048

# Логирование
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vpnbot

# Безопасность
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
```

```
sudo systemctl daemon-reload
sudo systemctl enable vpnbot
sudo systemctl restart vpnbot
journalctl -u vpnbot -f
```

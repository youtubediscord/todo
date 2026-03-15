# Интеграция MTProxy с Telegram-ботом

## Архитектура

Текущий стек бота: VLESS через 3x-ui + SSH управление MTProxy через `secrets.conf`.

**Целевой стек:** telemt REST API вместо SSH+secrets.conf.

```
Текущий:
  Бот → SSH → echo secret >> secrets.conf → systemctl restart mtproxy

Целевой:
  Бот → HTTP POST /v1/users → telemt применяет на лету (без рестарта)
```

## Миграция mtproto_service.py

### Что заменяется

| Текущий метод | Новый метод |
|---|---|
| `_ssh_connect()` + paramiko | `aiohttp.ClientSession()` |
| `echo secret >> secrets.conf` | `POST /v1/users` |
| `grep -v secret > tmp && mv` | `DELETE /v1/users/{name}` |
| `sed -i 's/^secret /#&/'` | `PATCH /v1/users/{name}` |
| `systemctl restart mtproxy` | Не нужен — API применяет на лету |
| `_build_proxy_link()` | API возвращает готовые `tg://proxy` ссылки |

### Пример нового MTProtoService

```python
import aiohttp
import logging
from typing import Dict, Optional, Tuple

logger = logging.getLogger(__name__)


class TelemetService:
    """Управление MTProto через telemt REST API."""

    def __init__(self, base_url: str = "http://127.0.0.1:9091",
                 auth_token: str = ""):
        self.base_url = base_url.rstrip("/")
        self.headers = {"Content-Type": "application/json"}
        if auth_token:
            self.headers["Authorization"] = auth_token

    async def _request(self, method: str, path: str, **kwargs) -> dict:
        async with aiohttp.ClientSession(headers=self.headers) as session:
            async with session.request(method, f"{self.base_url}{path}", **kwargs) as resp:
                data = await resp.json()
                if not data.get("ok"):
                    raise RuntimeError(f"telemt API error: {data}")
                return data

    async def create_user(
        self,
        user_id: int,
        expiration: Optional[str] = None,
        max_conns: Optional[int] = None,
        max_ips: Optional[int] = None,
    ) -> Tuple[str, dict]:
        """Создать пользователя, вернуть (tg://proxy ссылку, meta)."""
        body = {"username": f"user_{user_id}"}
        if expiration:
            body["expiration_rfc3339"] = expiration
        if max_conns:
            body["max_tcp_conns"] = max_conns
        if max_ips:
            body["max_unique_ips"] = max_ips

        data = await self._request("POST", "/v1/users", json=body)
        user_info = data["data"]["user"]
        # API возвращает готовые ссылки
        links = user_info.get("links", {})
        tls_links = links.get("tls", [])
        link = tls_links[0] if tls_links else ""
        return link, {
            "username": user_info["username"],
            "secret": data["data"].get("secret", ""),
            "links": links,
        }

    async def delete_user(self, user_id: int) -> bool:
        """Удалить пользователя."""
        try:
            await self._request("DELETE", f"/v1/users/user_{user_id}")
            return True
        except Exception as e:
            logger.warning("Failed to delete user_%s: %s", user_id, e)
            return False

    async def update_user(self, user_id: int, **kwargs) -> dict:
        """Обновить параметры пользователя."""
        data = await self._request(
            "PATCH", f"/v1/users/user_{user_id}", json=kwargs
        )
        return data["data"]

    async def get_users(self) -> list:
        """Список всех пользователей."""
        data = await self._request("GET", "/v1/users")
        return data["data"]

    async def get_user(self, user_id: int) -> Optional[dict]:
        """Получить информацию о пользователе."""
        try:
            data = await self._request("GET", f"/v1/users/user_{user_id}")
            return data["data"]
        except Exception:
            return None

    async def health(self) -> dict:
        """Проверить здоровье сервиса."""
        return await self._request("GET", "/v1/health")
```

### Интеграция с подписками

```python
# При покупке подписки
from datetime import datetime, timedelta

async def on_subscription_purchased(user_id: int, days: int):
    expiry = (datetime.utcnow() + timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    link, meta = await telemt.create_user(
        user_id=user_id,
        expiration=expiry,
        max_conns=10,
        max_ips=3,
    )
    # Отправить ссылку пользователю
    await bot.send_message(user_id, f"Ваш MTProxy: {link}")

# При истечении подписки (background task)
async def on_subscription_expired(user_id: int):
    await telemt.delete_user(user_id)
```

### Что остаётся от текущего кода

- `bot_db/mtproto_manager.py` — хранение метаданных в SQLite (юзер ↔ сервер ↔ секрет)
- `config/mtproto_servers.py` — конфигурация серверов (заменить SSH-поля на API URL)
- `handlers/mtproto_handlers.py` — Telegram хендлеры (логика не меняется)
- `background_tasks/mtproto_cleanup.py` — очистка истёкших подписок

### Что удаляется

- SSH-подключение через paramiko
- Управление `secrets.conf`
- `systemctl restart mtproxy`
- `run_mtproxy.sh` wrapper
- `install_mtproxy.sh`
- Патч `pid_max` и лимита секретов

## Гибридная схема: telemt + mtg

```
Сервер 1 (основной):
  telemt :443 — per-user ключи, API управление
  Бот создаёт/удаляет юзеров через REST API

Сервер 2 (stealth fallback):
  mtg :443 — один общий секрет, Doppelganger
  Бот выдаёт ссылку активным подписчикам
  Ротация секрета раз в сутки
```

## Конфигурация серверов (mtproto_servers.json)

```json
{
  "telemt-ru-1": {
    "name": "Россия 1",
    "enabled": true,
    "type": "telemt",
    "api_url": "http://10.0.0.1:9091",
    "api_auth": "my-secret-token",
    "domain": "10.0.0.1",
    "mtproto_port": 443,
    "mtproto_fake_tls_domain": "petrovich.ru",
    "location": "Moscow",
    "allowed_levels": ["free", "premium"]
  }
}
```

## Мониторинг

```python
async def check_telemt_health(server_id: str):
    """Проверка здоровья telemt сервера."""
    cfg = get_server_config(server_id)
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{cfg['api_url']}/v1/health") as resp:
            return resp.status == 200

async def get_online_count(server_id: str) -> int:
    """Количество активных соединений."""
    cfg = get_server_config(server_id)
    async with aiohttp.ClientSession() as session:
        async with session.get(f"{cfg['api_url']}/v1/stats/summary") as resp:
            data = await resp.json()
            return data.get("data", {}).get("current_connections", 0)
```

## Workaround для memory leak (#390)

telemt имеет утечку памяти в draining writers. Периодический рестарт:

```python
# В background_tasks
async def restart_telemt_if_needed():
    """Рестарт telemt если RSS > порога."""
    # Проверка через Docker API или SSH
    # docker restart telemt
    pass
```

Или через systemd timer:
```bash
# /etc/systemd/system/telemt-restart.timer
[Timer]
OnCalendar=daily
# Рестарт раз в сутки как workaround для memory leak
```

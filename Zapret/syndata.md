---
tags:
link:
aliases:
img:
---

# Полная документация функции syndata
`syndata` — Lua функция из zapret-antidpi.lua, которая добавляет payload данные в TCP SYN пакет и отправляет его вместо оригинала. Работает на "нулевой фазе" — до установления TCP соединения.

Расположение: `zapret-antidpi.lua:357-380`

Формат вызова:
```bash
--lua-desync=syndata[:param1=val1[:param2=val2]...]
```

---
Специфические параметры syndata

| Параметр       | Описание                                      | По умолчанию    |
|----------------|-----------------------------------------------|-----------------|
| blob=<name>    | Payload данные для SYN пакета                 | 16 нулевых байт |
| tls_mod=<list> | Модификации TLS: rnd, rndsni, sni=<str>, none | -               |

Важно: dupsid и padencap НЕ работают с syndata (требуют реальный TLS payload).

---

Standard Fooling (модификация L3/L4 заголовков)

| Параметр                  | Описание                                               |
|---------------------------|--------------------------------------------------------|
| ip_ttl=N                  | Установить IPv4 TTL                                    |
| ip6_ttl=N                 | Установить IPv6 hop limit                              |
| ip_autottl=delta,min-max  | Автоопределение IPv4 TTL (напр. -1,3-20)               |
| ip6_autottl=delta,min-max | Автоопределение IPv6 TTL                               |
| ip6_hopbyhop[=hex]        | Добавить hop-by-hop extension header                   |
| ip6_hopbyhop2[=hex]       | Добавить второй hop-by-hop header                      |
| ip6_destopt[=hex]         | Добавить destination options header                    |
| ip6_destopt2[=hex]        | Добавить второй destopt header                         |
| ip6_routing[=hex]         | Добавить routing header                                |
| ip6_ah[=hex]              | Добавить authentication header                         |
| tcp_seq=N                 | Сместить TCP sequence number                           |
| tcp_ack=N                 | Сместить TCP ack number                                |
| tcp_ts=N                  | Сместить TCP timestamp                                 |
| tcp_md5[=hex]             | Добавить MD5 TCP option (16 байт)                      |
| tcp_flags_set=<list>      | Установить TCP флаги (FIN,SYN,RST,PSH,ACK,URG,ECE,CWR) |
| tcp_flags_unset=<list>    | Снять TCP флаги                                        |
| tcp_ts_up                 | Переместить timestamp option в начало                  |
| fool=<func>               | Кастомная функция fooling                              |

---
Standard Reconstruct

| Параметр | Описание              |
|----------|-----------------------|
| badsum   | Испортить L4 checksum |

---
Standard Rawsend

| Параметр      | Описание                       |
|---------------|--------------------------------|
| repeats=N     | Количество повторов отправки   |
| ifout=<iface> | Override исходящего интерфейса |
| fwmark=N      | Override fwmark (Linux)        |

---
Standard IPfrag

| Параметр         | Описание                               | По умолчанию |
|------------------|----------------------------------------|--------------|
| ipfrag[=func]    | Функция фрагментатора                  | ipfrag2      |
| ipfrag_disorder  | Отправить фрагменты в обратном порядке | -            |
| ipfrag_pos_tcp=N | Позиция фрагментации TCP (кратно 8)    | 32           |
| ipfrag_pos_udp=N | Позиция фрагментации UDP (кратно 8)    | 8            |
| ipfrag_pos=N     | Общая позиция фрагментации             | -            |
| ipfrag_next=N    | Next protocol для IPv6 fragment header | -            |

---
НЕ поддерживается

| Параметр          | Причина                         |
|-------------------|---------------------------------|
| ip_id, ip_id_conn | syndata не вызывает apply_ip_id |
| tls_mod=dupsid    | Требует реальный TLS payload    |
| tls_mod=padencap  | Требует реальный TLS payload    |

---
Примеры использования

# Простая syndata (16 нулевых байт)
--lua-desync=syndata

# С TLS fake blob
--lua-desync=syndata:blob=fake_default_tls

# С модификацией SNI
--lua-desync=syndata:blob=fake_default_tls:tls_mod=rnd,sni=google.com

# С TTL fooling
--lua-desync=syndata:blob=fake_default_tls:ip_ttl=5:ip6_ttl=5

# С MD5 TCP option
--lua-desync=syndata:tcp_md5

# С IP фрагментацией
--lua-desync=syndata:blob=fake_default_tls:ipfrag:ipfrag_disorder

# Комбинация с другими функциями
--lua-desync=wssize:wsize=1:scale=6 --lua-desync=syndata --lua-desync=multisplit:pos=midsld

---
Особенности работы

1. Только TCP SYN — если пакет не SYN, выполняется instance cutoff
2. Нулевая фаза — работает до установления соединения
3. VERDICT_DROP — оригинальный SYN дропается, отправляется модифицированный
4. Один пакет — payload должен помещаться в один пакет (сегментация невозможна)
5. С хостлистами — работает только в режиме --ipcache-hostname

## dupsid и padencap МОЛЧА ИГНОРИРУЮТСЯ

Поведение:

| Аспект                 | Результат                       |
|------------------------|---------------------------------|
| Вызывают ошибку?       | НЕТ                             |
| Выводят warning в лог? | НЕТ                             |
| Возвращают false?      | НЕТ (возвращают true = "успех") |
| Применяются?           | НЕТ — код просто пропускается   |

Почему так происходит:
```c
// protocol.c:856-936
if (payload)  // ← syndata передаёт NULL сюда
{
  if (tls_mod->mod & FAKE_TLS_MOD_DUP_SID)
	  // ... этот код НЕ выполнится

  if (tls_mod->mod & FAKE_TLS_MOD_PADENCAP)
	  // ... и этот тоже
}
return bRes;  // возвращает true
```
Пример:
```bash
--lua-desync=syndata:blob=fake_default_tls:tls_mod=dupsid
```
Результат:
1. fake_default_tls загружается ✓
2. dupsid парсится без ошибки ✓
3. Блок if (payload) пропускается (payload=NULL)
4. Fake TLS отправляется БЕЗ дублирования session_id
5. Никакого предупреждения в логе

Итог по tls_mod в syndata:

| Мод      | Работает?             | Причина                      |
|----------|-----------------------|------------------------------|
| rnd      | ✅ ДА                 | Код вне блока if(payload)    |
| rndsni   | ✅ ДА                 | Код вне блока if(payload)    |
| sni=xxx  | ✅ ДА                 | Код вне блока if(payload)    |
| dupsid   | ❌ Молча игнорируется | Требует реальный ClientHello |
| padencap | ❌ Молча игнорируется | Требует реальный ClientHello |

Это дизайн-решение — dupsid/padencap нужен реальный TLS от клиента, которого на фазе SYN ещё нет.
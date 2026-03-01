---
date:
tags:
link:
aliases:
  - хостлист
img:
---
# 🌐 **[[filter|Фильтры]] по доменам (hostlist)**

### **`--hostlist`** - Включающий список доменов

**Синтаксис:**
```bash
--hostlist=<filename>
```

**Параметры:**
- `filename` - путь к файлу с доменами
- Формат: один домен на строку
- Поддомены применяются автоматически
- Поддержка gzip
- Можно указывать несколько раз

**Формат файла:**
```
youtube.com
google.com
facebook.com
```

**Особенности:**
- `youtube.com` автоматически включает `www.youtube.com`, `m.youtube.com` и т.д.

**Примеры:**
```bash
--hostlist=/path/to/domains.txt
--hostlist=/path/to/list1.txt --hostlist=/path/to/list2.txt.gz
```

---

### **`--hostlist-domains`** - Фиксированный список доменов

**Синтаксис:**
```bash
--hostlist-domains=<domain_list>
```

**Параметры:**
- Список доменов через запятую

**Примеры:**
```bash
--hostlist-domains=youtube.com,google.com,facebook.com
```

---

### **`--hostlist-exclude`** - Исключающий список доменов

**Синтаксис:**
```bash
--hostlist-exclude=<filename>
```

**Параметры:** (аналогично `--hostlist`)
- Домены, которые НЕ должны обрабатываться

**Примеры:**
```bash
--hostlist-exclude=/path/to/exclude_domains.txt
```

---

### **`--hostlist-exclude-domains`** - Фиксированный список исключений

**Синтаксис:**
```bash
--hostlist-exclude-domains=<domain_list>
```

**Примеры:**
```bash
--hostlist-exclude-domains=local.domain,internal.net
```

---

## 🤖 **Автоматический hostlist**

### **`--hostlist-auto`** - Автоматическое определение блокировок

**Синтаксис:**
```bash
--hostlist-auto=<filename>
```

**Параметры:**
- `filename` - файл для сохранения автоматически обнаруженных доменов
- Система автоматически определяет DPI блокировки и добавляет домены в список

**Примеры:**
```bash
--hostlist-auto=/var/lib/zapret/auto.txt
```

---

### **`--hostlist-auto-fail-threshold`** - Порог неудачных попыток

**Синтаксис:**
```bash
--hostlist-auto-fail-threshold=<int>
```

**Параметры:**
- Количество неудачных попыток для добавления домена в автолист
- **По умолчанию:** зависит от реализации

**Примеры:**
```bash
--hostlist-auto-fail-threshold=3
```

---

### **`--hostlist-auto-fail-time`** - Временное окно для неудач

**Синтаксис:**
```bash
--hostlist-auto-fail-time=<int>
```

**Параметры:**
- Время в секундах, в течение которого должны произойти неудачи
- **По умолчанию:** зависит от реализации

**Примеры:**
```bash
--hostlist-auto-fail-time=60    # все неудачи в течение 60 секунд
```

---

### **`--hostlist-auto-retrans-threshold`** - Порог ретрансмиссий

**Синтаксис:**
```bash
--hostlist-auto-retrans-threshold=<int>
```

**Параметры:**
- Количество ретрансмиссий запроса, которые считаются неудачей
- **По умолчанию:** зависит от реализации

**Примеры:**
```bash
--hostlist-auto-retrans-threshold=2
```

---

### **`--hostlist-auto-debug`** - Отладка автолиста (глобальный параметр)

**Синтаксис:**
```bash
--hostlist-auto-debug=<logfile>
```

**Параметры:**
- Путь к файлу логов для отладки автоматического определения

**Примеры:**
```bash
--hostlist-auto-debug=/var/log/zapret-auto.log
```
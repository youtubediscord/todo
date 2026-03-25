# AmneziaWG 2.0 — полный справочник параметров

> Составлен на основе анализа исходного кода [amneziawg-go](https://github.com/amnezia-vpn/amneziawg-go)
> Верифицировано по исходникам: 2026-03-25

## Обзор

AmneziaWG (*AWG, АмнезияВГ 2.0, Амнезия ВПН VPN*) — модифицированный WireGuard с обфускацией трафика для обхода DPI-блокировок.

**Версия 1.0** (2023): мусорные пакеты, padding handshake, фиксированные заголовки.
**Версия 2.0** (2025): signature packets (мимикрия под протоколы), range-based заголовки, padding для всех типов пакетов, CPS-язык для описания сигнатур.

Клиент: AmneziaVPN 4.8.12.9+ (desktop, Android). Self-hosted only для AWG 2.0.

---

## Все параметры протокола (17 штук)

### 1. Junk Packets — мусорные пакеты перед handshake

| Параметр | Тип | Валидация | Описание |
|----------|-----|-----------|----------|
| **Jc** | int | > 0, строго положительное | Количество мусорных пакетов |
| **Jmin** | int | > 0, строго положительное | Минимальный размер пакета (байт) |
| **Jmax** | int | > 0, строго положительное | Максимальный размер пакета (байт) |

Дефолт: 0 (отключено). Сериализуется в вывод только если != 0.

- Отправляются **только** при handshake initiation (~раз в 2 минуты)
- Размер каждого пакета: `crypto/rand.Int(Jmax - Jmin + 1) + Jmin`
- Данные: `crypto/rand.Read` (криптографически безопасные)
- Рекомендованный диапазон Jc: 4-12

**Важно**: в коде **нет** перекрёстной валидации `Jmin <= Jmax` — параметры проверяются независимо. Если задать Jmin > Jmax, поведение непредсказуемо.

```
Пример: Jc=7, Jmin=50, Jmax=1000
→ 7 пакетов, каждый 50-1000 байт случайных данных
```

### 2. Padding — случайные байты перед пакетами

| Параметр | Версия | Применяется к | Размер сообщения | Как часто |
|----------|--------|---------------|------------------|-----------|
| **S1** | 1.0 | Handshake Initiation | 148 байт | Каждый handshake (~2 мин) |
| **S2** | 1.0 | Handshake Response | 92 байта | Каждый handshake |
| **S3** | **2.0** | Cookie Reply | 64 байта | Редко (только под нагрузкой) |
| **S4** | **2.0** | Transport Data | переменный | **Каждый data-пакет** |

Валидация: `int >= 0` (в отличие от Jc/Jmin/Jmax, допускается 0). Дефолт: 0 (отключено).

**Механизм S1/S2/S3** — выделяется новый буфер, random prefix:
```
buf = make([]byte, padding + len(packet))
rand.Read(buf[:padding])         // Заполняем prefix случайными байтами
copy(buf[padding:], packet)      // Копируем пакет после prefix
```

**Механизм S4** — сдвиг данных в существующем буфере (отличается от S1-S3!):
```
// Сдвигаем зашифрованные данные ВПРАВО на padding байт
for i := len(elem.packet) - 1; i >= 0; i-- {
    elem.buffer[i+padding] = elem.buffer[i]
}
rand.Read(elem.buffer[:padding])  // Заполняем начало случайными байтами
```

**Приём (все типы)** — `DeterminePacketTypeAndPadding()` в `receive.go`:
```
data = packet[padding:]           // Пропускаем padding, читаем заголовок
header.Validate(LittleEndian.Uint32(data))  // Проверяем magic header
```

**Особенности S4**:
- Применяется к **каждому** data-пакету (основной трафик)
- **НЕ** применяется к keepalive-пакетам (проверка: `len(elem.packet) != MessageKeepaliveSize`)
  - `MessageKeepaliveSize = 32` байта (transport header 16B + Poly1305 tag 16B, нулевой payload)
- Добавляется **поверх** стандартного WireGuard-выравнивания до 16 байт (`PaddingMultiple = 16`)
- S1-S4 **не обязаны** быть кратны 16 — это любое целое >= 0; `PaddingMultiple` — отдельный внутренний механизм WireGuard
- При больших значениях может превысить MTU → фрагментация

### 3. Magic Headers — заголовки пакетов

| Параметр | Тип пакета | Формат | Byte order |
|----------|------------|--------|------------|
| **H1** | Handshake Init | `"N"` или `"N-M"` (uint32 range) | little-endian |
| **H2** | Handshake Response | `"N"` или `"N-M"` | little-endian |
| **H3** | Cookie Reply | `"N"` или `"N-M"` | little-endian |
| **H4** | Transport Data | `"N"` или `"N-M"` | little-endian |

Тип значения: `uint32` (0 — 4 294 967 295).

**Дефолтные значения** (устанавливаются в `NewDevice()`):
```go
device.headers.init      = &magicHeader{start: 1, end: 1}  // MessageInitiationType
device.headers.response  = &magicHeader{start: 2, end: 2}  // MessageResponseType
device.headers.cookie    = &magicHeader{start: 3, end: 3}  // MessageCookieReplyType
device.headers.transport = &magicHeader{start: 4, end: 4}  // MessageTransportType
```
Т.е. по умолчанию заголовки = стандартный WireGuard (1, 2, 3, 4). AWG без конфигурации H1-H4 полностью совместим с обычным WireGuard.

**Реализация** (`magic-header.go`):
```go
type magicHeader struct {
    start uint32
    end   uint32
}

func (h *magicHeader) Generate() uint32 {
    high := int64(h.end - h.start + 1)
    r, _ := rand.Int(rand.Reader, big.NewInt(high))
    return h.start + uint32(r.Int64())
}

func (h *magicHeader) Validate(val uint32) bool {
    return h.start <= val && val <= h.end
}
```

**Парсинг:**
- `"42"` → start=42, end=42 (фиксированный заголовок, как в AWG 1.0)
- `"471800590-471800690"` → start=471800590, end=471800690 (101 вариант)
- Валидация: `end >= start`, иначе ошибка `"wrong range specified"`

**Критичное ограничение:** диапазоны H1, H2, H3, H4 **НЕ должны пересекаться**.

Проверка происходит в `ipcSetDevice.mergeWithDevice()` — специальной функции, которая:
1. Заполняет не указанные в текущем IPC-вызове заголовки из существующего конфига устройства
2. Проверяет все 4 заголовка попарно на пересечение
3. Если ОК — применяет к устройству

Это значит: можно обновить один заголовок (напр. только H1) без повторного указания H2-H4 — они возьмутся из текущего конфига.

```go
// mergeWithDevice() — overlap check
headers := []*magicHeader{d.headers.init, d.headers.response, d.headers.cookie, d.headers.transport}
for i := 0; i < len(headers); i++ {
    for j := i + 1; j < len(headers); j++ {
        if left.start <= right.end && right.start <= left.end {
            return errors.New("headers must not overlap")
        }
    }
}
```

**Где применяются:**
- H1 → `CreateMessageInitiation()` в `noise-protocol.go`: `msg.Type = device.headers.init.Generate()`
- H2 → `CreateMessageResponse()`: `msg.Type = device.headers.response.Generate()`
- H3 → `SendHandshakeCookie()`: `msgType := device.headers.cookie.Generate()`
- H4 → `RoutineEncryption()`: `msgType := device.headers.transport.Generate()`

```
ХОРОШО (не пересекаются):
  H1 = 100-200
  H2 = 300-400
  H3 = 500-600
  H4 = 700-800

ПЛОХО:
  H1 = 100-200
  H2 = 150-250      # Пересекается с H1 → ошибка "headers must not overlap"
```

### 4. Signature Packets (i1-i5) — мимикрия под протоколы (NEW в 2.0)

| Параметр | Тип | Индекс в массиве |
|----------|-----|-------------------|
| **i1** | string (CPS) | `device.ipackets[0]` |
| **i2** | string (CPS) | `device.ipackets[1]` |
| **i3** | string (CPS) | `device.ipackets[2]` |
| **i4** | string (CPS) | `device.ipackets[3]` |
| **i5** | string (CPS) | `device.ipackets[4]` |

- До 5 пакетов, отправляемых **перед** каждым WireGuard handshake
- Описываются на языке CPS (Custom Protocol Signature)
- Если пакет не настроен (`nil`) — пропускается
- Хранятся в `device.ipackets [5]*obfChain`

**Отправка** (из `SendHandshakeInitiation()`):
```go
for _, ipacket := range peer.device.ipackets {
    if ipacket != nil {
        buf := make([]byte, ipacket.ObfuscatedLen(0))
        ipacket.Obfuscate(buf, nil)    // src = nil, генерация из тегов
        sendBuffer = append(sendBuffer, buf)
    }
}
```

---

## CPS — язык описания сигнатур

### Все 8 тегов (из исходного кода)

Зарегистрированы в `obfBuilders` map в `obf.go`:

```go
var obfBuilders = map[string]obfBuilder{
    "b":  newBytesObf,       // obf_bytes.go
    "t":  newTimestampObf,   // obf_timestamp.go
    "r":  newRandObf,        // obf_rand.go
    "rc": newRandCharObf,    // obf_randchars.go  (файл с 's'!)
    "rd": newRandDigitsObf,  // obf_randdigits.go
    "d":  newDataObf,        // obf_data.go
    "ds": newDataStringObf,  // obf_datastring.go
    "dz": newDataSizeObf,    // obf_datasize.go
}
```

| Тег | Формат | Параметр | Размер вывода | Описание | Документирован? |
|-----|--------|----------|---------------|----------|-----------------|
| `<b>` | `<b 0xDEADBEEF>` | **обязателен** (hex) | len(hex)/2 байт | Фиксированные байты | Да |
| `<t>` | `<t>` | игнорируется | 4 байта | Unix timestamp, big-endian uint32 | Да |
| `<r>` | `<r 100>` | **обязателен** (int) | N байт | Криптографически случайные байты | Да |
| `<rc>` | `<rc 10>` | **обязателен** (int) | N байт | Случайные буквы a-zA-Z (52 символа) | Да |
| `<rd>` | `<rd 5>` | **обязателен** (int) | N байт | Случайные цифры 0-9 | Да |
| `<d>` | `<d>` | игнорируется | = input | Pass-through (копия входных данных) | **Нет** |
| `<ds>` | `<ds>` | игнорируется | ~133% input | Base64 RawStdEncoding (без '=' padding) | **Нет** |
| `<dz>` | `<dz 4>` | **обязателен** (int) | N байт (фикс.) | Длина входных данных в big-endian байтах | **Нет** |

### Синтаксис CPS

```
Формат:  <тег параметр>
Цепочка: <тег1 параметр1><тег2 параметр2><тег3>...
```

**Парсер** (`newObfChain()` в `obf.go`):
- Ищет теги между `<` и `>`
- Имя тега — первый токен (до пробела), параметр — второй токен
- Теги обрабатываются последовательно слева направо
- Результаты конкатенируются в один пакет
- Ошибки **не** останавливают парсинг — собираются через `errors.Join()` и возвращаются все разом

**Ошибки парсера:**
- `"missing enclosing >"` — незакрытый тег
- `"empty tag"` — пустые скобки `<>`
- `"unknown tag <X>"` — тег не найден в `obfBuilders`
- `"failed to build <X>: ..."` — ошибка конструктора тега

### Интерфейс обфускатора

```go
type obf interface {
    Obfuscate(dst, src []byte)          // Записывает в dst
    Deobfuscate(dst, src []byte) bool   // Валидация + восстановление
    ObfuscatedLen(srcLen int) int        // Размер выхода
    DeobfuscatedLen(srcLen int) int      // Размер после деобфускации
}
```

### Детали реализации каждого тега

**`<b 0xHEX>` — фиксированные байты** (`obf_bytes.go`)
```
Вход:   hex-строка, префикс "0x" опционален
        Обработка префикса: strings.TrimPrefix(val, "0x") — только СТРОЧНЫЙ "0x"!
        "0X" (заглавный) НЕ распознаётся и останется в строке → ошибка.
        Примеры: "0xDEADBEEF" → "DEADBEEF", "DEADBEEF" → "DEADBEEF"
Выход:  бинарные данные из hex.DecodeString()
Размер: len(hex_digits) / 2
Ошибки:
  - "empty argument" — пустая строка (после trim)
  - "odd amount of symbols" — НЕЧЁТНОЕ кол-во hex-цифр (каждый байт = 2 hex-цифры)
  - hex.DecodeString error — невалидные hex-символы
Deobfuscate: проверяет ТОЧНОЕ побайтовое совпадение → false если не совпали

⚠ ВНИМАНИЕ: hex-строка ДОЛЖНА содержать ЧЁТНОЕ число hex-цифр!
  "0xDEADBEEF" → 8 цифр → OK (4 байта)
  "0xc7000000010" → 11 цифр → ОШИБКА "odd amount of symbols"!
  "0xc70000000108" → 12 цифр → OK (6 байт)
```

**`<t>` — timestamp** (`obf_timestamp.go`)
```
Вход:   параметр игнорируется (конструктор: newTimestampObf(_ string))
        <t> и <t anything> — оба валидны
Выход:  4 байта = time.Now().Unix() в big-endian uint32
Deobfuscate: ВСЕГДА true (нет проверки значения!)
DeobfuscatedLen: 0

В коде комментарий: "replay attack check? requires time to be always synchronized"
→ защита от replay НЕ реализована
```

**`<r N>` — случайные байты** (`obf_rand.go`)
```
Вход:   N — целое число (strconv.Atoi), обязательный параметр
Выход:  N байт из crypto/rand.Read
Deobfuscate: ВСЕГДА true (невозможно проверить случайность)
DeobfuscatedLen: 0

В коде: "// there is no way to validate randomness :)"
```

**`<rc N>` — случайные буквы** (`obf_randchars.go`)
```
Вход:   N — целое число
Алфавит: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" (52 символа)
Генерация: random_byte % 52 → индекс в алфавите
Deobfuscate: проверяет unicode.IsLetter() для каждого байта
DeobfuscatedLen: 0
```

**`<rd N>` — случайные цифры** (`obf_randdigits.go`)
```
Вход:   N — целое число
Алфавит: "0123456789" (10 символов)
Генерация: random_byte % 10 → индекс
Deobfuscate: проверяет unicode.IsDigit() для каждого байта
DeobfuscatedLen: 0
```

**`<d>` — pass-through** (`obf_data.go`) — **НЕ ДОКУМЕНТИРОВАН**
```
Параметр:  игнорируется (<d> и <d anything> — оба валидны)
Назначение: передаёт входные данные (src) без изменений в dst
ObfuscatedLen(n) = n  (размер не меняется)
DeobfuscatedLen(n) = n
Deobfuscate: всегда true

⚠ В signature packets (i1-i5) src=nil → <d> выводит 0 байт (бесполезен)
```

**`<ds>` — Base64** (`obf_datastring.go`) — **НЕ ДОКУМЕНТИРОВАН**
```
Параметр:  игнорируется
Назначение: кодирует src в Base64 (encoding/base64.RawStdEncoding, без '=' padding)
ObfuscatedLen(n) = base64.RawStdEncoding.EncodedLen(n)  (≈133% от входа)
DeobfuscatedLen(n) = base64.RawStdEncoding.DecodedLen(n)
Deobfuscate: декодирует Base64, но ИГНОРИРУЕТ ошибки декодирования (потенциальный баг)

⚠ В signature packets (i1-i5) src=nil → <ds> выводит 0 байт (бесполезен)
```

**`<dz N>` — размер данных** (`obf_datasize.go`) — **НЕ ДОКУМЕНТИРОВАН**
```
Вход:   N — количество байт для кодирования размера (strconv.Atoi), ОБЯЗАТЕЛЕН
Назначение: записывает len(src) как big-endian число в N байт
Алгоритм:
  for i := N-1; i >= 0; i-- {
      dst[i] = byte(srcLen & 0xFF)
      srcLen >>= 8
  }
ObfuscatedLen(n) = N  (фиксированный размер)
DeobfuscatedLen(n) = 0
Deobfuscate: всегда true

⚠ В signature packets (i1-i5) src=nil → len(nil)=0 → выводит N нулевых байт (0x00...00)
   Пример: <dz 2> в i1 → всегда выдаёт 0x0000
```

---

## Порядок отправки пакетов (верифицировано по send.go)

### SendHandshakeInitiation() — полная последовательность

```
HANDSHAKE (каждые ~2 минуты, проверка RekeyTimeout):

  ┌─────────────────────────────────────────────────────────────┐
  │ 1. Signature packets: i1 → i2 → i3 → i4 → i5              │
  │    (nil пропускаются, каждый — отдельный UDP-пакет)         │
  ├─────────────────────────────────────────────────────────────┤
  │ 2. Junk packets: Jc штук                                   │
  │    Размер каждого: rand(Jmin..Jmax) байт                   │
  │    Содержимое: crypto/rand.Read                             │
  ├─────────────────────────────────────────────────────────────┤
  │ 3. Handshake Init message:                                  │
  │    a) CreateMessageInitiation() → msg.Type = H1.Generate()  │
  │    b) binary.Write(LittleEndian, msg) → 148 байт            │
  │    c) cookieGenerator.AddMacs(packet) → MAC1 + MAC2         │
  │    d) Если S1 > 0: [S1 random bytes][packet]               │
  │    Итого: S1 + 148 байт                                    │
  └─────────────────────────────────────────────────────────────┘
  Всё отправляется ОДНИМ вызовом peer.SendBuffers(sendBuffer)
```

### SendHandshakeResponse() — отдельно

**Signature packets (i1-i5) и junk packets НЕ отправляются с Response!**
Они отправляются ТОЛЬКО с Init. Это подтверждено по коду: SendHandshakeResponse()
не содержит ссылок на `device.ipackets` или `device.junk`.

```
  ┌─────────────────────────────────────────────────────────────┐
  │ 4. Handshake Response message:                              │
  │    a) CreateMessageResponse() → msg.Type = H2.Generate()    │
  │    b) binary.Write(LittleEndian, msg) → 92 байта            │
  │    c) BeginSymmetricSession() → деривация ключей            │
  │    d) cookieGenerator.AddMacs(packet)                       │
  │    e) Если S2 > 0: [S2 random bytes][packet]               │
  │    f) SendBuffers([][]byte{packet}) — один пакет            │
  │    Итого: S2 + 92 байта                                    │
  └─────────────────────────────────────────────────────────────┘
```

### SendHandshakeCookie() — под нагрузкой

```
ПОД НАГРУЗКОЙ (DoS protection, редко):
  ┌─────────────────────────────────────────────────────────────┐
  │ 5. Cookie Reply:                                            │
  │    a) msgType = H3.Generate()                               │
  │    b) cookieChecker.CreateReply(..., msgType)               │
  │    c) binary.Write → 64 байта                               │
  │    d) Если S3 > 0: [S3 random bytes][packet]               │
  │    Итого: S3 + 64 байта                                    │
  │                                                             │
  │    Отправляется через device.net.bind.Send() НАПРЯМУЮ       │
  │    (не через peer queue, в отличие от Init/Response)        │
  └─────────────────────────────────────────────────────────────┘
```

### RoutineEncryption() + RoutineSequentialSender() — data трафик

```
DATA ТРАФИК (постоянно):
  ┌─────────────────────────────────────────────────────────────┐
  │ 6. Transport packet:                                        │
  │    a) RoutineEncryption():                                  │
  │       - H4.Generate() → первые 4 байта (little-endian)     │
  │       - calculatePaddingSize() → выравнивание до 16 байт   │
  │       - AEAD шифрование (ChaCha20-Poly1305)                │
  │    b) RoutineSequentialSender():                            │
  │       - Если НЕ keepalive И S4 > 0:                        │
  │         сдвиг данных вправо на S4, random prefix            │
  │    Итого: S4 + 16B header + encrypted payload + 16B align  │
  │                                                             │
  │    Keepalive: S4 НЕ применяется (len == MessageKeepaliveSize)│
  └─────────────────────────────────────────────────────────────┘
```

### Приём пакетов — DeterminePacketTypeAndPadding()

Функция в `receive.go` определяет тип пакета по размеру + magic header:

```go
// Для Init/Response/Cookie — ТОЧНОЕ совпадение размера:
if size == padding + MessageInitiationSize { ... }   // S1 + 148
if size == padding + MessageResponseSize { ... }     // S2 + 92
if size == padding + MessageCookieReplySize { ... }  // S3 + 64

// Для Transport — больше или равно (переменный payload):
if size >= padding + MessageTransportHeaderSize { ... }  // S4 + 16+
```

Затем:
1. Пропускает `padding` байт
2. Читает uint32 из первых 4 байт (little-endian)
3. Валидирует через `header.Validate(value)`
4. При совпадении — убирает padding: `copy(packet, packet[padding:])` + truncate

**Junk и Signature пакеты на приёме:**
Явной обработки нет. Junk-пакеты и signature-пакеты не проходят проверку `DeterminePacketTypeAndPadding()` (возвращается `MessageUnknownType`) и **молча отбрасываются** — ни ошибок, ни логов. Это by design: они нужны только для обмана DPI на сетевом уровне.

**Нет fallback к стандартному WireGuard:**
Функция проверяет пакеты **только** через настроенные AWG-заголовки (H1-H4). Если H1-H4 изменены, стандартные WireGuard-пакеты (type=1,2,3,4) будут отброшены как `MessageUnknownType`. Обратной совместимости с обычным WireGuard при изменённых заголовках нет.

---

## Примеры конфигураций

### Минимальная конфигурация AWG 2.0

```ini
[Interface]
PrivateKey = YOUR_KEY
Address = 10.8.1.2/24
DNS = 1.1.1.1

# Junk
Jc = 5
Jmin = 50
Jmax = 500

# Padding
S1 = 40
S2 = 40

# Headers (фиксированные, совместимость с 1.0)
H1 = 123456789
H2 = 987654321
H3 = 111111111
H4 = 222222222

[Peer]
PublicKey = SERVER_KEY
Endpoint = server:51820
AllowedIPs = 0.0.0.0/0
```

### Полная конфигурация AWG 2.0

```ini
[Interface]
PrivateKey = YOUR_KEY
Address = 10.8.1.2/24
DNS = 1.1.1.1, 1.0.0.1

# --- Junk packets ---
Jc = 7
Jmin = 50
Jmax = 1000

# --- Padding (все типы) ---
S1 = 68
S2 = 149
S3 = 32
S4 = 16

# --- Range-based headers ---
H1 = 471800590-471800690
H2 = 1246894907-1246895000
H3 = 923637689-923637690
H4 = 1769581055-1869581055

# --- Signature packets (мимикрия под QUIC) ---
i1 = <b 0xc70000000108><rc 8><t><r 100>
i2 = <b 0xf6ab3267fa><t><rc 20><r 80>

[Peer]
PublicKey = SERVER_KEY
Endpoint = server:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

### Примеры сигнатур для мимикрии

**DNS-запрос:**
```
i1 = <b 0x1a2d0100000100000000000109696e666572656e6365><t><r 15>
```
Побайтовый разбор hex (верифицировано по RFC 1035):
- `1a2d` — Transaction ID (произвольный)
- `0100` — Flags: Standard Query, Recursion Desired
- `0001` — QDCOUNT: 1 вопрос
- `0000 0000` — ANCOUNT=0, NSCOUNT=0
- `0001` — ARCOUNT: 1 additional record
- `09` — DNS label length = 9
- `696e666572656e6365` — ASCII "inference"

**QUIC Initial (верифицировано по RFC 9000):**
```
i1 = <b 0xc70000000108><rc 8><t><r 100>
```
Побайтовый разбор hex:
- `c7` = `11000111` — Form=1 (Long), Fixed=1, Type=00 (Initial), Reserved=0111
- `00000001` — Version = QUIC v1
- `08` — DCID Length = 8 байт
- `<rc 8>` — 8 случайных букв имитируют Destination Connection ID
- `<t>` — timestamp добавляет уникальность каждому handshake
- `<r 100>` — 100 случайных байт заполняют payload

**SIP INVITE (текстовый протокол):**
```
i1 = <b 0x494e56495445207369703a><rc 12><b 0x4053697056504e2e636f6d20534950><r 50>
```
Hex = "INVITE sip:" + random user + "@SipVPN.com SIP" + random payload.

**Многопакетная сигнатура:**
```
i1 = <b 0xc70000000108><rc 8><t><r 100>    # мимикрия под QUIC Initial
i2 = <b 0xf6ab3267fa><t><rc 20><r 80>      # произвольные магические байты (не протокол)
i3 = <r 200>                                 # чистый шум
```
3 пакета перед каждым handshake: QUIC-подобный + кастомный + чистый шум.

**С недокументированным тегом `<dz>`:**
```
i1 = <dz 2><r 50>
```
2 нулевых байта (т.к. src=nil в signature packets, len=0) + 50 случайных байт.
Может имитировать length-prefixed протокол с пустым полем длины.

> **Примечание:** теги `<d>` и `<ds>` **бесполезны** в i1-i5, т.к. signature packets
> вызывают `Obfuscate(buf, nil)` — src всегда nil, и эти теги выводят 0 байт.
> Они предназначены для возможного использования obfChain в других контекстах.

---

## Подводные камни и ограничения

### 1. MTU overflow при S4

S4 добавляется поверх стандартного WireGuard-выравнивания и AEAD overhead.

**Расчёт размера пакета на проводе** (network MTU обычно = 1500):
```
IP header:           20 байт
UDP header:           8 байт
S4 random prefix:    S4 байт
WG transport header: 16 байт (H4 type + receiver + nonce)
Encrypted payload:   padded_plaintext байт (ChaCha20, размер = вход)
Poly1305 auth tag:   16 байт
─────────────────────────────
ИТОГО IP-пакет = 60 + S4 + padded_plaintext

Максимальный plaintext без фрагментации:
  max_plaintext = network_MTU - 60 - S4

  S4=0:   max = 1500 - 60 = 1440 (стандартный WireGuard)
  S4=16:  max = 1500 - 76 = 1424
  S4=50:  max = 1500 - 110 = 1390

Рекомендуемый TUN MTU = network_MTU - 60 - S4
  S4=0 → TUN MTU ≈ 1420 (стандартный WG дефолт)
  S4=16 → TUN MTU ≈ 1400
  S4=50 → TUN MTU ≈ 1370
```

**IPv6:** заголовок IPv6 = 40 байт (вместо 20 у IPv4). Формула для IPv6:
```
max_plaintext_ipv6 = network_MTU - 80 - S4    (40+8+16+16=80)
```

**Важно:** `calculatePaddingSize()` работает с TUN MTU (размер payload от TUN-устройства), а не с network MTU. Если TUN MTU не уменьшен для компенсации S4, пакеты будут фрагментироваться на уровне IP.

### 2. Дефолтные значения и совместимость
AWG-параметры по умолчанию:
- **H1-H4**: инициализированы стандартными WireGuard-типами (1, 2, 3, 4) в `NewDevice()` — НЕ nil!
- **S1-S4, Jc/Jmin/Jmax**: 0 (обфускация выключена)
- **i1-i5**: nil (signature packets отключены)

Без явной конфигурации AWG-параметров протокол полностью совместим с обычным WireGuard.
Параметры клиента и сервера **должны совпадать** — иначе стороны не смогут декодировать пакеты.

### 3. Timestamp без replay-защиты
Тег `<t>` записывает `time.Now().Unix()`, но при deobfuscation **всегда возвращает true**. Код содержит комментарий: `"replay attack check? requires time to be always synchronized"` — защита не реализована.

### 4. Random нельзя валидировать
`<r N>` при deobfuscation возвращает true безусловно. `DeobfuscatedLen` = 0. Комментарий: `"there is no way to validate randomness :)"`.

### 5. Header overlap
Диапазоны H1-H4 проверяются на пересечение при **config merge** (после установки всех 4-х заголовков). Ошибка: `"headers must not overlap"`. Если пересекаются → невозможно определить тип пакета.

### 6. Keepalive без S4
S4 **не применяется** к keepalive (проверка `len(elem.packet) != MessageKeepaliveSize`). Это потенциальный fingerprint для DPI — keepalive-пакеты имеют предсказуемый размер.

### 7. Размер сигнатурных пакетов
- Минимум: 100+ байт (короткие подозрительны для DPI)
- Оптимум: 100-500 байт
- Максимум: ~1200 байт (UDP MTU)
- Нет жёсткого ограничения в коде, но > MTU → фрагментация

### 8. Jmin/Jmax не проверяются перекрёстно
В коде нет валидации `Jmin <= Jmax`. Каждый параметр проверяется только на `> 0` независимо.

### 9. `<ds>` игнорирует ошибки декодирования
`Deobfuscate()` в `obf_datastring.go` вызывает `base64.Decode()`, но **отбрасывает ошибку** — потенциальный баг в реализации.

### 10. `<b>` принимает только строчный "0x"
`strings.TrimPrefix(val, "0x")` — убирает только `0x`, но **НЕ** `0X`. Если написать `<b 0XDEAD>`, hex-парсинг сломается.

### 11. Signature/junk только при Initiation
Signature packets (i1-i5) и junk packets отправляются **только** при `SendHandshakeInitiation()`. `SendHandshakeResponse()` не содержит ссылок на `device.ipackets` и `device.junk` — Response отправляется без маскировки (только S2 padding и H2 header).

### 12. Transport пакеты батчатся
`RoutineSequentialSender()` собирает несколько зашифрованных transport-пакетов в `bufs` (до `maxBatchSize` штук) и отправляет одним вызовом `peer.SendBuffers(bufs)`. S4 padding применяется к каждому пакету в batch индивидуально.

### 13. Пробелы в hex-строках `<b>` молча обрезают данные
Парсер CPS использует `strings.Fields()` и берёт только `parts[1]`:
```
<b 0xDEADBEEF>      → val="0xDEADBEEF"     → OK, 4 байта
<b 0xDE AD BE EF>   → val="0xDE"            → ТОЛЬКО 1 байт! (AD BE EF потеряны)
```
Ошибки нет, данные молча теряются. Все hex-цифры должны быть слитно.

### 14. Текст между тегами CPS молча игнорируется
```
"hello<r 10>world<t>"   → "hello" и "world" отброшены без ошибок
"<r 10> trailing text"  → "trailing text" отброшен
```
Парсер ищет только содержимое внутри `< >`, всё остальное пропускается.

### 15. Только один динамический тег на цепочку
Теги `<d>` и `<ds>` имеют переменную длину выхода (зависит от входных данных). При `Deobfuscate()` длина вычисляется как:
```go
dynamicLen := len(src) - c.ObfuscatedLen(0)  // все динамические байты
```
Эта формула корректна **только если в цепочке один динамический тег**. Два динамических тега (напр. `<d><ds>`) вызовут buffer overrun — первый заберёт все байты, второму ничего не останется. Ограничение не документировано и не валидируется парсером.

В контексте signature packets (i1-i5) это неактуально — src=nil, динамических данных нет.

---

## Рекомендации по выбору значений

### Для обхода базовых DPI (Россия, 2026)

```ini
# Достаточно для большинства случаев
Jc = 5
Jmin = 50
Jmax = 500
S1 = 40
S2 = 40
S3 = 0
S4 = 0
H1 = 100000000-200000000
H2 = 300000000-400000000
H3 = 500000000-600000000
H4 = 700000000-800000000
```

### Для продвинутых DPI (полная мимикрия)

```ini
Jc = 7
Jmin = 50
Jmax = 1000
S1 = 68
S2 = 149
S3 = 32
S4 = 16
H1 = 471800590-471800690
H2 = 1246894907-1246895000
H3 = 923637689-923637690
H4 = 1769581055-1869581055
i1 = <b 0xc70000000108><rc 8><t><r 100>
i2 = <b 0xf6ab3267fa><t><rc 20><r 80>
```

### Баланс безопасность vs скорость

| Параметр | Влияние на скорость | Влияние на обфускацию | Когда работает |
|----------|--------------------|-----------------------|----------------|
| Jc | Минимальное | Среднее | Только handshake |
| S1, S2 | Минимальное | Среднее | Только handshake |
| S3 | Минимальное | Низкое | Редко (DoS) |
| **S4** | **Значительное** | **Высокое** | **Каждый пакет** |
| H1-H4 ranges | Минимальное (1 rand/пакет) | Высокое | Каждый пакет |
| i1-i5 | Минимальное | Высокое | Только handshake |

**S4 — единственный параметр с заметным влиянием на throughput.** Начинайте с S4=0, увеличивайте при необходимости.

---

## Структура в исходном коде

```
amneziawg-go/device/
├── device.go           # Device struct: junk, paddings, headers, ipackets[5]
├── uapi.go             # IPC парсер: jc/jmin/jmax, s1-s4, h1-h4, i1-i5
├── send.go             # SendHandshakeInitiation/Response/Cookie, RoutineEncryption/Sender
├── receive.go          # DeterminePacketTypeAndPadding(), RoutineReceiveIncoming
├── noise-protocol.go   # CreateMessageInitiation/Response → H1/H2 headers
├── magic-header.go     # magicHeader: newMagicHeader(), Generate(), Validate()
├── constants.go        # PaddingMultiple=16, RekeyAfterTime=120s, etc.
├── obf.go              # obfChain, obfBuilders map, newObfChain() парсер
├── obf_bytes.go        # <b> — фиксированные hex-байты
├── obf_timestamp.go    # <t> — Unix timestamp (4B big-endian)
├── obf_rand.go         # <r> — crypto/rand случайные байты
├── obf_randchars.go    # <rc> — случайные буквы a-zA-Z (52 символа)
├── obf_randdigits.go   # <rd> — случайные цифры 0-9
├── obf_data.go         # <d> — pass-through (НЕ ДОКУМЕНТИРОВАН)
├── obf_datastring.go   # <ds> — Base64 RawStdEncoding (НЕ ДОКУМЕНТИРОВАН)
└── obf_datasize.go     # <dz> — длина данных в байтах (НЕ ДОКУМЕНТИРОВАН)
```

---

## Сравнение AWG 1.0 vs 2.0

| Возможность | AWG 1.0 | AWG 2.0 |
|-------------|---------|---------|
| Junk packets | Jc, Jmin, Jmax | Jc, Jmin, Jmax (без изменений) |
| Handshake padding | S1, S2 | S1, S2, **S3**, **S4** |
| Заголовки | H1-H4 (фиксированные uint32) | H1-H4 (**range-based**, N-M) |
| Мимикрия | Нет | **i1-i5 + CPS** |
| CPS теги | Нет | **8 тегов** (5 документированных + 3 скрытых) |
| DPI bypass | Signature-based only | **Signature + statistical + protocol mimicry** |

---

## Побайтовая структура сообщений WireGuard

Размеры верифицированы по структурам в `noise-protocol.go`:

### MessageInitiation — 148 байт
```
Offset  Size  Field
──────  ────  ─────────────────────────────
0       4     Type (uint32, H1 magic header)
4       4     Sender (uint32, индекс отправителя)
8       32    Ephemeral (NoisePublicKey)
40      48    Static (NoisePublicKey 32 + Poly1305 Tag 16)
88      28    Timestamp (TAI64N 12 + Poly1305 Tag 16)
116     16    MAC1 (blake2s-128)
132     16    MAC2 (blake2s-128)
──────  ────
        148   ИТОГО
```

### MessageResponse — 92 байта
```
Offset  Size  Field
──────  ────  ─────────────────────────────
0       4     Type (uint32, H2 magic header)
4       4     Sender (uint32)
8       4     Receiver (uint32)
12      32    Ephemeral (NoisePublicKey)
44      16    Empty (Poly1305 Tag, encrypted empty)
60      16    MAC1 (blake2s-128)
76      16    MAC2 (blake2s-128)
──────  ────
        92    ИТОГО
```

### MessageCookieReply — 64 байта
```
Offset  Size  Field
──────  ────  ─────────────────────────────
0       4     Type (uint32, H3 magic header)
4       4     Receiver (uint32)
8       24    Nonce (XChaCha20-Poly1305 nonce)
32      32    Cookie (blake2s-128 16 + Poly1305 Tag 16)
──────  ────
        64    ИТОГО
```

### MessageTransport — 16+ байт (переменный)
```
Offset  Size      Field
──────  ────────  ─────────────────────────────
0       4         Type (uint32, H4 magic header)
4       4         Receiver (uint32)
8       8         Counter (uint64, nonce)
16      variable  Ciphertext (encrypted payload + 16B Poly1305 auth tag)
──────  ────────
        16+       ИТОГО (заголовок фиксирован, payload переменный)
```

### Полный wire-format transport пакета (с AWG обфускацией)

```
Порядок формирования (из кода):

1. RoutineEncryption():
   - Генерирует H4 header → записывает в buffer[0:16]
   - calculatePaddingSize() → добавляет нули к payload (выравнивание до 16 байт)
   - AEAD Seal(header, nonce, padded_payload, nil):
     ciphertext = Encrypt(padded_payload) + 16B Poly1305 tag
     Результат: [16B header][ciphertext][16B tag]

2. RoutineSequentialSender() (если S4 > 0 и НЕ keepalive):
   - Сдвигает весь зашифрованный пакет вправо на S4 байт
   - Заполняет первые S4 байт случайными данными

Итоговый пакет на проводе:
┌──────────────┬──────────────────────────┬────────────────────────────┬───────────┐
│ S4 random    │ WG Transport Header      │ encrypted(payload + align) │ Poly1305  │
│ (S4 байт)   │ H4(4B) + recv(4B) + nonce│ (переменный)               │ (16B tag) │
│              │ (8B) = 16 байт           │                            │           │
└──────────────┴──────────────────────────┴────────────────────────────┴───────────┘
               ↑ header (16B, LE)          ↑ ciphertext                            ↑
```

### MessageKeepalive — 32 байта
```
= MessageTransport с нулевым payload:
  16B header + 16B Poly1305 tag (шифрование пустых данных) = 32 байта
  MessageKeepaliveSize = MessageTransportSize = 32
```

---

## Стандартные константы WireGuard (constants.go)

```
RekeyAfterMessages      = 2^60 сообщений
RejectAfterMessages     = 2^64 - 2^13 - 1
RekeyAfterTime          = 120 секунд        ← интервал handshake (~2 мин)
RekeyAttemptTime        = 90 секунд
RekeyTimeout            = 5 секунд           ← double-lock check в SendHandshakeInitiation
RekeyTimeoutJitterMaxMs = 334 мс
RejectAfterTime         = 180 секунд
KeepaliveTimeout        = 10 секунд
CookieRefreshTime       = 120 секунд
HandshakeInitiationRate = 1/50 секунды       ← rate limit
PaddingMultiple         = 16                 ← WireGuard внутреннее выравнивание payload
MaxTimerHandshakes      = 90 / 5 = 18       ← макс. попыток handshake
```

**Стандартные type values** (заменяются H1-H4):
```
MessageInitiationType  = 1
MessageResponseType    = 2
MessageCookieReplyType = 3
MessageTransportType   = 4
MessageUnknownType     = 0  (пакет не опознан → отброс)
```

---

## Дополнительные технические детали

### Double-lock pattern в SendHandshakeInitiation()
```go
// Быстрая проверка без блокировки (RLock):
peer.handshake.mutex.RLock()
if time.Since(peer.handshake.lastSentHandshake) < RekeyTimeout {
    peer.handshake.mutex.RUnlock()
    return nil  // Слишком рано для нового handshake
}
peer.handshake.mutex.RUnlock()

// Полная блокировка с повторной проверкой (Lock):
peer.handshake.mutex.Lock()
if time.Since(peer.handshake.lastSentHandshake) < RekeyTimeout {
    peer.handshake.mutex.Unlock()
    return nil
}
peer.handshake.lastSentHandshake = time.Now()
peer.handshake.mutex.Unlock()
```
Классический double-check locking для предотвращения дупликатов handshake.

### calculatePaddingSize() — выравнивание payload
```go
func calculatePaddingSize(packetSize, mtu int) int {
    lastUnit := packetSize
    if mtu == 0 {
        // Нет MTU → выравнивание до ближайших 16 байт
        return ((lastUnit + 16 - 1) & ^(16 - 1)) - lastUnit
    }
    if lastUnit > mtu {
        lastUnit %= mtu    // Берём остаток от деления на MTU
    }
    paddedSize := ((lastUnit + 16 - 1) & ^(16 - 1))
    if paddedSize > mtu {
        paddedSize = mtu   // Не превышать MTU
    }
    return paddedSize - lastUnit
}
```
Применяется ПЕРЕД AEAD-шифрованием в `RoutineEncryption()`. S4 добавляется ПОСЛЕ.

**Примеры вычислений:**
```
calculatePaddingSize(1480, 1500) = 8    # 1480 → 1488 (ближайшее кратное 16)
calculatePaddingSize(1500, 1500) = 0    # ceil(1500/16)*16=1504 > MTU → cap to 1500, pad=0
calculatePaddingSize(1501, 1500) = 15   # 1501 % 1500 = 1, ceil(1/16)*16=16, pad=15
calculatePaddingSize(0, 1500)    = 0    # пустой payload (keepalive), 0 уже кратно 16
calculatePaddingSize(100, 0)     = 12   # без MTU: ceil(100/16)*16=112, pad=12
```

### Нет unit-тестов для CPS
Файл `obf_test.go` в репозитории **отсутствует**. Парсер CPS и все 8 обфускаторов не покрыты тестами. Это увеличивает риск скрытых багов (как `<ds>` Deobfuscate, игнорирующий ошибки).

### UAPI: порядок параметров при сериализации (GET)
```
jc → jmin → jmax → s1 → s2 → s3 → s4 → h1 → h2 → h3 → h4 → i1 → i2 → i3 → i4 → i5
```
Параметры со значением 0/nil **не включаются** в вывод.

---

## Ошибки в статье на Хабре (по результатам анализа кода)

| Что написано в статье | Что в коде | Комментарий |
|----------------------|------------|-------------|
| Init = 144 байта | `MessageInitiationSize` = 148 байт | Статья не учитывает 4 байта type field |
| Response = 88 байт | `MessageResponseSize` = 92 байта | Аналогично |
| Cookie Reply = 64 байта (в тексте), 60 байт (в схеме) | `MessageCookieReplySize` = 64 байта | Схема в статье неверна |
| CPS: 5 тегов | 8 тегов в obfBuilders | `<d>`, `<ds>`, `<dz>` не упомянуты |
| `<rc>` = "случайные буквы/цифры [A-Za-z]" | Только буквы a-zA-Z (52 символа) | В статье ошибочно написано "букв/цифр" |
| QUIC пример: `<b 0xc7000000010>` | 11 hex-цифр = **нечётное** → ОШИБКА | Реальные конфиги: один `<b>` blob ~1250 байт (чётное) |
| Сигнатуры из мелких тегов `<b><rc><t><r>` | Клиент генерирует один `<b 0x...>` blob | `<rc>`,`<t>`,`<r>` для ручных конфигов; клиент пакует всё в статический hex |
| Signature packets "перед каждым handshake" | Только перед **Init**, НЕ Response | SendHandshakeResponse() не содержит ipackets/junk |

---

## Реальные конфиги AmneziaVPN vs примеры из статьи

Клиент AmneziaVPN генерирует signature packets **иначе**, чем показано в статье на Хабре:

**Статья Хабр** (образовательный пример, составной):
```
I1 = <b 0xc7000000010><rc 8><t><r 100>
      ↑ QUIC header      ↑ random  ↑ random payload
      (СЛОМАН: 11 hex-цифр = нечётное → ошибка парсера)
```
Идея: собрать пакет из нескольких тегов, каждый handshake будет уникальным.

**Реальный конфиг AmneziaVPN** (self-hosted, из рабочего подключения):
```
I1 = <b 0xc70000000108df2b1b...896>
      ↑ ОДИН тег <b>, 2500 hex-цифр = 1250 байт статических данных
```
Клиент генерирует **весь пакет целиком** как один `<b>` blob:
- Первые 6 байт: `c70000000108` — валидный QUIC Initial v1 header (DCID len=8)
- Остальные 1244 байта: случайные данные, сгенерированные клиентом при установке

**Ключевое отличие**: статический blob отправляет одинаковые байты при каждом handshake. Составной вариант с `<rc>`, `<t>`, `<r>` генерирует уникальный пакет каждые ~2 минуты. Статический проще для DPI-фингерпринта, но на практике достаточен — DPI анализирует паттерны протокола, а не сравнивает конкретные байты.

---

## Что документирует README репозитория

README (`amneziawg-go/README.md`) документирует **только** эти CPS-теги:
```
<b 0x[seq]>, <r [size]>, <rd [size]>, <rc [size]>, <t>
```

Теги `<d>`, `<ds>`, `<dz>` **не упомянуты** ни в README, ни в статье на Хабре — обнаружены только анализом исходного кода (`obfBuilders` map в `obf.go`).

README рекомендует Jc = 4-12 и отмечает что все параметры дефолтятся в 0.

---

## Метаданные репозитория

- **Версия**: 0.0.20250522 (из `version.go`)
- **Go**: >= 1.24.4
- **AWG 2.0 merge**: сентябрь 2025 (PR #91 — ranged H1-H4, S3/S4)
- **Последний значимый коммит**: 2025-12-01 — рефакторинг junk packets (#103)
- **Unit-тесты CPS**: отсутствуют (`obf_test.go` не существует)
- **Примеры конфигов**: нет (конфигурация только через IPC/UAPI)

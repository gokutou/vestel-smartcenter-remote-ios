# Vestel / Toshiba Akıllı TV Kumandası — iOS (Mac'siz) Proje Notları

**Durum:** Çalışıyor, kişisel kullanıma hazır. Tüm komutlar (tuş, klavye, uygulama açma, fare hareketi ve tıklama) resmi Smart Center uygulamasıyla aynı protokol üzerinden, tcpdump ile doğrulanmış.
**Platform:** SwiftUI iOS uygulaması, **Mac olmadan** derlenip (`xtool`) **LiveContainer** ile imzasız çalıştırılıyor.
**Son güncelleme:** 28 Haziran 2026

---

## 1. Genel Bakış

Amaç: Mac'imiz ve ücretli geliştirici hesabımız olmadan, yerel ağ (LAN) üzerinden Vestel/Toshiba akıllı TV'yi kontrol eden bir iPhone uygulaması yazmak ve çalıştırmak.

Çalışma mantığı kısaca:

1. Telefon ve TV **aynı Wi-Fi ağında**.
2. Uygulama, TV'nin IP'sini ağda tarayarak bulur (ya da elle girilir).
3. TV'ye, `http://<TV_IP>:56789/apps/SmartCenter` adresine **HTTP POST** ile küçük XML komutları gönderir.
4. TV bu komutları, fiziksel kumanda / resmi uygulama gönderiyormuş gibi işler.

**Ön koşul (TV tarafı):** TV ayarlarında **"Virtual Remote" (Sanal Kumanda) açık** olmalı. Tuş ve klavye komutları çalışıyorsa bu zaten açıktır.

---

## 2. Mimari

```
┌─────────────┐     HTTP POST (XML)      ┌──────────────────┐
│  iPhone     │ ───────────────────────▶ │  TV              │
│ (LiveCont.) │   :56789/apps/SmartCenter│  56789 portu     │
│  SwiftUI    │ ◀─────────────────────── │  (Virtual Remote)│
└─────────────┘   201 Created            └──────────────────┘
        │
        └── Keşif: en0'ın /24 subnet'inde 56789 portu açık olan host'u tarar
```

- Tek dosyalık SwiftUI uygulaması.
- Ağ katmanı: `URLSession` (komutlar) + `Network.framework` `NWConnection` (port taraması) + `NWBrowser` (Local Network izni tetikleme).
- Tüm komutlar **"gönder ve unut"** (fire-and-forget) — TV'den durum bilgisi okunmuyor (bkz. Sınırlar ve Gelecek Fikirleri).

---

## 3. Tersine Mühendislikle Çözülen TV API (Referans)

> Bu bölüm projenin en değerli kısmı. Komutların hepsi `POST http://<TV_IP>:56789/apps/SmartCenter` adresine gider.

### 3.1. Ortak istek formatı

```
POST /apps/SmartCenter HTTP/1.1
application_name: vestel smart center
Content-Type: text/plain; charset=ISO-8859-1

<XML gövdesi>
```

- **`application_name: vestel smart center`** başlığı zorunlu.
- Gövde **ISO-8859-1 (Latin-1)** ile kodlanmalı (Swift'te `.isoLatin1`).
- Başarılı yanıt: `HTTP/1.1 201 Created`.

### 3.2. Uzaktan kumanda tuşu

```xml
<?xml version='1.0' ?><remote><key code='XXXX'/></remote>
```

### 3.3. Klavye karakteri (yalnızca TV tarayıcısında çalışır)

```xml
<?xml version='1.0' ?><keyboard><key value='UNICODE'/></keyboard>
```

`UNICODE` = karakterin Unicode kod değeri (ör. 'a' → 97).
**Not:** Bu yalnızca TV'nin **yerleşik tarayıcısında** gerçek bir metin alanı odaktayken çalışır. YouTube gibi ayrı uygulamalarda çalışmaz (bkz. Sınırlar).

### 3.4. Uygulama açma (portal)

```xml
<?xml version='1.0' ?><browserseturl><load url='http://www.portaltv.tv/swf/APPNAME/APPNAME.swf' page='RC'/></browserseturl>
```

Örnek: Prime Video için `APPNAME=amazon`.

### 3.5. Fare / touchpad (tcpdump ile doğrulandı)

**Hareket** — göreli (relative) delta, `button='0'`:

```xml
<?xml version='1.0' ?><mouseevent><event_data dx='5' dy='-22' button='0'/></mouseevent>
```

**Tıklama** — basma + bırakma (doğrulandı: `button='1'` → kısa bekleme → `button='0'`):

```xml
<?xml version='1.0' ?><mouseevent><event_data dx='0' dy='0' button='1'/></mouseevent>
<?xml version='1.0' ?><mouseevent><event_data dx='0' dy='0' button='0'/></mouseevent>
```

- `dx`/`dy` = imleci kaydırma miktarı (trackpad gibi). Yavaş hareket küçük, hızlı hareket büyük delta üretir.
- Resmi uygulama her hareket için **ayrı bir HTTP POST** (ve ayrı TCP bağlantısı) açıyor; bizimki de aynı.

### 3.6. Tuş kodları tablosu

| Kod  | İşlev            | Kod  | İşlev               | Kod  | İşlev                    |
|------|------------------|------|---------------------|------|--------------------------|
| 1000–1009 | Rakam 0–9   | 1024 | Stop                | 1052 | Mavi (Blue)              |
| 1010 | Geri (Back)      | 1025 | Play                | 1053 | OK                       |
| 1011 | Aspect           | 1027 | Geri sarma (RW)     | 1054 | Yeşil (Green)            |
| 1012 | Güç (Power)      | 1028 | İleri sarma (FF)    | 1055 | Kırmızı (Red)            |
| 1013 | Sessiz (Mute)    | 1031 | Altyazı (Subtitle)  | 1056 | Kaynak (Source)          |
| 1015 | Dil (Lang)       | 1037 | Kapat (Close)       | 1057 | Mirror                   |
| 1016 | Ses + (Vol+)     | 1040 | Favori (Fav)        | 1058 | Teletext                 |
| 1017 | Ses − (Vol−)     | 1047 | EPG                 | 1062 | YouTube                  |
| 1018 | Info             | 1048 | Menü / Home         | 1063 | Ana ekran (Mainscreen)   |
| 1019 | Aşağı (Down)     | 1049 | Duraklat (Pause)    | 1064 | Netflix                  |
| 1020 | Yukarı (Up)      | 1050 | Sarı (Yellow)       | 1065 | Tarayıcı (Browser)       |
| 1021 | Sol (Left)       | 1051 | Kayıt (Rec)         | 1066 | Ayarlar (Settings)       |
| 1022 | Sağ (Right)      |      |                     | 1067 | Ambilight                |
|      |                  |      |                     | 1068 | Çoklu görünüm (Multiview)|
| 1070/1071/1072 | Sanal kumanda varyantları | | |  1073 | Rakuten TV               |

---

## 4. Uygulama Özellikleri

- **Keşif:** Açılışta otomatik tarama; bulunamazsa belirgin **"Tekrar tara"** butonu; ayrıca **manuel IP** girişi.
- **Tam tuş seti:** güç, kaynak, sessiz, yön tuşları + OK, ses, geri/home, medya kontrolleri (play/pause/stop/ileri/geri/kayıt), renk tuşları, info/altyazı/EPG/favori/menü/aspect/teletext/dil.
- **D-pad basılı tut (auto-repeat):** Yön tuşlarını basılı tutunca tekrar gönderir (önce 0.4 sn bekler, sonra her 0.12 sn'de bir) — `HoldButton` bileşeni.
- **Tarayıcı klavyesi:** Ekrandaki metin kutusundan TV tarayıcısına yazı yazma.
- **Uygulama kısayolları:** Netflix, YouTube, Prime, Browser, Rakuten, Settings.
- **Touchpad (fare modu):** Tam ekran sayfa; **sürükle = imleç**, **dokun = tıkla**. Hareket ~30 Hz'e kısılır.
- **Kalıcı hassasiyet kaydırıcısı:** 0.4×–4.0×, `@AppStorage` ile cihazda saklanır — bir kez ayarla, kalıcı.
- **Klavye kapanması:** "Bitti" butonu + kaydırınca kapanma + herhangi bir kumanda tuşuna basınca otomatik kapanma.
- **Düzen:** Esnek genişlikli butonlar, her ekran boyutuna sığar; TV bağlı değilken kontroller pasif.

---

## 5. Derleme ve Çalıştırma (Mac'siz Runbook)

### 5.1. Zincir

- **xtool** (github.com/xtool-org/xtool) — Xcode yerine geçen çapraz platform araç, Docker `swift` container'ında çalışır.
- **Xcode `.xip`** içinden çıkarılan **Swift SDK** (adı genelde `darwin`).
- **LiveContainer** (github.com/LiveContainer/LiveContainer) — IPA'yı imzasız/JIT ile çalıştırır; kod imzalama gerektirmez.

### 5.2. Container'ı başlatma

`Xcode_16.3.xip` ve xtool AppImage'i host'ta `~/ios` klasörüne koy (container içinde `/work` olur).

```bash
docker run -it --privileged --name xtool-build \
  -v "$HOME/ios":/work \
  -e APPIMAGE_EXTRACT_AND_RUN=1 \
  -e XTL_TMPDIR=/work/tmp \
  -e TMPDIR=/work/tmp \
  swift:6.1 /bin/bash
```

> **Önemli:** SDK'nın Swift sürümü ile container'ın derleyici sürümü **eşleşmeli**. SDK Swift 6.1 ise container `swift:6.1` olmalı. `docker run` ≠ `docker start` — var olan container'a yeni mount eklenemez.

### 5.3. Container içinde ortam değişkenleri ve kurulum

```bash
mkdir -p /work/tmp
export APPIMAGE_EXTRACT_AND_RUN=1
export XTL_TMPDIR=/work/tmp
export TMPDIR=/work/tmp
apt-get update && apt-get install -y zip     # IPA paketleme için gerekli

# xtool kurulumu / SDK çıkarma (xip yolu /work içinde):
#   xtool setup ile Xcode_16.3.xip -> Swift SDK
#   giriş için: 1 numaralı seçenek (Parola / ücretsiz Apple ID), 0 (ücretli API key) DEĞİL
swift sdk list        # "darwin" SDK'sını doğrula
```

### 5.4. Derleme ve IPA

```bash
cd /work/VestelRemote
xtool dev build --ipa
find /work/VestelRemote -name '*.ipa'
```

`/work` host'a bağlı olduğu için IPA aynı anda `~/ios/VestelRemote/...` altında da görünür — `docker cp` gerekmez.

### 5.5. Telefona aktarma ve çalıştırma

1. IPA'yı telefona geçir (bulut / `python3 -m http.server` / kendine mail).
2. **LiveContainer**'da sağ üstteki **+** ile IPA'yı seç, çalıştır.
3. iOS **Ayarlar → LiveContainer → Local Network** iznini aç (izinler host = LiveContainer seviyesinde uygulanır).

### 5.6. Gerekli Info.plist anahtarları

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` → `["_http._tcp"]`
- `NSAppTransportSecurity` → `NSAllowsLocalNetworking = true`

> Not: Yerel ağ/UDP'nin gerçek kapı bekçisi **kod imzası değil, iOS "Local Network" iznidir**. Ham `recvfrom` izin sormaz; bir **Bonjour taraması (NWBrowser)** izin penceresini tetikler — bu yüzden uygulama açılışta kısa bir Bonjour taraması yapıyor.

### 5.7. Kaynak dosyayı güncelleme

Üretilen `Sources/VestelRemote/VestelRemoteApp.swift` içeriğini `VestelRemote.swift` ile değiştir (üretilen `ContentView.swift`'i sil; tek bir `@main` kalsın).

---

## 6. Karşılaşılan Sorunlar ve Çözümleri (Debugging Log)

Bu zinciri ayağa kaldırmak işin en kırılgan tarafıydı. Sırayla çözülenler:

| # | Belirti | Çözüm |
|---|---------|-------|
| 1 | Docker'da AppImage **FUSE** hatası | `export APPIMAGE_EXTRACT_AND_RUN=1` |
| 2 | xtool yanlış giriş yöntemi | Girişte **1** (Parola / ücretsiz Apple ID), 0 (ücretli) değil |
| 3 | unxip için **disk/temp yetersiz** | Host dizini mount + `XTL_TMPDIR=/work/tmp`, `TMPDIR=/work/tmp` |
| 4 | `-v ios/` göreli yol hatası | Mutlak yol: `-v "$HOME/ios":/work`; `docker run` ≠ `docker start` |
| 5 | Çıkarma **%55'te ölüyor** | **OOM** (kernel swift-frontend'i öldürüyordu, VM ~2GB) → swap/RAM ekle |
| 6 | "this SDK is not supported by the compiler" | SDK (6.1) ≠ container (6.3.2) → container'ı **`swift:6.1`**'e sabitle |
| 7 | `overlapping accesses to 'addr'` (exclusivity) | `let saLen = socklen_t(addr.sa_len)` satırını `withUnsafePointer`'dan **önce** al |
| 8 | `init(cString:)` deprecated uyarısı | `String(decoding: host[..<len].map { UInt8(bitPattern: $0) }, as: UTF8.self)` |
| 9 | `var len` uyarısı | `let len` |
| 10 | "Could not find executable 'zip'" | `apt-get install -y zip` |

Sonuç: `Build complete!` → LiveContainer'da çalışan uygulama.

---

## 7. Bilinen Sınırlar

- **Keşif kaba kuvvet:** `en0`'ın /24'ünde 56789 portunu tarar. Çalışır ama **farklı subnet/VLAN'daki TV'yi bulamaz** ve biraz yavaş olabilir. Daha temizi mDNS/SSDP olurdu; ancak sideload'da **multicast entitlement** (`com.apple.developer.networking.multicast`, sadece Apple onaylı) SSDP/broadcast'i engellediği için bilinçli olarak unicast taramayı seçtik.
- **Geri bildirim yok:** Komutlar "gönder-unut". TV kapalıysa veya IP yanlışsa **sessizce başarısız** olur; nabız/durum kontrolü yok.
- **Fare gecikmesi:** Her hareket ayrı bir HTTP POST olduğu için doğası gereği gecikmeye açık (resmi uygulamanın "fare takılıyor" şikâyetleri de aynı sebepten).
- **YouTube'da klavye çalışmaz:** YouTube ayrı, sandbox'lı bir uygulama olarak (Cobalt benzeri runtime) çalışır ve yalnızca **tuş kodlarını** alır, klavye/IME enjeksiyonunu değil. Bu, TV'nin kendi mimarisinden gelen, bizim çözemeyeceğimiz gerçek bir sınır.
- **App Store uygulaması değil:** Çalışması **LiveContainer**'a ve "Local Network" izninin açık kalmasına bağlı. Kişisel kullanım için sorun değil.

---

## 8. Gelecek Fikirleri / Yol Haritası

Hepsi opsiyonel; çekirdek iş bitti, bunlar cila ve genişleme.

**Küçük / hızlı:**
- [ ] **Son TV IP'sini `@AppStorage`'a kaydet**, açılışta taramayı atla (bağlanamazsa taramaya düş).
- [ ] **Ses tuşlarına basılı-tut** ekle (`HoldButton` hazır, sadece sarmak yeterli).
- [ ] **Rakam tuş takımı** (kodlar 1000–1009).
- [ ] Touchpad'de **sağ tık / uzun bas** ve **iki parmak kaydırma** (scroll) jestleri.
- [ ] Basit **bağlantı/nabız göstergesi** (TV erişilebilir mi).

**Orta / daha etkili:**
- [ ] **İki yönlü iletişim:** Resmi uygulamanın açılışta yaptığı **durum/EPG sorgularını** tcpdump ile yakala → TV'den **geri bilgi** çek (açık mı, kaynak, ses seviyesi, kanal). Kumandayı tek yönlü "gönder-unut"tan, gerçek durumları gösteren iki yönlü bir arayüze çevirir.
- [ ] **WebSocket kanalı** araştırması: Bu TV'ler HTTP'nin yanında bir WebSocket kanalı da açıyor — daha düşük gecikmeli fare/telemetri için incelenebilir.
- [ ] **Daha iyi keşif:** Birden fazla TV bulunduğunda seçtirme, daha hızlı tarama, sonucu önbelleğe alma.
- [ ] (Kırılgan, opsiyonel) **YouTube için D-pad otomatik yazıcı:** Metni, YouTube'un harf ızgarasında ok+OK hareketlerine çevirmek. Klavye düzeni/imleç konumu varsayımına dayandığı için kırılgan.

---

## 9. Dosyalar

- **`VestelRemote.swift`** — Tek dosyalık SwiftUI uygulaması (~493 satır). İçeriği `Sources/VestelRemote/VestelRemoteApp.swift`'e konur.
  - `VestelTV` — `@MainActor ObservableObject`: komut gönderme (`key`, `char`, `type`, `openApp`, `mouse`, `click`), keşif (`discover`), Local Network izni tetikleme.
  - `VKey` — tüm tuş kodları enum'u.
  - `HoldButton` — basılı tut / auto-repeat bileşeni.
  - `TrackpadView` — tam ekran touchpad + kalıcı hassasiyet kaydırıcısı.
  - `ContentView` — ana kumanda arayüzü.

---

## 10. Ayarlanabilir Parametreler (Hızlı Referans)

| Ne | Nerede | Varsayılan |
|----|--------|------------|
| Fare hassasiyeti | Touchpad'deki kaydırıcı (kalıcı) | 1.3× (aralık 0.4–4.0) |
| Fare gönderim sıklığı | `TrackpadView` → `sendInterval` | 0.033 sn (~30 Hz) |
| D-pad ilk tekrar gecikmesi | `HoldButton` → ilk `Task.sleep` | 0.4 sn |
| D-pad tekrar aralığı | `HoldButton` → ikinci `Task.sleep` | 0.12 sn |
| Tarama eşzamanlılığı | `discover` → `maxInFlight` | 40 |
| Host tarama zaman aşımı | `portOpen` çağrısı | 0.8 sn |

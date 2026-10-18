# Cleaner App: Tasarım Spec'i (v1 = Smart Tarama)

## Amaç
Mac diskinde yeniden üretilebilir veya gereksiz dosyaları tespit edip, kullanıcı onayıyla güvenle (Çöp Kutusu'na) taşıyarak alan açan, kişisel kullanım için native bir macOS uygulaması.

## Kapsam dilimleri
- **v1 (bu spec):** Smart tarama, öneri panosu, güvenli silme, esnek AI ayarları.
- **v2:** Finder benzeri manuel mod, bu modda AI önerileri.
- **v3:** Docker/Podman image temizliği, "gereksiz" işaretlerini kural olarak saklama (öğrenme hafızası), `Application Support` derin analizi.

v1 dışındakiler bu spec'in kapsamı değildir.

## Kullanıcı hikâyesi
Kullanıcı uygulamayı açar, "Tara" der. Uygulama kategoriler halinde önerileri tahmini kazançla ve güven seviyesiyle gösterir. Kullanıcı seçer, dry-run önizlemesini görür, onaylar. Seçilenler Çöp Kutusu'na taşınır ve kazanılan alan raporlanır.

## Teknoloji ve ortam
- SwiftUI, Swift 6.2, macOS 26 hedefi, Xcode 26.3.
- Sandbox kapalı, kullanıcı Full Disk Access verir (App Store hedefi yok).
- Swift Package modülleri + SwiftUI app target.

## Modüller
| Modül | Sorumluluk | Bağımlılık |
|---|---|---|
| `CleanerCore` | `Finding` (path, size, category, confidence, reason, safety), `Category`, `Confidence` | yok |
| `DiskScanner` | İptal edilebilir dizin boyutu hesabı (`Scanner` adı Foundation ile çakışır) | CleanerCore |
| `Rules` | `Rule` protokolü; her kural `[Finding]` üretir | DiskScanner, Safety, CleanerCore |
| `Safety` | İzinli kökler, korunan yollar; silmeden önce zorunlu geçit | CleanerCore |
| `AI` | `AIProvider` protokolü, `AnthropicProvider`, `OpenAICompatibleProvider`, metadata redaksiyonu, JSON çıktı doğrulama | CleanerCore |
| `Preferences` | Provider profilleri, Keychain sarmalayıcı, taranacak kökler, hariç tutma listesi (`Settings` adı SwiftUI ile çakışır) | yok |
| `Cleaning` | `NSWorkspace.recycle` ile Çöp Kutusu'na taşıma, dry-run, sonuç raporu | Safety |
| `AppModel` | Test edilebilir `ScanViewModel` (tarama, seçim, AI, temizleme akışı) | hepsi |
| `CleanerApp` | Yalnızca SwiftUI görünümleri (pano, onay sheet'i, Settings penceresi) | AppModel |

## v1 kuralları (Rules)
- Kullanıcı cache'leri: `~/Library/Caches`
- Loglar: `~/Library/Logs`
- Homebrew cache: `brew --cache` çıktısı
- Xcode: DerivedData ve kullanılmayan simulator'lar
- Geliştirici artifact'ları, yalnızca yanında manifest varsa:
  - `node_modules` (`package.json`)
  - `target/` (`pom.xml`)
  - `build/` ve `.gradle` (`build.gradle`)
  - `venv`, `.venv`, `__pycache__` (`requirements.txt` veya `pyproject.toml`)

Not: Çöp Kutusu içeriği v1 kurallarında yoktur. Zaten Çöp Kutusu'ndaki bir öğeyi "Çöp Kutusu'na taşımak" anlamsızdır ve kalıcı silme v1 kapsamı dışındadır. Rapor, alanın gerçekte Çöp Kutusu boşaltılınca açılacağını kullanıcıya söyler ve Çöp Kutusu'nu Finder'da açan bir buton sunar.

## AI katmanı
- `AIProvider` protokolü, belirsiz `Finding`'leri puanlar ve gerekçe ekler; yapılandırılmış JSON döner.
- Üç adaptör:
  - `AnthropicProvider`
  - `OpenAICompatibleProvider` (Azure, LiteLLM, Ollama, LM Studio ve OpenAI uyumlu şirket agent'ları)
  - `CustomHTTPProvider`: şirket içi LLM platformları gibi, ne Anthropic ne OpenAI şemasına uyan servisler için.
- `CustomHTTPProvider` tamamen ayardan yapılandırılır, kod değişikliği gerektirmez:
  - host ve endpoint path
  - auth biçimi: header adı + şema (`Bearer`, `x-api-key`, özel header) veya query parametresi
  - ekstra header'lar
  - istek gövdesi şablonu (`{{model}}`, `{{system}}`, `{{prompt}}` yer tutucuları)
  - yanıttan metni çıkaran JSON yolu (ör. `choices.0.message.content`)
  - zaman aşımı
- Settings alanları: provider tipi, host / base URL, model, ekstra header'lar, API key (ve `CustomHTTPProvider` için yukarıdakiler). API key macOS Keychain'de saklanır.
- Yapılandırmalar profil olarak kaydedilir (ör. "Şirket LLM", "Claude"); kullanıcı aralarında geçiş yapabilir.
- "Bağlantıyı test et" butonu bulunur.
- AI'a yalnızca metadata gider: yol, boyut, tarih, klasör türü. Dosya içeriği gitmez. Gönderilecek veri önizlenir ve kullanıcı onaylar.
- AI kapalı veya erişilemezse sistem kural-only moda düşer, hata kullanıcıya kısa uyarıyla gösterilir.

## Veri akışı
Scan → Rules → `[Finding]` → (opsiyonel) AI puanlama → pano → kullanıcı seçimi → dry-run önizleme → Safety kontrolü → Çöp Kutusu'na taşıma → rapor.

## Güvenlik kuralları
- Silme yalnızca `Safety` geçidinden geçer; geçmeyen yol reddedilir.
- Ev dizini kökleri ve sistem yolları hiçbir zaman önerilmez.
- Yakın zamanda değiştirilmiş projeler düşük güvenle işaretlenir.
- Varsayılan silme Çöp Kutusu'na taşıma, kalıcı silme yoktur (v1).

## Hata yönetimi
- Eksik izin: Full Disk Access yönlendirmesi gösterilir.
- Tek yolda silme hatası tüm işlemi durdurmaz; rapora yazılır.
- Tarama kullanıcı tarafından iptal edilebilir.

## Test stratejisi
- Her kural için geçici dizin fixture'larıyla birim testi.
- `Safety` reddetme testleri (sistem yolları, ev kökü, korunan yollar).
- AI JSON ayrıştırma ve hata dönüşleri için mock provider testleri.
- Elle uçtan uca: gerçek home taraması, `du -sh` ile boyut karşılaştırması, test klasörünün Çöp Kutusu'na taşınıp geri alınabilmesi.
- AI bağlantı testi hem Anthropic hem OpenAI uyumlu endpoint (ör. yerel Ollama) ile yapılır.

## Kapsam dışı (v1)
Manuel gezgin, Docker/Podman, öğrenme hafızası, `Application Support` analizi, kalıcı silme, App Store dağıtımı.

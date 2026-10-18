# Breezy (Cleaner App)

Kişisel macOS temizleyici (uygulama adı Breezy, SwiftPM paketi/modülleri `Cleaner*`): gereksiz dosyaları bulur, onayla Çöp Kutusu'na taşır.
Spec: `docs/superpowers/specs/2026-10-18-cleaner-app-design.md` (tek doğruluk kaynağı).

## Stack
SwiftUI, Swift 6.2, macOS 26, Xcode 26.3. Swift Package modülleri + app target. Sandbox kapalı.

## Modüller (Sources/)
CleanerCore, DiskScanner, Rules, Safety, AI, Preferences, Cleaning, AppModel, CleanerApp (yalnızca görünümler). Testler: `Tests/<Modül>Tests`, ortak yardımcılar `Sources/TestSupport`. Plan: `docs/superpowers/plans/`.

## Komutlar
- Derle: `swift build -q`
- Test: `swift test -q`
- Tek test: `swift test -q --filter <TestAdı>`
- Paketle: `scripts/make-app.sh` → evrensel `build/Breezy.app` (ad-hoc imza; her yeniden derlemede Tam Disk Erişimi tekrar istenebilir)

## Kurallar
- Silme yalnızca `Safety` geçidinden geçer. Kalıcı silme yok, `NSWorkspace.recycle` kullan.
- AI'a yalnızca metadata gider (yol, boyut, tarih, klasör türü), dosya içeriği asla.
- API key yalnızca Keychain'de. Loga, teste, fixture'a yazma.
- Yeni kural = yeni `Rule` + fixture'lı birim testi. Önce test yaz.
- Mevcut kod stilini ve isimlendirmeyi koru. Gereksiz soyutlama, yorum, refactor ekleme.
- Ağ koduna yalnızca `AI` modülünde izin var (`URLSessionHTTPClient`); başka modüle ağ, telemetri, analitik ekleme.
- Yeni `Rule`: `categories`, `impact` (geri gelme/risk/not) ve gerekirse `KnownApps` girdisi ver. Geri gelmeyen, kullanıcı verisi ve büyük öğeler asla önceden seçilmez; AI etkiyi yalnızca kötüleştirebilir, güveni kuralın en fazla +1 üstüne çıkarır.
- Kapsam dışı: manuel gezgin (v2), Docker/Podman, öğrenme hafızası, Application Support analizi (v3).

## Çıktı ve token tasarrufu
- Cevaplar kısa olsun: ne değişti, nerede, sonraki adım. Kodu tekrar yazma, diff'i anlatma.
- Dosyanın tamamını okuma; `offset/limit` veya arama kullan.
- Derleme/test çıktısını `-q` ile al, uzunsa yalnızca hata satırlarını incele.
- `.build/`, `DerivedData/` içine bakma.
- Bu dosyayı kararlı tut: sık değiştirmek prompt cache'i bozar. Oturum içi geçici notları buraya yazma.

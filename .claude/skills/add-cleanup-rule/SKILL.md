---
name: add-cleanup-rule
description: Use when adding a new cleanup rule (a new category of removable files/dirs) to the Rules module, such as a new cache, build artifact, or log location.
---

# Yeni temizlik kuralı ekle

1. Kuralın ne bulduğunu ve güvenli olma koşulunu tek cümleyle yaz (ör. "`target/`, yanında `pom.xml` varsa").
2. `Tests/RulesTests/` altında fixture'lı test yaz: geçici dizinde hem eşleşen hem eşleşmeyen yapı kur. Testin kırmızı olduğunu doğrula.
3. `Sources/Rules/` altında `Rule` protokolünü uygulayan tek dosyalık kural ekle. Mevcut bir kuralı örnek al, yapısını kopyala.
4. `Finding` alanlarını doldur: `category`, `confidence` (manifest yoksa veya yakın zamanda değiştiyse düşür), `reason` (tek kısa cümle) ve `impact` (geri gelme: kendiliğinden/komutla/geri gelmez, risk, "silersen ne olur" notu). Kuralda `categories` tanımla (kategori bazlı tarama için). Önbellek klasörü adından tanınan uygulamalar için `KnownApps`'e girdi ekle.
5. Kuralı kayıt listesine ekle. Safety listesine dokunma; yeni yol sistem/ev köküne denk geliyorsa kuralı reddet.
6. `swift test -q --filter <KuralTesti>` ile yeşili doğrula, sonra tüm `swift test -q`.

Yapma: dosya içeriği okuma, kalıcı silme eklemek, kapsam dışı özellik, geri gelmeyen/kullanıcı verisi öğeyi varsayılan seçili yapmak.

## Çıktı kuralı (gereksiz çıktı üretme)
- Yalnızca istenen çıktıyı ver: ne değişti, nerede, sonraki adım. Giriş/özet/tekrar paragrafı, kodu yeniden yazma, diff anlatma, "şunu da yapabilirim" listesi yok.
- Dosyayı/çıktıyı bütün okuma: önce arama, `offset/limit`, `-q`; uzun çıktıda yalnızca hata satırları.
- Zaten bilinen bilgiyi (önceki mesaj, AGENTS.md, ledger) tekrar yazma veya yeniden türetme.
- Tek cümleyle cevaplanabilen soruya tek cümleyle cevap ver.

---
name: add-cleanup-rule
description: Use when adding a new cleanup rule (a new category of removable files/dirs) to the Rules module, such as a new cache, build artifact, or log location.
---

# Yeni temizlik kuralı ekle

1. Kuralın ne bulduğunu ve güvenli olma koşulunu tek cümleyle yaz (ör. "`target/`, yanında `pom.xml` varsa").
2. `Tests/RulesTests/` altında fixture'lı test yaz: geçici dizinde hem eşleşen hem eşleşmeyen yapı kur. Testin kırmızı olduğunu doğrula.
3. `Sources/Rules/` altında `Rule` protokolünü uygulayan tek dosyalık kural ekle. Mevcut bir kuralı örnek al, yapısını kopyala.
4. `Finding` alanlarını doldur: `category`, `confidence` (manifest yoksa veya yakın zamanda değiştiyse düşür), `reason` (tek kısa cümle).
5. Kuralı kayıt listesine ekle. Safety listesine dokunma; yeni yol sistem/ev köküne denk geliyorsa kuralı reddet.
6. `swift test -q --filter <KuralTesti>` ile yeşili doğrula, sonra tüm `swift test -q`.

Yapma: dosya içeriği okuma, kalıcı silme eklemek, kapsam dışı (v1) özellik.

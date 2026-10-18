---
name: add-ai-provider
description: Use when adding or changing an AI provider adapter or its settings (AIProvider protocol, Anthropic, OpenAI-compatible, CustomHTTP) in the AI module.
---

# AI provider ekle/değiştir

- Tüm adaptörler `AIProvider` protokolünü uygular; yeni servis için önce `CustomHTTPProvider` yapılandırmasının (host, path, auth, gövde şablonu, yanıt JSON yolu) yetip yetmediğine bak. Yetiyorsa kod ekleme.
- Gönderilen veri yalnızca metadata: `~` ile gizlenmiş yol, boyut, yaş, klasör türü, kuralın güven/gerekçe/etki bilgisi (`AIPrompt`). İstek başına en fazla `AIPrompt.maxItems` (40) öğe. Redaksiyon `AI` modülünde tek yerde yapılır; atlama.
- Yanıtı yapılandırılmış JSON olarak doğrula; bozuksa hata döndür, kural-only moda düş.
- API key sadece Keychain sarmalayıcısıyla okunur/yazılır. Test ve loglarda gösterme.
- Anthropic adaptöründe sabit sistem prompt'una `cache_control` ekle (prompt caching), değişen kısım sona gelsin.
- Test: mock HTTP ile başarı, bozuk JSON, zaman aşımı, 401. Ardından `swift test -q --filter AITests`.

## Çıktı kuralı (gereksiz çıktı üretme)
- Yalnızca istenen çıktıyı ver: ne değişti, nerede, sonraki adım. Giriş/özet/tekrar paragrafı, kodu yeniden yazma, diff anlatma, "şunu da yapabilirim" listesi yok.
- Dosyayı/çıktıyı bütün okuma: önce arama, `offset/limit`, `-q`; uzun çıktıda yalnızca hata satırları.
- Zaten bilinen bilgiyi (önceki mesaj, AGENTS.md, ledger) tekrar yazma veya yeniden türetme.
- Tek cümleyle cevaplanabilen soruya tek cümleyle cevap ver.

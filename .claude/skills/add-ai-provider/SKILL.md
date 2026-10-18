---
name: add-ai-provider
description: Use when adding or changing an AI provider adapter or its settings (AIProvider protocol, Anthropic, OpenAI-compatible, CustomHTTP) in the AI module.
---

# AI provider ekle/değiştir

- Tüm adaptörler `AIProvider` protokolünü uygular; yeni servis için önce `CustomHTTPProvider` yapılandırmasının (host, path, auth, gövde şablonu, yanıt JSON yolu) yetip yetmediğine bak. Yetiyorsa kod ekleme.
- Gönderilen veri yalnızca metadata: yol, boyut, tarih, klasör türü. Redaksiyon `AI` modülünde tek yerde yapılır; atlama.
- Yanıtı yapılandırılmış JSON olarak doğrula; bozuksa hata döndür, kural-only moda düş.
- API key sadece Keychain sarmalayıcısıyla okunur/yazılır. Test ve loglarda gösterme.
- Anthropic adaptöründe sabit sistem prompt'una `cache_control` ekle (prompt caching), değişen kısım sona gelsin.
- Test: mock HTTP ile başarı, bozuk JSON, zaman aşımı, 401. Ardından `swift test -q --filter AITests`.

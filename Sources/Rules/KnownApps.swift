import Foundation
import CleanerCore

/// Önbellek klasörü adından uygulamayı tanıyıp silmenin etkisini bilinen bir notla verir.
enum KnownApps {
    private struct Entry {
        let needle: String
        let impact: Impact
    }

    private static func e(_ needle: String, _ r: Regeneration, _ k: Risk, _ note: String) -> Entry {
        Entry(needle: needle, impact: Impact(regeneration: r, risk: k, note: note))
    }

    private static let entries: [Entry] = [
        e("JetBrains", .automatic, .low,
          "IDE indekslerini ve önbelleğini ilk açılışta yeniden oluşturur; büyük projelerde birkaç dakika yavaş açılır. Ayarlar ve lisans etkilenmez."),
        e("Google", .automatic, .low,
          "Tarayıcı site verilerini yeniden indirir; sayfalar ilk ziyarette yavaş yüklenir. Parola ve oturumlar etkilenmez."),
        e("com.apple.Safari", .automatic, .low,
          "Site önbelleği yeniden dolar; sayfalar ilk ziyarette yavaş yüklenir."),
        e("Firefox", .automatic, .low,
          "Site önbelleği yeniden dolar; sayfalar ilk ziyarette yavaş yüklenir."),
        e("Spotify", .automatic, .medium,
          "Çevrimdışı indirilen şarkılar da silinebilir; yeniden indirmen gerekir."),
        e("Slack", .automatic, .low, "Medya ve çalışma alanı önbelleği yeniden iner; oturum açık kalır."),
        e("discord", .automatic, .low, "Medya önbelleği yeniden iner; oturum açık kalır."),
        e("com.apple.dt.Xcode", .automatic, .low, "Xcode indekslerini yeniden oluşturur; ilk açılışta yavaşlık olur."),
        e("CocoaPods", .manual, .low, "`pod install` paketleri yeniden indirir; çevrimdışıyken derleme başarısız olabilir."),
        e("org.swift.swiftpm", .manual, .low, "Swift paketleri ilk derlemede yeniden iner; çevrimdışıyken derleme başarısız olabilir."),
        e("go-build", .automatic, .low, "Go derleme önbelleği; sonraki derleme ilk seferde uzun sürer."),
        e("pip", .manual, .low, "Python paketleri bir sonraki kurulumda yeniden indirilir."),
        e("Yarn", .manual, .low, "Paketler bir sonraki kurulumda yeniden indirilir."),
        e("pnpm", .manual, .low, "Paketler bir sonraki kurulumda yeniden indirilir."),
        e("npm", .manual, .low, "Paketler bir sonraki kurulumda yeniden indirilir."),
        e("ms-playwright", .manual, .medium,
          "Test tarayıcıları `npx playwright install` ile yeniden indirilmeli; o zamana kadar UI testleri çalışmaz."),
    ]

    static func impact(forCacheNamed name: String) -> Impact? {
        entries.first { name.localizedCaseInsensitiveContains($0.needle) }?.impact
    }
}

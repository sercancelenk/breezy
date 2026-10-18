import Foundation

enum JSONPathLite {
    static func extract(_ path: String, from data: Data) throws -> String {
        guard var node = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            throw AIError.badResponse("Yanıt JSON değil")
        }
        for part in path.split(separator: ".").map(String.init) {
            if let i = Int(part), let arr = node as? [Any], arr.indices.contains(i) {
                node = arr[i]
            } else if let dict = node as? [String: Any], let v = dict[part] {
                node = v
            } else {
                throw AIError.badResponse("Yanıtta '\(path)' yolu bulunamadı")
            }
        }
        if let s = node as? String { return s }
        if node is NSNumber { return "\(node)" }
        throw AIError.badResponse("'\(path)' metin değil")
    }
}

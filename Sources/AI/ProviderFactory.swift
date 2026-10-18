import Foundation
import Preferences

public enum ProviderFactory {
    public static func make(profile: ProviderProfile, apiKey: String,
                            http: any HTTPClient = URLSessionHTTPClient()) -> any AIProvider {
        switch profile.kind {
        case .anthropic: AnthropicProvider(profile: profile, apiKey: apiKey, http: http)
        case .openAICompatible: OpenAICompatibleProvider(profile: profile, apiKey: apiKey, http: http)
        case .customHTTP: CustomHTTPProvider(profile: profile, apiKey: apiKey, http: http)
        }
    }
}

import Foundation

/// Languages are passed around as lowercase codes (`it`, `en`, `fr`, `pt-br`…).
enum Language {
    /// The language's English name, used in the instructions to the model ("Italian", "French"…).
    static func name(_ code: String) -> String {
        let english = Locale(identifier: "en")
        return english.localizedString(forIdentifier: code)
            ?? english.localizedString(forLanguageCode: code)
            ?? code
    }

    /// A valid language code in lowercase, or `nil` (`auto`, empty, or not a language).
    static func code(_ value: String) -> String? {
        let code = value.trimmingCharacters(in: .whitespaces).lowercased()
        guard code.wholeMatch(of: /[a-z]{2,3}(-[a-z0-9]{2,8})?/) != nil,
              Locale(identifier: "en").localizedString(forLanguageCode: code) != nil
        else { return nil }
        return code
    }
}

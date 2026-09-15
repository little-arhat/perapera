import AppKit
import PeraperaCore

/// The dictionary one click away, for what the bundled slice does not carry:
/// readings, every sense, inflections and example sentences.
enum JapanDict {
    static func url(for word: String) -> URL? {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = Furigana.stripped(word)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return URL(string: "https://www.japandict.com/?s=\(encoded)&lang=eng")
    }

    @MainActor
    static func open(_ word: String) {
        if let url = url(for: word) { NSWorkspace.shared.open(url) }
    }
}

import Foundation

// MARK: - Language

/// A user-facing language option exposed by the Settings → Language screen and
/// by the Composer language picker.
///
/// `code` is a BCP-47 language tag (e.g. `"en"`, `"pt-BR"`, `"zh-Hans-CN"`).
/// `name` is a human-readable label shown to the user. The label is
/// pre-localized on the value (matching RN's static `APP_LANGUAGES` /
/// `LANGUAGES` lists in `Bluesky-ReactNative/src/locale/languages.ts`); we do
/// **not** rely on `Locale.localizedString(forLanguageCode:)` for the primary
/// label so the names stay identical between RN and the SwiftUI clients.
public struct Language: Hashable, Sendable, Identifiable, Codable {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }

    public var id: String { code }
}

// MARK: - App languages

/// Languages the **app's user interface** can be displayed in.
///
/// Mirrors RN's `APP_LANGUAGES` array in
/// `Bluesky-ReactNative/src/locale/languages.ts`. Order matches RN exactly so
/// the picker reads identically on both clients (English first, then the rest
/// in alphabetical order by translated name).
///
/// The codes are BCP-47 tags. RN normalizes some codes via
/// `sanitizeAppLanguageSetting` — that function maps unknown / malformed
/// values back to `"en"`. Mirror that behavior in `BlueskyKit` (or wherever
/// this is consumed) before applying the value to a `Locale`.
public enum AppLanguages {
    public static let all: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "an", name: "aragonés – Aragonese"),
        Language(code: "ast", name: "asturianu – Asturian"),
        Language(code: "ca", name: "català – Catalan"),
        Language(code: "cy", name: "Cymraeg – Welsh"),
        Language(code: "da", name: "dansk – Danish"),
        Language(code: "de", name: "Deutsch – German"),
        Language(code: "el", name: "Ελληνικά – Greek"),
        Language(code: "en-GB", name: "British English"),
        Language(code: "eo", name: "Esperanto"),
        Language(code: "es", name: "español – Spanish"),
        Language(code: "eu", name: "euskara – Basque"),
        Language(code: "fi", name: "suomi – Finnish"),
        Language(code: "fr", name: "français – French"),
        Language(code: "fy", name: "Frysk – Western Frisian"),
        Language(code: "ga", name: "Gaeilge – Irish"),
        Language(code: "gd", name: "Gàidhlig – Scottish Gaelic"),
        Language(code: "gl", name: "galego – Galician"),
        Language(code: "hi", name: "हिंदी – Hindi"),
        Language(code: "hu", name: "magyar – Hungarian"),
        Language(code: "ia", name: "Interlingua"),
        Language(code: "id", name: "Bahasa Indonesia – Indonesian"),
        Language(code: "it", name: "italiano – Italian"),
        Language(code: "ja", name: "日本語 – Japanese"),
        Language(code: "km", name: "ភាសាខ្មែរ – Khmer"),
        Language(code: "ko", name: "한국어 – Korean"),
        Language(code: "ne", name: "नेपाली – Nepali"),
        Language(code: "nl", name: "Nederlands – Dutch"),
        Language(code: "pl", name: "polski – Polish"),
        Language(code: "pt-BR", name: "português do Brasil – Brazilian Portuguese"),
        Language(code: "pt-PT", name: "português europeu – European Portuguese"),
        Language(code: "ro", name: "română – Romanian"),
        Language(code: "ru", name: "русский – Russian"),
        Language(code: "sv", name: "svenska – Swedish"),
        Language(code: "th", name: "ภาษาไทย – Thai"),
        Language(code: "tr", name: "Türkçe – Turkish"),
        Language(code: "uk", name: "українська – Ukrainian"),
        Language(code: "vi", name: "Tiếng Việt – Vietnamese"),
        Language(code: "zh-Hans-CN", name: "简体中文 – Simplified Chinese"),
        Language(code: "zh-Hant-TW", name: "繁體中文 – Traditional Chinese"),
        Language(code: "zh-Hant-HK", name: "粵文 – Cantonese"),
    ]

    /// Coerces an arbitrary stored value back to a known `AppLanguages` code.
    /// Mirrors RN's `sanitizeAppLanguageSetting` — anything we don't recognize
    /// falls back to `"en"`.
    public static func sanitize(_ code: String?) -> String {
        guard let code else { return "en" }
        if all.contains(where: { $0.code == code }) { return code }
        return "en"
    }
}

// MARK: - Content languages

/// Languages the user can mark as the primary language of their posts and the
/// languages they want to see in their feeds.
///
/// Mirrors the **deduped** subset of RN's `LANGUAGES` table — the subset where
/// each entry has a non-empty ISO 639-1 `code2`. RN does the same dedup at
/// the call site (`DEDUPED_LANGUAGES` in `LanguageSettings.tsx`); we
/// pre-compute the same list here so the picker order is stable on both
/// clients. Names match RN's `LANGUAGES` table verbatim.
///
/// This list is used by:
/// - **Primary post language** — single-select picker.
/// - **Content languages** — multi-select picker. Pinning a post in a
///   language not on this list is impossible from the UI; users who want
///   exotic codes can still type them via XRPC manually, matching RN's
///   constraint.
public enum ContentLanguages {
    public static let all: [Language] = [
        Language(code: "aa", name: "Afar"),
        Language(code: "ab", name: "Abkhazian"),
        Language(code: "af", name: "Afrikaans"),
        Language(code: "ak", name: "Akan"),
        Language(code: "am", name: "Amharic"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "an", name: "Aragonese"),
        Language(code: "as", name: "Assamese"),
        Language(code: "av", name: "Avaric"),
        Language(code: "ae", name: "Avestan"),
        Language(code: "ay", name: "Aymara"),
        Language(code: "az", name: "Azerbaijani"),
        Language(code: "ba", name: "Bashkir"),
        Language(code: "bm", name: "Bambara"),
        Language(code: "eu", name: "Basque"),
        Language(code: "be", name: "Belarusian"),
        Language(code: "bn", name: "Bangla"),
        Language(code: "bh", name: "Bhojpuri"),
        Language(code: "bi", name: "Bislama"),
        Language(code: "bs", name: "Bosnian"),
        Language(code: "br", name: "Breton"),
        Language(code: "bg", name: "Bulgarian"),
        Language(code: "my", name: "Burmese"),
        Language(code: "ca", name: "Catalan"),
        Language(code: "ch", name: "Chamorro"),
        Language(code: "ce", name: "Chechen"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "cu", name: "Church Slavic"),
        Language(code: "cv", name: "Chuvash"),
        Language(code: "kw", name: "Cornish"),
        Language(code: "co", name: "Corsican"),
        Language(code: "cr", name: "Cree"),
        Language(code: "cs", name: "Czech"),
        Language(code: "da", name: "Danish"),
        Language(code: "dv", name: "Divehi"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "dz", name: "Dzongkha"),
        Language(code: "en", name: "English"),
        Language(code: "eo", name: "Esperanto"),
        Language(code: "et", name: "Estonian"),
        Language(code: "ee", name: "Ewe"),
        Language(code: "fo", name: "Faroese"),
        Language(code: "fa", name: "Persian"),
        Language(code: "fj", name: "Fijian"),
        Language(code: "fi", name: "Finnish"),
        Language(code: "fr", name: "French"),
        Language(code: "fy", name: "Western Frisian"),
        Language(code: "ff", name: "Fulah"),
        Language(code: "ka", name: "Georgian"),
        Language(code: "de", name: "German"),
        Language(code: "gd", name: "Scottish Gaelic"),
        Language(code: "ga", name: "Irish"),
        Language(code: "gl", name: "Galician"),
        Language(code: "gv", name: "Manx"),
        Language(code: "el", name: "Greek"),
        Language(code: "gn", name: "Guarani"),
        Language(code: "gu", name: "Gujarati"),
        Language(code: "ht", name: "Haitian Creole"),
        Language(code: "ha", name: "Hausa"),
        Language(code: "he", name: "Hebrew"),
        Language(code: "hz", name: "Herero"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ho", name: "Hiri Motu"),
        Language(code: "hr", name: "Croatian"),
        Language(code: "hu", name: "Hungarian"),
        Language(code: "hy", name: "Armenian"),
        Language(code: "ig", name: "Igbo"),
        Language(code: "is", name: "Icelandic"),
        Language(code: "io", name: "Ido"),
        Language(code: "ii", name: "Sichuan Yi"),
        Language(code: "iu", name: "Inuktitut"),
        Language(code: "ie", name: "Interlingue"),
        Language(code: "ia", name: "Interlingua"),
        Language(code: "id", name: "Indonesian"),
        Language(code: "ik", name: "Inupiaq"),
        Language(code: "it", name: "Italian"),
        Language(code: "jv", name: "Javanese"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "kl", name: "Kalaallisut"),
        Language(code: "kn", name: "Kannada"),
        Language(code: "ks", name: "Kashmiri"),
        Language(code: "kr", name: "Kanuri"),
        Language(code: "kk", name: "Kazakh"),
        Language(code: "km", name: "Khmer"),
        Language(code: "ki", name: "Kikuyu"),
        Language(code: "rw", name: "Kinyarwanda"),
        Language(code: "ky", name: "Kyrgyz"),
        Language(code: "kv", name: "Komi"),
        Language(code: "kg", name: "Kongo"),
        Language(code: "ko", name: "Korean"),
        Language(code: "kj", name: "Kuanyama"),
        Language(code: "ku", name: "Kurdish"),
        Language(code: "lo", name: "Lao"),
        Language(code: "la", name: "Latin"),
        Language(code: "lv", name: "Latvian"),
        Language(code: "li", name: "Limburgish"),
        Language(code: "ln", name: "Lingala"),
        Language(code: "lt", name: "Lithuanian"),
        Language(code: "lb", name: "Luxembourgish"),
        Language(code: "lu", name: "Luba-Katanga"),
        Language(code: "lg", name: "Ganda"),
        Language(code: "mk", name: "Macedonian"),
        Language(code: "mh", name: "Marshallese"),
        Language(code: "ml", name: "Malayalam"),
        Language(code: "mi", name: "Māori"),
        Language(code: "mr", name: "Marathi"),
        Language(code: "ms", name: "Malay"),
        Language(code: "mg", name: "Malagasy"),
        Language(code: "mt", name: "Maltese"),
        Language(code: "mn", name: "Mongolian"),
        Language(code: "na", name: "Nauru"),
        Language(code: "nv", name: "Navajo"),
        Language(code: "nr", name: "South Ndebele"),
        Language(code: "nd", name: "North Ndebele"),
        Language(code: "ng", name: "Ndonga"),
        Language(code: "ne", name: "Nepali"),
        Language(code: "nn", name: "Norwegian Nynorsk"),
        Language(code: "nb", name: "Norwegian Bokmål"),
        Language(code: "no", name: "Norwegian"),
        Language(code: "ny", name: "Nyanja"),
        Language(code: "oc", name: "Occitan"),
        Language(code: "oj", name: "Ojibwa"),
        Language(code: "or", name: "Odia"),
        Language(code: "om", name: "Oromo"),
        Language(code: "os", name: "Ossetic"),
        Language(code: "pa", name: "Punjabi"),
        Language(code: "pi", name: "Pali"),
        Language(code: "pl", name: "Polish"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "ps", name: "Pashto"),
        Language(code: "qu", name: "Quechua"),
        Language(code: "rm", name: "Romansh"),
        Language(code: "ro", name: "Romanian"),
        Language(code: "rn", name: "Rundi"),
        Language(code: "ru", name: "Russian"),
        Language(code: "sg", name: "Sango"),
        Language(code: "sa", name: "Sanskrit"),
        Language(code: "si", name: "Sinhala"),
        Language(code: "sk", name: "Slovak"),
        Language(code: "sl", name: "Slovenian"),
        Language(code: "se", name: "Northern Sami"),
        Language(code: "sm", name: "Samoan"),
        Language(code: "sn", name: "Shona"),
        Language(code: "sd", name: "Sindhi"),
        Language(code: "so", name: "Somali"),
        Language(code: "st", name: "Southern Sotho"),
        Language(code: "es", name: "Spanish"),
        Language(code: "sq", name: "Albanian"),
        Language(code: "sc", name: "Sardinian"),
        Language(code: "sr", name: "Serbian"),
        Language(code: "ss", name: "Swati"),
        Language(code: "su", name: "Sundanese"),
        Language(code: "sw", name: "Swahili"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "ty", name: "Tahitian"),
        Language(code: "ta", name: "Tamil"),
        Language(code: "tt", name: "Tatar"),
        Language(code: "te", name: "Telugu"),
        Language(code: "tg", name: "Tajik"),
        Language(code: "tl", name: "Filipino"),
        Language(code: "th", name: "Thai"),
        Language(code: "bo", name: "Tibetan"),
        Language(code: "ti", name: "Tigrinya"),
        Language(code: "to", name: "Tongan"),
        Language(code: "tn", name: "Tswana"),
        Language(code: "ts", name: "Tsonga"),
        Language(code: "tk", name: "Turkmen"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "tw", name: "Akan"),
        Language(code: "ug", name: "Uyghur"),
        Language(code: "uk", name: "Ukrainian"),
        Language(code: "ur", name: "Urdu"),
        Language(code: "uz", name: "Uzbek"),
        Language(code: "ve", name: "Venda"),
        Language(code: "vi", name: "Vietnamese"),
        Language(code: "vo", name: "Volapük"),
        Language(code: "wa", name: "Walloon"),
        Language(code: "wo", name: "Wolof"),
        Language(code: "xh", name: "Xhosa"),
        Language(code: "yi", name: "Yiddish"),
        Language(code: "yo", name: "Yoruba"),
        Language(code: "za", name: "Zhuang"),
        Language(code: "zu", name: "Zulu"),
    ]

    /// Lookup table keyed by BCP-47 / ISO 639-1 code.
    public static let byCode: [String: Language] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) }
    )

    /// Returns the canonical display name for `code`, or the bare code if
    /// it isn't in our curated list. Mirrors RN's `languageName` helper which
    /// falls back to `code2.toUpperCase()` for unrecognized values; we keep
    /// the raw code so the user sees something stable rather than a localized
    /// fallback that may differ from RN.
    public static func name(for code: String) -> String {
        byCode[code]?.name ?? code
    }
}

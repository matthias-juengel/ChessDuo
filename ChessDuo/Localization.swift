import Foundation

extension String {
    /// Convenience localized string lookup
    static func loc(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        if args.isEmpty { return format }
        return String(format: format, locale: .current, arguments: args)
    }

    /// Format a signed integer delta using semantic keys:
    ///  - delta_positive_format : "+%lld"
    ///  - delta_neutral_format  : "%lld" (zero)
    ///  - delta_negative_format : "-%lld"
    /// Falls back to simple interpolation if keys are missing.
    static func localizedDelta(_ value: Int64) -> String {
        let key: String
        if value > 0 { key = "delta_positive_format" }
        else if value < 0 { key = "delta_negative_format" }
        else { key = "delta_neutral_format" }
        let format = NSLocalizedString(key, comment: "Signed numeric delta format")
        // If lookup failed (returned the key itself), just show a manually formatted value.
        if format == key { return String(format: "%+lld", value) }
        return String(format: format, locale: .current, value)
    }
}

enum AppInfo {
    /// Localized display name from Info.plist (CFBundleDisplayName), falling back to CFBundleName.
    static var displayName: String {
        let bundle = Bundle.main
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, !name.isEmpty {
            return name
        }
        if let fallback = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String, !fallback.isEmpty {
            return fallback
        }
        return ""
    }
}

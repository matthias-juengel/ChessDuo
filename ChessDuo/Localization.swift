import Foundation

extension String {
    /// Convenience localized string lookup
    static func loc(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        if args.isEmpty { return format }
        return String(format: format, locale: .current, arguments: args)
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

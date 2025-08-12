import Foundation

extension String {
    /// Convenience localized string lookup
    static func loc(_ key: String, _ args: CVarArg...) -> String {
        let format = NSLocalizedString(key, comment: "")
        if args.isEmpty { return format }
        return String(format: format, locale: .current, arguments: args)
    }
}

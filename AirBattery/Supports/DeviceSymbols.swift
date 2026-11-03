import AppKit

/// Resolves SF Symbols for Apple devices from the system's own device type catalog, the same source the Bluetooth menu uses.
enum DeviceSymbols {
    private struct TypeInfo {
        var symbol: String?
        var variants: [String: String]
        var conformsTo: [String]
    }

    private struct Catalog {
        var tags: [String: [String]] = [:]
        var types: [String: TypeInfo] = [:]
    }

    private static let catalog: Catalog = loadCatalog()
    private static let familyTypes = [(prefix: "Watch", uti: "com.apple.watch"), (prefix: "AppleTV", uti: "com.apple.apple-tv")]

    static func symbol(vendorProductID: String, variant: String? = nil) -> String? {
        resolve(catalog.tags[vendorProductID] ?? [], variant: variant)
    }

    static func symbol(modelCode: String, variant: String? = nil) -> String? {
        if let utis = catalog.tags[modelCode] { return resolve(utis, variant: variant) }
        let colored = catalog.tags.filter { $0.key.hasPrefix(modelCode + "@") }.sorted { $0.key < $1.key }
        if !colored.isEmpty { return resolve(colored.flatMap { $0.value }, variant: variant) }
        let family = familyTypes.first { modelCode.hasPrefix($0.prefix) }
        return resolve(family.map { [$0.uti] } ?? [], variant: variant)
    }

    private static func resolve(_ utis: [String], variant: String?) -> String? {
        for uti in utis {
            var queue = [uti]
            var seen = Set<String>()
            while !queue.isEmpty {
                let current = queue.removeFirst()
                guard seen.insert(current).inserted, let info = catalog.types[current] else { continue }
                if let base = info.symbol {
                    let candidates = [variant.flatMap { info.variants[$0] }, base].compactMap { $0 }
                    if let found = candidates.first(where: isAvailable) { return found }
                }
                queue += info.conformsTo
            }
        }
        return nil
    }

    private static func isAvailable(_ symbol: String) -> Bool {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil
    }

    private static func loadCatalog() -> Catalog {
        let root = "/System/Library/CoreServices/CoreTypes.bundle/Contents"
        var plists = ["\(root)/Info.plist"]
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: "\(root)/Library")) ?? []
        plists += bundles.filter { $0.hasPrefix("CoreTypes-") }.sorted().map { "\(root)/Library/\($0)/Contents/Info.plist" }

        var result = Catalog()
        for path in plists {
            guard let data = FileManager.default.contents(atPath: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { continue }
            let declarations = ["UTExportedTypeDeclarations", "UTImportedTypeDeclarations"].flatMap { plist[$0] as? [[String: Any]] ?? [] }
            for declaration in declarations {
                guard let uti = declaration["UTTypeIdentifier"] as? String else { continue }
                let icons = declaration["UTTypeIcons"] as? [String: Any]
                let conforms = declaration["UTTypeConformsTo"]
                var info = result.types[uti] ?? TypeInfo(symbol: nil, variants: [:], conformsTo: [])
                info.symbol = info.symbol ?? icons?["UTTypeSymbolName"] as? String
                info.variants.merge(icons?["UTTypeSymbolVariantNames"] as? [String: String] ?? [:]) { current, _ in current }
                info.conformsTo += (conforms as? [String]) ?? (conforms as? String).map { [$0] } ?? []
                result.types[uti] = info

                let tags = declaration["UTTypeTagSpecification"] as? [String: Any]
                for key in ["public.bluetooth-vendor-product-id", "com.apple.device-model-code"] {
                    let values = (tags?[key] as? [String]) ?? (tags?[key] as? String).map { [$0] } ?? []
                    for value in values where !(result.tags[value]?.contains(uti) ?? false) {
                        result.tags[value, default: []].append(uti)
                    }
                }
            }
        }
        return result
    }
}

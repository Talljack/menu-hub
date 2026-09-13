import Foundation
import MenuHubCore

struct SettingsExportService: Sendable {
    let encode: @Sendable (CatalogDocument) throws -> Data
    let write: @Sendable (Data, URL) throws -> Void

    static let live = Self(
        encode: { try JSONEncoder().encode($0) },
        write: { try $0.write(to: $1, options: .atomic) }
    )

    func export(_ document: CatalogDocument, to url: URL) throws {
        try write(encode(document), url)
    }
}

import UIKit

/// Enregistre les logos importés depuis Photos (redimensionnés, en PNG).
enum LogoStorage {
    static func save(_ data: Data) -> String? {
        guard let image = UIImage(data: data), image.size.width > 0, image.size.height > 0 else { return nil }
        let maxSide: CGFloat = 400
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let png = resized.pngData() else { return nil }
        do {
            try FileManager.default.createDirectory(at: AppPaths.logosFolder, withIntermediateDirectories: true)
            let name = UUID().uuidString + ".png"
            try png.write(to: AppPaths.logoFile(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func delete(_ name: String?) {
        guard let name else { return }
        try? FileManager.default.removeItem(at: AppPaths.logoFile(name))
    }
}

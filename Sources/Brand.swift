import AppKit

enum Brand {
  static let mark: NSImage = {
    let image = Bundle.main.url(forResource: "mark", withExtension: "svg")
      .flatMap { NSImage(contentsOf: $0) }
      ?? NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil)!
    image.isTemplate = true
    return image
  }()
}

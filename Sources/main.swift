import AppKit

MainActor.assumeIsolated {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let delegate = App()
  app.delegate = delegate
  withExtendedLifetime(delegate) { app.run() }
}

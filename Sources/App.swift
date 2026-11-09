import AppKit
import ApplicationServices
import SwiftUI

@MainActor final class App: NSObject, NSApplicationDelegate {
  let state = State()
  let panel = PreviewPanel(
    contentRect: NSRect(origin: .zero, size: Card.size),
    styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
  let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  var timer: Timer?
  var pendingRead = false
  var currentHost = ""
  var enabled = !UserDefaults.standard.bool(forKey: "paused")
  var mode =
    Mode(rawValue: UserDefaults.standard.object(forKey: "mode") as? Int ?? Mode.work.rawValue)
    ?? .work
  var watched: pid_t?
  var lastField: AXUIElement?
  func applicationDidFinishLaunching(_ n: Notification) {
    updateStatusIcon()
    panel.contentView = PreviewHostingView(rootView: Card(resized: { [weak self] height in
      guard let self, panel.frame.height != height else { return }
      var frame = panel.frame
      frame.origin.y = frame.maxY - height
      frame.size.height = height
      if let area = panel.screen?.visibleFrame { frame.origin.y = max(area.minY + 8, frame.minY) }
      panel.setFrame(frame, display: true)
    }, state: state))
    panel.isFloatingPanel = true
    panel.level = .floating
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    rebuildMenu()
    #if TEST_PROBES
    let sample = CommandLine.arguments.contains("--english")
      ? "why the tests fails when the token expire?"
      : "\u{4F60}\u{597D}"
    if CommandLine.arguments.contains("--smoke") {
      panel.center()
      panel.orderFrontRegardless()
      state.update(sample, mode: CommandLine.arguments.contains("--common") ? .common : .work)
      timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          if self.state.status == "Done"
            || (!self.state.status.isEmpty && !["Waiting for a pause…", "Translating…", "Polishing…"].contains(self.state.status))
          {
            print(self.state.english.isEmpty ? self.state.status : self.state.english)
            if self.state.status != "Done" { exit(1) }
            NSApp.terminate(nil)
          }
        }
      }
      return
    }
    if CommandLine.arguments.contains("--verify-cli") {
      Task {
        for _ in 0..<200 {
          try? await Task.sleep(nanoseconds: 250_000_000)
          if state.status == "Done", state.draft == sample,
            panel.isVisible
          {
            print("Verified visible panel: " + state.origin + " | " + state.english)
            NSApp.terminate(nil)
            return
          }
        }
        print("Verification timed out")
        exit(2)
      }
    }
    #endif
    timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }

  }
  func updateStatusIcon() {
    guard let button = item.button else { return }
    let icon = Brand.mark.copy() as! NSImage
    icon.size = NSSize(width: 18, height: 18)
    icon.isTemplate = true
    button.image = icon
    button.title = enabled ? "" : " ⏸"
    button.toolTip = enabled ? "AgentEnglish" : "AgentEnglish (paused)"
    button.setAccessibilityLabel(button.toolTip)
  }
  func rebuildMenu() {
    let m = NSMenu()
    func add(_ title: String, _ action: Selector) -> NSMenuItem {
      let x = NSMenuItem(title: title, action: action, keyEquivalent: "")
      x.target = self
      m.addItem(x)
      return x
    }
    _ = add(enabled ? "Pause Translation" : "Resume Translation", #selector(toggle))
    _ = add(AXIsProcessTrusted() ? "Desktop Access Enabled" : "Enable Desktop Access…", #selector(authorize))
    _ = add("Setup Guide…", #selector(guide))
    let slow = add("Slow Speech", #selector(slowVoice))
    slow.state = UserDefaults.standard.bool(forKey: "slowVoice") ? .on : .off
    let delay = add("Wait 1.2 Seconds After Typing", #selector(changeDelay))
    delay.state = UserDefaults.standard.integer(forKey: "delay") == 1200 ? .on : .off
    m.addItem(.separator())
    for opt in Mode.allCases {
      let x = add(opt.title, #selector(change(_:)))
      x.tag = opt.rawValue
      x.state = opt == mode ? .on : .off
    }
    _ = add("Retry Translation", #selector(retry))
    m.addItem(.separator())
    _ = add("Quit AgentEnglish", #selector(quit))
    item.menu = m
  }
  @objc func authorize() {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    if !AXIsProcessTrustedWithOptions([key: true] as CFDictionary) {
      NSWorkspace.shared.open(
        URL(
          string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
  }
  @objc func guide() {
    if let file = Bundle.main.url(forResource: "guide", withExtension: "html") {
      NSWorkspace.shared.open(file)
    }
  }
  @objc func slowVoice() {
    UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "slowVoice"), forKey: "slowVoice")
    rebuildMenu()
  }
  @objc func changeDelay() {
    UserDefaults.standard.set(
      UserDefaults.standard.integer(forKey: "delay") == 1200 ? 650 : 1200, forKey: "delay")
    rebuildMenu()
  }
  func applicationWillTerminate(_ n: Notification) {
    if LocalModel.service?.isRunning == true { LocalModel.service?.terminate() }
  }
  @objc func toggle() {
    enabled.toggle()
    UserDefaults.standard.set(!enabled, forKey: "paused")
    hide()
    updateStatusIcon()
    rebuildMenu()
  }
  @objc func change(_ sender: NSMenuItem) {
    mode = Mode(rawValue: sender.tag) ?? .apple
    UserDefaults.standard.set(mode.rawValue, forKey: "mode")
    hide()
    rebuildMenu()
  }
  @objc func retry() { hide() }
  @objc func quit() { NSApp.terminate(nil) }
  func hide() {
    if panel.isVisible { panel.orderOut(nil) }
    if !state.draft.isEmpty { state.clear() }
    lastField = nil
  }
  func tick() {
    guard enabled, let app = NSWorkspace.shared.frontmostApplication,
      let host = app.bundleIdentifier
    else {
      hide()
      return
    }
    if currentHost != host {
      hide()
      currentHost = host
    }
    if TerminalSessions.hosts.contains(host) {
      if pendingRead { return }
      pendingRead = true
      Task {
        let d = await Task.detached(priority: .utility) { TerminalSessions.latest(for: host) }.value
        pendingRead = false
        guard enabled, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == host else {
          return
        }
        guard let d, d.active else {
          hide()
          return
        }
        state.origin = d.agent == "claude" ? "Claude Code" : "Codex CLI"
        if let text = d.text, (d.filtersHints == true || !isTerminalHint(text)), WritingAction(text) != nil {
          if state.draft != text { state.update(text, mode: mode) }
        } else {
          if !state.draft.isEmpty { state.clear() }
          let ready = "Type in Chinese or English, then pause."
          if state.status != ready { state.status = ready }
        }
        show(terminalFrame(app.processIdentifier), terminal: true)
      }
      return
    }
    guard desktops.contains(host), AXIsProcessTrusted() else {
      hide()
      return
    }
    state.origin = app.localizedName ?? "Desktop"
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(ax, 0.2)
    if watched != app.processIdentifier {
      AXUIElementSetAttributeValue(ax, "AXManualAccessibility" as CFString, kCFBooleanTrue)
      watched = app.processIdentifier
    }
    guard let field = element(ax, "AXFocusedUIElement"),
      let role = attr(field, "AXRole") as? String, ["AXTextArea", "AXTextField"].contains(role),
      !["AXSecureTextField", "AXSearchField"].contains(attr(field, "AXSubrole") as? String ?? ""),
      let text = attr(field, "AXValue") as? String, WritingAction(text) != nil
    else {
      hide()
      return
    }
    if lastField.map({ !CFEqual($0, field) }) ?? true {
      state.clear()
      lastField = field
    }
    if state.draft != text { state.update(text, mode: mode) }
    let box = bounds(field) ?? element(ax, "AXFocusedWindow").flatMap(bounds)
    show(box, terminal: false)
  }
  // Older CLI bridges can include the idle prompt as if it were typed text.
  func isTerminalHint(_ text: String) -> Bool {
    text == "Ask Codex to do anything" ||
      (text.hasPrefix("Try \"") && text.hasSuffix("\""))
  }
  func terminalFrame(_ pid: pid_t) -> CGRect? {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
      let w = windows.first(where: {
        $0[kCGWindowOwnerPID as String] as? Int32 == pid
          && $0[kCGWindowLayer as String] as? Int == 0
      }),
      let b = w[kCGWindowBounds as String] as? [String: CGFloat], let x = b["X"], let y = b["Y"],
      let width = b["Width"], let h = b["Height"],
      let top = NSScreen.screens.first?.frame.maxY
    else { return nil }
    return CGRect(x: x, y: top - y - h, width: width, height: h)
  }
  func show(_ box: CGRect?, terminal: Bool) {
    let screen =
      NSScreen.screens.first { screen in
        box.map { screen.frame.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? false
      } ?? NSScreen.main
    guard let area = screen?.visibleFrame else { return }
    let anchor = box ?? area
    let size = panel.frame.size
    let right = anchor.maxX + 10
    let x = right + size.width < area.maxX ? right : anchor.maxX - size.width
    let y =
      terminal
      ? anchor.maxY - size.height - 16
      : (right + size.width < area.maxX ? anchor.midY - size.height / 2 : anchor.maxY + 10)
    panel.setFrameOrigin(
      NSPoint(
        x: max(area.minX + 8, min(x, area.maxX - size.width - 8)),
        y: max(area.minY + 8, min(y, area.maxY - size.height - 8))))
    if !panel.isVisible { panel.orderFrontRegardless() }
  }
}

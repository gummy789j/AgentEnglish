import AppKit
import SwiftUI

MainActor.assumeIsolated {
  let app = NSApplication.shared
  app.setActivationPolicy(.accessory)
  let state = State()
  state.origin = "Claude Code"
  state.action = .translate
  let win = PreviewPanel(contentRect: NSRect(origin: .zero, size: Card.size), styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
  let view = PreviewHostingView(rootView: Card(resized: { height in
    win.setContentSize(CGSize(width:Card.size.width,height:height))
  }, state:state))
  win.backgroundColor = .clear; win.isOpaque = false
  win.contentView = view
  win.center(); win.orderFrontRegardless()
  let board = NSPasteboard(name:.init(rawValue:"AgentEnglish-Test-"+UUID().uuidString))
  defer { board.releaseGlobally() }
  func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.5)) }
  settle()
  let minimum = win.frame.height
  let result = "I sometimes want to write in English. Could you correct my grammar and suggest more specific wording based on the mode I select?"
  state.english = result; state.status = "Translating…"
  precondition(!state.copyResult(to:board))
  state.status = "Done"; settle()
  let sampleHeight = win.frame.height
  precondition(state.copyResult(to:board) && board.string(forType:.string) == result)
  if let output = ProcessInfo.processInfo.environment["AGENTENGLISH_PREVIEW_PATH"] {
    let rep = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
    view.cacheDisplay(in:view.bounds,to:rep)
    try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:output))
  }
  state.english = Array(repeating:result,count:25).joined(separator:"\n")
  settle()
  let longHeight = win.frame.height
  precondition(state.copyResult(to:board) && board.string(forType:.string) == state.english)
  print("ready / sample / long height:",minimum,sampleHeight,longHeight,"copied:",state.english.count)
  precondition(minimum < sampleHeight && sampleHeight < longHeight && longHeight <= 375)
}

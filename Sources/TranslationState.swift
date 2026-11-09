import AVFoundation
import SwiftUI
import Translation

let source = Locale.Language(identifier: "zh-Hant")
let target = Locale.Language(identifier: "en")

enum Mode: Int, CaseIterable {
  case apple, work, common
  var title: String { ["Apple · Offline", "Work · Ollama", "Everyday · Ollama"][rawValue] }
}
enum WritingAction {
  case translate, polish

  init?(_ text: String) {
    if text.range(of: #"\p{Han}"#, options: .regularExpression) != nil {
      self = .translate
    } else if text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
      self = .polish
    } else {
      return nil
    }
  }
}
@MainActor final class State: ObservableObject {
  @Published var config: TranslationSession.Configuration?
  @Published var origin = ""
  @Published var action: WritingAction?
  @Published var english = ""
  @Published var status = ""
  var draft = ""
  var epoch = 0
  var job: Task<Void, Never>?
  let voice = AVSpeechSynthesizer()
  func clear() {
    epoch += 1
    job?.cancel()
    config = nil
    action = nil
    draft = ""
    english = ""
    status = ""
    voice.stopSpeaking(at: .immediate)
  }
  var canCopy: Bool { status == "Done" && !english.isEmpty }

  @discardableResult
  func copyResult(to pasteboard: NSPasteboard = .general) -> Bool {
    guard canCopy else { return false }
    pasteboard.clearContents()
    return pasteboard.setString(english, forType: .string)
  }

  func say() {
    voice.stopSpeaking(at: .immediate)
    let line = AVSpeechUtterance(string: english)
    line.voice = AVSpeechSynthesisVoice(language: "en-US")
    line.rate = UserDefaults.standard.bool(forKey: "slowVoice") ? 0.36 : 0.48
    voice.speak(line)
  }
  func update(_ text: String, mode: Mode) {
    clear()
    guard let action = WritingAction(text) else { return }
    self.action = action
    draft = text
    let revision = epoch
    status = "Waiting for a pause…"
    job = Task {
      do {
        try await Task.sleep(
          nanoseconds: UInt64(UserDefaults.standard.object(forKey: "delay") as? Int ?? 650)
            * 1_000_000)
        status = action == .polish ? "Polishing…" : "Translating…"
        if mode == .apple && action == .polish {
          status = "Choose Work or Everyday in the AgentEnglish menu to polish English."
          return
        }
        if mode == .apple {
          let available = await LanguageAvailability().status(from: source, to: target)
          guard epoch == revision else { return }
          guard available == .installed else {
            status = "Download Traditional Chinese and English in System Settings → General → Language & Region → Translation Languages, then choose Retry Translation."
            return
          }
          config = .init(source: source, target: target)
        } else {
          try await LocalModel.generate(text, mode: mode, action: action) { result in
            if epoch == revision { english = result }
          }
          if epoch == revision { status = "Done" }
        }
      } catch {
        if epoch == revision {
          english = ""
          status = (error as? LocalModel.Failure)?.errorDescription ?? "Translation failed. Check Ollama and choose Retry Translation."
        }
      }
    }
  }
  func appleTranslate(_ session: TranslationSession) async {
    let revision = epoch
    guard !draft.isEmpty, config != nil else { return }
    do {
      let reply = try await session.translate(draft)
      if epoch == revision { english = reply.targetText; status = "Done" }
    } catch {
      if epoch == revision { status = "Check your downloaded languages, then choose Retry Translation." }
    }
  }

}

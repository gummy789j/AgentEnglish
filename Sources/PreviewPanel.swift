import AppKit
import SwiftUI
import Translation

struct Card: View {
  static let size = CGSize(width: 414, height: 166)
  // Header, footer, dividers and padding consume 102 points.
  private let chrome: CGFloat = 102
  private let maxBody: CGFloat = 270
  @SwiftUI.State private var measured: CGFloat = 64
  @SwiftUI.State private var copied = false
  var resized: (CGFloat) -> Void = { _ in }
  @ObservedObject var state: State
  init(resized: @escaping (CGFloat) -> Void = { _ in }, state: State) {
    self.resized = resized
    self.state = state
  }
  private let mint = Color(red: 0.62, green: 0.90, blue: 0.77)
  private let muted = Color(red: 0.68, green: 0.73, blue: 0.74)
  private var hasTranslation: Bool { !state.english.isEmpty }

  private var displayText: String { hasTranslation ? state.english : state.status }
  private var bodyFont: NSFont {
    let base = NSFont.systemFont(ofSize: hasTranslation ? 19 : 15)
    guard hasTranslation, let serif = base.fontDescriptor.withDesign(.serif) else { return base }
    return NSFont(descriptor: serif, size: 19) ?? base
  }

  private func resizeToText() {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 3
    let bounds = (displayText as NSString).boundingRect(
      with: NSSize(width: Self.size.width - 40, height: .greatestFiniteMagnitude),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: [.font: bodyFont, .paragraphStyle: paragraph])
    let height = ceil(bounds.height) + 8
    measured = height
    resized(chrome + max(64, min(maxBody, height)))
  }

  private var header: some View {
      HStack(spacing: 8) {
        Image(nsImage: Brand.mark).renderingMode(.template).resizable().scaledToFit()
          .frame(width: 16, height: 16)
          .foregroundStyle(Color(red: 0.06, green: 0.18, blue: 0.16))
          .frame(width: 25, height: 25)
          .background(mint, in: RoundedRectangle(cornerRadius: 8))
          .accessibilityHidden(true)
        Text("AgentEnglish").font(.system(size: 13, weight: .semibold))
        Spacer()
        Button {
          copied = state.copyResult()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
            Text(copied ? "Copied" : "Copy")
          }
          .font(.system(size: 11, weight: .semibold))
          .padding(.horizontal, 9).frame(height: 27)
          .foregroundStyle(state.canCopy ? mint : muted.opacity(0.60))
          .background(Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain).disabled(!state.canCopy)
        .accessibilityLabel("Copy full result").help("Copy the complete English text")
        .onChange(of: state.draft) { copied = false }
        .task(id: copied) {
          guard copied else { return }
          do { try await Task.sleep(for: .seconds(1.5)); copied = false } catch { }
        }
        Button { state.say() } label: {
          Image(systemName: "speaker.wave.2.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hasTranslation ? mint : muted.opacity(0.55))
            .frame(width: 29, height: 27)
            .background(Color.white.opacity(0.07), in: Capsule())
        }
        .buttonStyle(.plain).disabled(!hasTranslation)
        .accessibilityLabel("Read aloud").help("Read aloud")
      }
  }
  private var resultView: some View {
      ScrollView {
        Text(verbatim: displayText)
          .font(Font(bodyFont))
          .foregroundStyle(hasTranslation ? Color.white : muted)
          .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

      }
      .id(state.epoch)
      .scrollIndicators(measured > maxBody ? .visible : .hidden)
      .padding(.vertical, 11)
  }
  private var footer: some View {
      HStack(spacing: 7) {
        Circle().fill(mint).frame(width: 5, height: 5)
        Text(state.origin.isEmpty ? "Local translation" : state.origin)
        Spacer()
        if measured > maxBody {
          Label("Scroll", systemImage: "arrow.up.and.down")
        } else if hasTranslation && !state.canCopy {
          Text("Writing…")
        }
        Text(state.action == .polish ? "POLISH  ·  EN" : state.action == .translate ? "ZH  →  EN" : "EN").tracking(1)
      }.font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(muted).padding(.top, 9)
  }
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      resultView
      Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
      footer
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 17).padding(.vertical, 13)
    .frame(width: Self.size.width, height: chrome + max(64, min(maxBody, measured)))
    .onChange(of: displayText, initial: true) { resizeToText() }
    .background(LinearGradient(colors: [
      Color(red: 0.12, green: 0.18, blue: 0.19),
      Color(red: 0.085, green: 0.10, blue: 0.13)
    ], startPoint: .topLeading, endPoint: .bottomTrailing))
    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Color.white.opacity(0.17)))
    .preferredColorScheme(.dark)
    .translationTask(state.config) { session in await state.appleTranslate(session) }
  }
}
final class PreviewHostingView: NSHostingView<Card> {
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
final class PreviewPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

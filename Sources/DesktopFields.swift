import AppKit
import ApplicationServices

let desktops = ["com.anthropic.claudefordesktop", "com.openai.chat", "com.openai.codex", "sh.herder.Herder"]
func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(e, key as CFString, &value) == .success else { return nil }
  return value
}
func element(_ e: AXUIElement, _ key: String) -> AXUIElement? {
  guard let v = attr(e, key), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
  return (v as! AXUIElement)
}
func bounds(_ e: AXUIElement) -> CGRect? {
  guard let p = attr(e, "AXPosition"), let s = attr(e, "AXSize"),
    CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
    let top = NSScreen.screens.first?.frame.maxY
  else { return nil }
  var point = CGPoint.zero
  var size = CGSize.zero
  guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
    AXValueGetValue(s as! AXValue, .cgSize, &size),
    size.width > 0 && size.height > 0
  else { return nil }
  return CGRect(x: point.x, y: top - point.y - size.height, width: size.width, height: size.height)
}

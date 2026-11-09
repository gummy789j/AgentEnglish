import Darwin
import Foundation

struct TerminalDraft: Decodable, Sendable {
  let host: String
  let stamp: Double
  let active: Bool
  let agent: String
  let text: String?
  let filtersHints: Bool?
}

// Run on a worker thread. The bridge only releases its in-memory draft when
// queried for its own terminal host. No prompt text is written to disk.
enum TerminalSessions {
  static let hosts = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty"]
  static func latest(for host: String) -> TerminalDraft? {
    let dir = "/tmp/agentenglish-" + String(getuid())
    var info = stat()
    guard lstat(dir, &info) == 0, info.st_uid == getuid(),
      info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o077 == 0,
      let paths = try? FileManager.default.contentsOfDirectory(atPath: dir)
    else { return nil }
    return paths.filter { $0.hasSuffix(".sock") }
      .compactMap { query(dir + "/" + $0, host: host) }
      .filter { $0.host == host }.max { $0.stamp < $1.stamp }
  }
  private static func query(_ path: String, host: String) -> TerminalDraft? {
    var address = sockaddr_un()
    let bytes = path.utf8CString
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &address.sun_path) { out in
      bytes.withUnsafeBytes { out.copyBytes(from: $0) }
    }
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    defer { close(fd) }
    var timeout = timeval(tv_sec: 0, tv_usec: 100000)
    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))
    setsockopt(
      fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    let connected = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard connected == 0 else { return nil }
    var peer = uid_t()
    var group = gid_t()
    guard getpeereid(fd, &peer, &group) == 0, peer == getuid() else { return nil }
    let request = Data((host + "\n").utf8)
    guard request.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == request.count else {
      return nil
    }
    var data = Data()
    var buf = [UInt8](repeating: 0, count: 8192)
    while data.count < 700000 {
      let n = read(fd, &buf, buf.count)
      if n == 0 { break }
      if n < 0 { return nil }
      data.append(contentsOf: buf.prefix(n))
      if data.last == 10 { break }
    }
    return try? JSONDecoder().decode(TerminalDraft.self, from: data)
  }
}

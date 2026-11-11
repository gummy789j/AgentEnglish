import Foundation

struct Sample: Decodable {
  let name: String
  let text: String
  let mode: String
  let action: String
  let review: String
  let requiredFragments: [String]?
  let forbiddenFragments: [String]?
}
let samples = try JSONDecoder().decode([Sample].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
Task { @MainActor in
  do {
    var failed = false
    for sample in samples {
      var output = ""
      try await LocalModel.generate(sample.text, mode: sample.mode == "work" ? .work : .common,
        action: sample.action == "polish" ? .polish : .translate) { output = $0 }
      let normalized = output.lowercased()
      let missing = (sample.requiredFragments ?? []).filter { !normalized.contains($0.lowercased()) }
      let leaked = (sample.forbiddenFragments ?? []).filter { normalized.contains($0.lowercased()) }
      failed = failed || !missing.isEmpty || !leaked.isEmpty
      let data = try JSONSerialization.data(withJSONObject: [
        "name": sample.name, "output": output, "review": sample.review,
        "missingFragments": missing, "forbiddenFragmentsFound": leaked,
      ], options: [.sortedKeys, .withoutEscapingSlashes])
      print(String(decoding: data, as: UTF8.self))
      fflush(stdout)
    }
    exit(failed ? 1 : 0)
  } catch { print(error); exit(1) }
}
dispatchMain()

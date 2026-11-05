//
//
//  Copyright (c) 2025 GetYourGuide GmbH
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//

import Basics
import Core
import FixtureSupport
import Foundation
import PackageModel
import SPMGraphDescriptionInterface
import Testing

@testable import SPMGraphLint

@Suite(.serialized)
struct SPMGraphLintTests {
  @Test("It loads every root package and runs the rules on each of them")
  func multipleRoots() async throws {
    let recorder = Recorder()
    let lint = try makeLint(
      roots: [.fixturePackagePath, .secondFixturePackagePath],
      rule: .recording(into: recorder)
    )

    try await lint.run()

    #expect(recorder.packageNames == ["LintFixturePackage", "SecondFixturePackage"])
  }

  @Test("It runs a graph rule once with every root package")
  func graphRule() async throws {
    let recorder = Recorder()
    let lint = try makeLint(
      roots: [.fixturePackagePath, .secondFixturePackagePath],
      rule: .recordingGraph(into: recorder)
    )

    try await lint.run()

    #expect(recorder.packageNames == ["LintFixturePackage+SecondFixturePackage"])
  }

  @Test("It writes the sorted, unique violation identities to the baseline file")
  func writesBaseline() async throws {
    let baseline = try temporaryFile()
    let lint = try makeLint(
      rule: .failing(with: ["b", "a", "a"]),
      baselinePath: baseline,
      writeBaseline: true
    )

    try await lint.run()

    #expect(try localFileSystem.readFileContents(baseline) == "fake: a\nfake: b\n")
  }

  @Test("It passes when the violations match the baseline")
  func matchingBaseline() async throws {
    let baseline = try temporaryFile(contents: "fake: a\nfake: b\n")
    let lint = try makeLint(rule: .failing(with: ["a", "b"]), baselinePath: baseline)

    try await lint.run()
  }

  @Test("It fails on a violation missing from the baseline")
  func newViolation() async throws {
    let baseline = try temporaryFile(contents: "fake: a\n")
    let lint = try makeLint(rule: .failing(with: ["a", "b"]), baselinePath: baseline)

    try await expectBaselineMismatch(new: ["fake: b"], stale: []) {
      try await lint.run()
    }
  }

  @Test("It fails on a baseline entry that no longer occurs, so the baseline only shrinks")
  func staleBaselineEntry() async throws {
    let baseline = try temporaryFile(contents: "fake: a\nfake: b\n")
    let lint = try makeLint(rule: .failing(with: ["a"]), baselinePath: baseline)

    try await expectBaselineMismatch(new: [], stale: ["fake: b"]) {
      try await lint.run()
    }
  }

  @Test("It fails on a missing baseline file instead of treating it as empty")
  func missingBaseline() async throws {
    let baseline = try temporaryFile().parentDirectory.appending(component: "missing.txt")
    let lint = try makeLint(rule: .failing(with: []), baselinePath: baseline)

    await #expect(throws: (any Swift.Error).self) {
      try await lint.run()
    }
  }

  @Test("Strict mode without a baseline fails on any violation")
  func strictWithoutBaseline() async throws {
    let lint = try makeLint(rule: .failing(with: ["a"]), isStrict: true)

    let error = await #expect(throws: SPMGraphLint.Error.self) {
      try await lint.run()
    }
    guard case .lintFailedAndStrictIsOn = error else {
      Issue.record("Unexpected error: \(String(describing: error))")
      return
    }
  }

  @Test("Non-strict mode without a baseline only reports")
  func nonStrictWithoutBaseline() async throws {
    let lint = try makeLint(rule: .failing(with: ["a"]))

    try await lint.run()
  }
}

// MARK: - Helpers

private final class Recorder: @unchecked Sendable {
  private let lock = NSLock()
  private var names: [String] = []

  var packageNames: [String] {
    lock.withLock { names }
  }

  func record(_ name: String) {
    lock.withLock { names.append(name) }
  }
}

private struct FakeError: LocalizedError {
  let errorDescription: String?
}

private struct FakeConfigLoader: SPMGraphConfigLoading {
  let rule: SPMGraphConfig.Lint.Rule

  func load(buildDirectory: AbsolutePath) throws(SPMGraphConfigLoaderError) -> SPMGraphConfig {
    SPMGraphConfig(lint: .init(rules: [rule], isStrict: false))
  }
}

private extension SPMGraphConfig.Lint.Rule {
  static func failing(with messages: [String]) -> Self {
    Self(id: "fake", name: "Fake", abstract: "Fake") { _, _ in
      messages.map { FakeError(errorDescription: $0) }
    }
  }

  static func recordingGraph(into recorder: Recorder) -> Self {
    .graph(id: "fake", name: "Fake", abstract: "Fake", validate: { packages, _ in
      recorder.record(packages.map(\.manifest.displayName).joined(separator: "+"))
      return []
    })
  }

  static func recording(into recorder: Recorder) -> Self {
    Self(id: "fake", name: "Fake", abstract: "Fake") { package, _ in
      recorder.record(package.manifest.displayName)
      return []
    }
  }
}

private func makeLint(
  roots: [AbsolutePath] = [.fixturePackagePath],
  rule: SPMGraphConfig.Lint.Rule,
  isStrict: Bool = false,
  baselinePath: AbsolutePath? = nil,
  writeBaseline: Bool = false
) throws -> SPMGraphLint {
  try SPMGraphLint(
    packageLoader: .live,
    configLoader: FakeConfigLoader(rule: rule),
    input: SPMGraphLintInput(
      spmPackageDirectory: roots[0].pathString,
      additionalPackageDirectories: roots.dropFirst().map(\.pathString),
      configBuildDirectory: nil,
      excludedSuffixes: [],
      isStrict: isStrict,
      verbose: false,
      expectedWarningsCount: 0,
      outputFilePath: nil,
      baselinePath: baselinePath?.pathString,
      writeBaseline: writeBaseline
    )
  )
}

private func expectBaselineMismatch(
  new expectedNew: [String],
  stale expectedStale: [String],
  _ body: () async throws -> Void
) async throws {
  let error = await #expect(throws: SPMGraphLint.Error.self) {
    try await body()
  }
  guard case let .baselineMismatch(new, stale) = error else {
    Issue.record("Unexpected error: \(String(describing: error))")
    return
  }
  #expect(new == expectedNew)
  #expect(stale == expectedStale)
}

private func temporaryFile(contents: String? = nil) throws -> AbsolutePath {
  let directory = try localFileSystem.tempDirectory.appending(component: UUID().uuidString)
  try localFileSystem.createDirectory(directory, recursive: true)
  let file = directory.appending(component: "baseline.txt")
  if let contents {
    try localFileSystem.writeFileContents(file, string: contents)
  }
  return file
}

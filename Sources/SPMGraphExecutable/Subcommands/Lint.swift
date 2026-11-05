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

import ArgumentParser
import SPMGraphLint

struct LintArguments: ParsableArguments {
  @OptionGroup var common: SPMGraphArguments

  @Flag(
    name: [.short, .long],
    help: "Fails on warnings"
  )
  var strict: Bool = false

  @Option(
    name: [.customShort("o"), .customLong("output", withSingleDash: false)],
    help:
      "Relative path for an output file with the formatted lint results. By default the errors are only dumped into the sdtout."
  )
  var outputFilePath: String?

  @Option(
    name: [.customShort("c"), .customLong("warningsCount", withSingleDash: false)],
    help:
      "The number of allowed warnings for the strict mode. note: It can be useful to **bypass the strict mode in specific scenarios**. `The default is zero`."
  )
  public var expectedWarningsCount: UInt = 0

  @Option(
    name: .customLong("root"),
    help: "Another Package.swift directory linted together with the first one. Repeat it for several packages."
  )
  var additionalPackageDirectories: [String] = []

  @Option(
    name: .customLong("baseline"),
    help:
      "A file of accepted violations, one per line. The lint fails on a violation missing from it and on an entry that no longer occurs, so it can only shrink."
  )
  var baselinePath: String?

  @Flag(
    name: .customLong("write-baseline"),
    help: "Writes the current violations into the `--baseline` file instead of comparing against it."
  )
  var writeBaseline: Bool = false

  @OptionGroup
  var config: SPMGraphConfigArguments

  func validate() throws {
    if writeBaseline && baselinePath == nil {
      throw ValidationError("`--write-baseline` requires `--baseline <path>`.")
    }
  }
}

struct Lint: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    abstract: """
    Lints your Package.swift dependency graph and uncovers configuration issues. Arguments take precedence over the matching `SPMGraphConfig.swift` options.
    **Note**: It requires setting up your spmgraph configuration first; for that run `spmgraph config` to define your lint rules, and then load them using `spmgraph load`.
    """,
    discussion: """
        Run checks on a given Package.swift and raises configuration issues and potential optimisations
        that otherwise would be bubbled up by the build system later on.
      """,
    version: "1.2.0"
  )

  @OptionGroup var arguments: LintArguments

  mutating func run() async throws {
    let library = try SPMGraphLint(
      input: SPMGraphLintInput(
        spmPackageDirectory: arguments.common.spmPackageDirectory,
        additionalPackageDirectories: arguments.additionalPackageDirectories,
        configBuildDirectory: arguments.config.configBuildDirectory,
        excludedSuffixes: arguments.common.excludedSuffixes,
        isStrict: arguments.strict,
        verbose: arguments.common.verbose,
        expectedWarningsCount: arguments.expectedWarningsCount,
        outputFilePath: arguments.outputFilePath,
        baselinePath: arguments.baselinePath,
        writeBaseline: arguments.writeBaseline
      )
    )
    try await library.run()
  }
}

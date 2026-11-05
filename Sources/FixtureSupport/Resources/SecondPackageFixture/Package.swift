// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "SecondFixturePackage",
  dependencies: [
    .package(path: "../PackageFixture")
  ],
  targets: [
    .target(
      name: "SecondModule",
      dependencies: [
        .product(name: "LintLibrary", package: "PackageFixture")
      ]
    )
  ]
)

// swift-tools-version: 6.3

import PackageDescription

let package = Package(
  name: "Clp",
  platforms: [
    .macOS(.v26)
  ],
  products: [
    .executable(name: "Clp", targets: ["Clp"])
  ],
  dependencies: [],
  targets: [
    .executableTarget(
      name: "Clp",
      path: "Sources/Clp"
    ),
    .testTarget(
      name: "ClpTests",
      dependencies: ["Clp"],
      path: "Tests/ClpTests"
    ),
  ],
  swiftLanguageModes: [.v6]
)

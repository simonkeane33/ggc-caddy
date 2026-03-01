// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "GreystonesCaddyCore",
  platforms: [
    .iOS(.v17)
  ],
  products: [
    .library(name: "GreystonesCaddyCore", targets: ["GreystonesCaddyCore"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift", from: "6.29.0")
  ],
  targets: [
    .target(
      name: "GreystonesCaddyCore",
      dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
      ],
      resources: [
        .process("Resources/default.csv"),
        .process("Resources/greystones_course.json"),
        .process("Resources/satellite.styl"),
        .process("Resources/satellite@2x.styl")
      ]
    ),
    .testTarget(
      name: "GreystonesCaddyCoreTests",
      dependencies: ["GreystonesCaddyCore"]
    )
  ]
)

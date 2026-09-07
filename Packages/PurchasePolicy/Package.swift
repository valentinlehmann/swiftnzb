// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PurchasePolicy",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PurchasePolicy", targets: ["PurchasePolicy"]),
    ],
    targets: [
        // Pure free-tier / grandfathering arithmetic. No StoreKit, no persistence, no app types —
        // so the money rules are unit-testable without the app (there is no app test target).
        .target(name: "PurchasePolicy"),
        .testTarget(
            name: "PurchasePolicyTests",
            dependencies: ["PurchasePolicy"]
        ),
    ]
)

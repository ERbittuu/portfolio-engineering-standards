// swift-tools-version: 5.9
//
// SYSKitFirebase — the adapter that connects SYSKit's protocols to Firebase.
//
// Separate from SYSKit on purpose. Both relative paths only resolve once this
// package sits in an app's App/Packages/ alongside SYSKit and FirebaseKit, so
// keeping it apart leaves SYSKit itself buildable and testable in isolation.
//
// An app that uses no Firebase simply doesn't vendor this.
import PackageDescription

let package = Package(
    name: "SYSKitFirebase",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "SYSKitFirebase", targets: ["SYSKitFirebase"]),
    ],
    dependencies: [
        .package(path: "../SYSKit"),
        .package(path: "../FirebaseKit"),
    ],
    targets: [
        .target(
            name: "SYSKitFirebase",
            dependencies: [
                "SYSKit",
                .product(name: "FirebaseAnalytics", package: "FirebaseKit"),
                .product(name: "FirebaseCrashlytics", package: "FirebaseKit"),
            ]
        ),
    ]
)

// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "AppAuthIntrop",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13) // يدعم iOS فقط
    ],
    products: [
        .library(
            name: "AppAuthIntrop",
            targets: ["AppAuthIntrop"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/openid/AppAuth-iOS.git",
            from: "2.0.0"
        ),
        .package(
            url: "https://github.com/the-best-is-best/IOSCrypto",
            from: "1.0.1"
        )
    ],
    targets: [
        .target(
            name: "AppAuthIntrop",
            dependencies: [
                .product(name: "AppAuth", package: "AppAuth-iOS"),
                .product(name: "kmmcrypto", package: "IOSCrypto")

            ],
            path: "Sources/AppAuthIntrop", // تأكد من المسار الصحيح
            resources: [],
            swiftSettings: [
                // هذا يضمن استخدام SDK الخاص بـ iOS
                .define("PLATFORM_IOS", .when(platforms: [.iOS]))
            ]
        ),
    ]
)

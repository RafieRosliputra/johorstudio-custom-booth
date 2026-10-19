// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JohorBooth",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JohorBooth", targets: ["JohorBooth"]),
    ],
    dependencies: [
        // libwebp compiled from source and linked statically into the app (WebP encoding).
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "JohorBooth",
            dependencies: [
                .product(name: "libwebp", package: "libwebp-Xcode"),
            ],
            path: "Sources/JohorBooth"
        ),
    ]
)

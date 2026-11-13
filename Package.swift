// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "edfapay-ios-binaries",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "EdfaPaySoftPOS", targets: ["EdfaPaySoftPOS"]),
        .library(name: "EdfaPayDspread",  targets: ["EdfapayDspread"]),
    ],
    targets: [
        .binaryTarget(
            name: "EdfaPaySoftPOS",
            url: "https://github.com/edfapay/edfapay-ios-binaries/releases/download/1.0.0-dev/EdfaPaySoftPOS.xcframework.zip",
            checksum: "3aa91e5a3b41c68aa7bb141baa35bea28f4e2fe8610137981b7d46ae3b26d183"
        ),
        .binaryTarget(
            name: "EdfapayDspread",
            url: "https://github.com/edfapay/edfapay-ios-binaries/releases/download/1.0.0-dev/EdfapayDspread.xcframework.zip",
            checksum: "7664dcb77c27c446522d37af63da7a3892a674db119fd52f0c517353662477cd"
        ),
    ]
)

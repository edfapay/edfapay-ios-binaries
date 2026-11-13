# EdfaPay iOS Binaries

Pre-compiled XCFramework distributions for the EdfaPay SoftPOS iOS SDK.

## Requirements

- iOS 17.0+
- Swift 5.9+
- Xcode 15+

## Installation (Swift Package Manager)

Add this package to your project:

```
https://github.com/edfapay/edfapay-ios-binaries
```

### Products

| Product | Use when |
|---|---|
| `EdfaPaySoftPOS` | Apple Tap to Pay or Dspread external NFC payments |
| `EdfaPayDspread` | Direct Dspread CR100 BLE reader access only |

Most integrations only need `EdfaPaySoftPOS`.

## Usage

```swift
import EdfaPaySoftPOS

// Initialize the SDK
EdfaPayPlugin.shared.initiate(
    env: .production,
    onSuccess: { print("SDK ready") },
    onError: { error in print("Init failed: \(error)") }
)
```

## Releases

| Version | Date | Notes |
|---|---|---|
| 1.0.0-dev | 2026-11-13 | Initial binary release |

## Support

Contact [EdfaPay](https://edfapay.com) for integration support.

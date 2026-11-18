# EdfaPay SoftPOS Swift SDK

Swift-native iOS SDK for EdfaPay SoftPOS payments.

**Card acceptance is a seam, not an implementation.** NFC/APDU/EMV processing is performed by an external reader (Dspread CR100 BLE, or Tap to Pay on iPhone) and fed into the SDK through the `CardReader` / `ExternalNfcReader` protocols. The SDK handles authentication, server submission, retries, and UI coordination.

---

## Installation

### Swift Package Manager (source — development)

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/edfapay/edfapay-softpos-swift-sdk", from: "1.0.0")
]
```

### Swift Package Manager (binary release)

Add the binary-distribution package (pre-compiled XCFrameworks, no source dependency):

```swift
dependencies: [
    .package(url: "https://github.com/edfapay/edfapay-ios-binaries", from: "1.0.0")
]
// Products: EdfaPaySoftPOS (SDK), EdfaPayDspread (Dspread CR100 reader, add only if needed)
```

### Import

```swift
import softpos_sdk_swift
```

---

## Quick start

```swift
let plugin = EdfaPayPlugin.shared          // singleton
plugin.enableLogs = true                   // optional, dev only

// 1. Configure
plugin.configure(environment: .production)

// 2. Initialise (token / auth-code login)
plugin.initiate(
    credentials: EdfaPayCredentials(environment: .production, authCode: "YOUR_AUTH_CODE"),
    onSuccess: { sessionId in
        print("Ready — session \(sessionId ?? "")")
    },
    onTerminalBindingTask: { task in
        // No terminal bound yet — present task.terminals for the user to pick
        task.bind(task.terminals.first!, onError: { print($0) })
    },
    onError: { print($0) }
)

// 3. Charge
plugin.purchase(
    txnParams: TxnParams(amount: "10.00"),
    onError: { print($0) },
    onPaymentProcessComplete: { status, code, txn, _ in
        print(status ? "Approved \(txn?.bid ?? "")" : "Declined")
    }
)
```

---

## Configuration

### `configure`

Call once before `initiate`. Re-call to swap the card reader, inject a custom URLSession for tests, or override the environment.

```swift
plugin.configure(
    environment: .production,
    deviceId: "",                           // empty = stable UUID from Keychain
    configuration: .saEdfaPay(),           // or .default, or custom EdfapayConfiguration
    cardReader: MyCardReader(),             // defaults to NoopCardReader
    store: SessionStore(),                  // defaults to Keychain-backed store
    urlSession: .shared
)
```

### `restoreSession`

After `configure`, restore a previously persisted session so a relaunched app can resume without calling `initiate` again.

```swift
plugin.restoreSession { restored in
    if restored { /* session is live — go to dashboard */ }
    else        { /* show login screen */ }
}
```

### `EdfapayConfiguration`

Fine-grained crypto / timeout / variant settings. Use the built-in presets or build your own:

```swift
// Built-in preset (sa-edfapay partner defaults)
let config = EdfapayConfiguration.saEdfaPay(environmentURLs: [
    .production: EnvironmentURLs(baseUrl: "https://api.edfapay.com/")
])

// Custom
let config = EdfapayConfiguration(
    partner: .saEdfaPay,
    aesMode: .cbc,
    pinLength: 6,
    requestTimeoutMs: 60_000,
    scanCardTimeoutMs: 30_000,
    environmentURLs: [.production: EnvironmentURLs(baseUrl: "https://api.edfapay.com/")]
)
```

### `configure(environment:)`

Shortcut that sets environment, leaving all other settings at defaults. Equivalent to calling `configure(environment:configuration:.default)`.

```swift
plugin.configure(environment: .development)
```

---

## Environments

```swift
public enum Env {
    case development   // "dev"
    case staging       // "stg"
    case sandbox       // "sdx"
    case production    // "prod"
    case demo          // "demo"
    case revamp        // "revamp"
}
```

---

## Credentials

```swift
// Token / auth-code login (most common)
EdfaPayCredentials(environment: .production, authCode: "TOKEN")

// Email + password login (use with Extension.loginWithCredentials + verifyOtp)
EdfaPayCredentials(environment: .production, email: "user@example.com", password: "pw")
```

---

## Transactions

All transaction methods follow the same callback signature. `ProcessCompleteCallback` = `(Bool, String?, Transaction?, Bool) -> Void` where the arguments are `(isSuccess, responseCode, transaction, isFlowComplete)`.

### Purchase

```swift
plugin.purchase(
    flowType: .detail,                // .detail (default) | .immediate | .status
    txnParams: TxnParams(amount: "10.00", orderId: "order-123"),
    onRequestTimerEnd: { },           // server timeout (optional)
    onCardScanTimerEnd: { },          // card-scan timeout (optional)
    onError: { error in },
    onPaymentProcessComplete: { status, code, txn, done in },
    onCancelByUser: { }               // optional
)
```

### Authorize (pre-auth)

```swift
plugin.authorize(txnParams: TxnParams(amount: "50.00"), onError: { }, onPaymentProcessComplete: { _, _, _, _ in })
```

### Capture (settle an authorisation)

```swift
let params = TxnParams(amount: "50.00", originalTransaction: authorizedTxn)
plugin.capture(txnParams: params, onError: { }, onPaymentProcessComplete: { _, _, _, _ in })
```

### Refund

```swift
let params = TxnParams(amount: "10.00", originalTransaction: purchasedTxn)
plugin.refund(txnParams: params, onError: { }, onPaymentProcessComplete: { _, _, _, _ in })
```

### Void

Modelled as a reversal. Requires a `Transaction` from a previous approved transaction.

```swift
plugin.void(transaction: txn, onSuccess: { response in }, onError: { })
```

### Reverse (by transaction object)

```swift
plugin.reverse(transaction: txn, onSuccess: { response in }, onError: { })
```

### Reverse last transaction

```swift
plugin.reverseLastTransaction(onSuccess: { response in }, onError: { })
```

### `TxnParams`

```swift
var params = TxnParams(
    amount: "25.00",
    orderId: "optional-ref",           // defaults to a UUID
    transactionType: .purchase,        // optional — SDK sets this from the method call
    originalTransaction: prevTxn       // required for capture/refund/reversal
)
params.addAdditionalRequestParams(key: "custom_field", value: .string("value"))
try params.validate()                  // throws if originalTransaction invariants violated
```

### `FlowType`

| Value | Behaviour |
|---|---|
| `.detail` | Shows the full success/fail status screen. Sheet stays open until user taps Done (external NFC) or the host dismisses it. |
| `.immediate` | Dismisses automatically as soon as the server responds — no status screen. |
| `.status` | Like `.detail` but the status view is shown even before the user taps Done. |

---

## Reconciliation

```swift
// Trigger end-of-day reconciliation
plugin.reconcile(onSuccess: { recon in }, onError: { })

// History (paginated)
plugin.reconciliationHistory(pagination: Pagination(page: 1, perPage: 20),
                             onSuccess: { [ReconciliationHistory] in }, onError: { })

// Detail for one reconciliation
plugin.reconciliationDetail(id: "recon-id", onSuccess: { ReconciliationDetail in }, onError: { })

// Receipt for one reconciliation
plugin.reconciliationReceipt(id: "recon-id", onSuccess: { ReconciliationReceipt in }, onError: { })
```

---

## Transaction history

```swift
plugin.txnHistory(pagination: Pagination(page: 1, perPage: 20),
                  onSuccess: { [Transaction] in }, onError: { })

plugin.txnDetail(txnId: "txn-id", onSuccess: { Transaction in }, onError: { })
```

---

## Terminal management

```swift
plugin.activateTerminal(password: nil, onSuccess: { }, onError: { })
plugin.deActivateTerminal(password: nil, onSuccess: { }, onError: { })
plugin.syncTerminal(onSuccess: { }, onError: { })
plugin.terminalInfo(onSuccess: { TerminalInfo in }, onError: { })
```

---

## Session management

```swift
let sessionId: String?    = plugin.getSessionId()
let detail: SessionDetail? = plugin.getSessionDetail()

plugin.logoutCurrentSession { error, success in }
```

### `merchantName` (async property)

```swift
let name = await plugin.merchantName    // from downloaded terminal config
```

---

## Invoice / payment-gateway payments

```swift
plugin.invoicePayment(method: .card, body: ["invoice_id": .string("inv-123")],
                      onSuccess: { InvoicePaymentResponse in }, onError: { })

plugin.invoiceRefund(body: ["invoice_id": .string("inv-123")],
                     onSuccess: { InvoicePaymentResponse in }, onError: { })
```

---

## Receipts and transaction search

```swift
// Online receipt URL for a transaction or reconciliation
plugin.onlineReceiptUrl(type: .transaction, id: "txn-id",
                        onSuccess: { urlString in }, onError: { })

// Raw JSON transaction detail via merchant/payment-gateway API
plugin.apiTransactionDetail(id: "txn-id", onSuccess: { JSONValue in }, onError: { })

// Flexible search
plugin.transactionSearch(params: ["status": .string("APPROVED")],
                         onSuccess: { JSONValue in }, onError: { })

plugin.pgTransactionStatus(params: ["order_id": .string("ord-123")],
                           onSuccess: { JSONValue in }, onError: { })
```

---

## Extension — `EdfaPayPlugin.shared.Extension`

Advanced login / terminal / key operations.

### Credential-based login (two-step)

```swift
// Step 1 — submit email + password
plugin.Extension.loginWithCredentials(
    email: "merchant@example.com",
    password: "secret",
    location: Location(),
    onError: { },
    onSuccess: { login in
        // login.sessionId, login.otpExpireInSeconds
    }
)

// Step 1b — OTP sent; verify it
plugin.Extension.verifyOtp(
    sessionId: login.sessionId,
    otp: "123456",
    onError: { },
    onSuccess: { sdkLogin in /* session ready */ },
    onProfileSelection: { profiles, sessionId in
        // Multiple merchant profiles — pick one then call selectUser
    }
)

// Step 1c — multi-profile: select a user after OTP
plugin.Extension.selectUser(
    sessionId: sessionId,
    userId: profile.userId,
    otp: "123456",
    onError: { },
    onSuccess: { sdkLogin in }
)

// Resend OTP
plugin.Extension.resendOtp(sessionId: sessionId, onError: { }, onSuccess: { message in })
```

### Token login (single step)

```swift
plugin.Extension.loginWithToken(token: "AUTH_CODE", location: Location(),
                                 onError: { }, onSuccess: { sdkLogin in })
```

### Terminal provisioning

```swift
// List terminals available for binding
plugin.Extension.getAvailableTerminal(onError: { }, onSuccess: { [Terminal] in })

// Register (bind) a terminal TRSM
plugin.Extension.registerTerminal(trsm: "TRSM_VALUE",
                                   onError: { },
                                   onSuccess: { RegisterTerminalResponse in })

// Download terminal configuration
plugin.Extension.getTerminalConfig(
    forceDownload: false,
    configurationType: .fullTerminalConfiguration,
    onError: { },
    onSuccess: { DownloadParams in }
)

// Fetch or refresh the DUKPT initial key
plugin.Extension.getInitialKey(onError: { }, onSuccess: { keyString in })

// Renew the session token if it has expired and renewal is possible
plugin.Extension.renewSessionIfRequiredAndPossible(onError: { }, onSuccess: { sessionId in })
```

---

## Utils — `EdfaPayPlugin.shared.Utils`

```swift
// Stable per-install device identifier (UUID from Keychain)
let deviceId = plugin.Utils.getDeviceId()
let deviceId = plugin.Utils.getDeviceId(merchantId: 12345)  // appends merchantId suffix

// Jailbreak / debugger / integrity checks
let threats: [String] = plugin.Utils.securityThreats()  // ThreatType raw values

// Encrypted key-value storage (backed by SessionStore / Keychain)
plugin.Utils.saveData(key: "my_key", value: "my_value",
                      onSuccess: { saved in }, onError: { })
plugin.Utils.getData(key: "my_key") { value in }
```

---

## Webhooks — `configureHook`

After each transaction (and after `initiate`), the SDK POSTs `{"data":"<base64>"}` to your webhook. Delivery is best-effort with up to 5 retries at 60-second intervals.

```swift
let hook = Hook()
    .transaction(url: "https://your-server.com/hooks/txn",
                 header: ["Authorization": "Bearer TOKEN"])
    .initiate(url: "https://your-server.com/hooks/init")

plugin.configureHook(hook: hook)

// Optional payload encryptor (applied before base64 → POST body)
plugin.configureHook(hook: hook, encryptor: { base64 in encrypt(base64) })
```

---

## Partner config and security checks

```swift
// Apply a Base64-AES-CBC-gunzip-JSON partner configuration blob
plugin.setPartnerConfig(configBase64, key: aesKeyBytes)

// Toggle individual device-security checks
plugin.updateSecurityChecks(configBase64, key: aesKeyBytes)
// Config JSON structure: {"enabled": true, "checks": {"jailbreak": true, "debugger": false, …}}
```

---

## Remote channel (ECR integration) — `EdfaPayPlugin.shared.RemoteChannel`

A lightweight TCP server for receiving payment commands from an Electronic Cash Register over the local network.

```swift
// Open on port 8080
try plugin.RemoteChannel.LocalNetwork(port: 8080, timeout: 30).open()

// Close
plugin.RemoteChannel.close()
```

**Wire format** — newline-delimited JSON:

```json
// Request
{"id": "req-1", "fun": "purchase", "data": {"amount": "10.00", "orderId": "ref-1", "flowType": "detail"}}
{"id": "req-2", "fun": "reverseLastTransaction", "data": {}}

// Response
{"id": "req-1", "status": "APPROVED", "flowComplete": true, "transaction": {...}}
{"id": "req-1", "status": "ERROR", "message": "..."}
```

Supported `fun` values: `purchase`, `reverseLastTransaction`.

---

## External NFC reader — Scan-Card flow

For the contactless card-tap experience, the external reader performs the full EMV exchange and drives the SDK's UI via `EdfaContactlessEvents`. Use `ScanCardView` (SwiftUI) for the built-in tap-prompt → processing → PIN → result screen.

### Quick setup

```swift
// 1. Build a coordinator (call after initiate succeeds)
let coordinator = EdfaPayPlugin.shared.makeScanCardCoordinator(
    reader: myReader,                        // ExternalNfcReader implementation
    type: .purchase,
    flowType: .detail,
    txnParams: TxnParams(amount: "10.00"),
    onError: { error in /* pre-scan fatal error */ },
    onPaymentProcessComplete: { status, code, txn, isFlowComplete in
        // ⚠️ Do NOT dismiss the sheet here with flowType .detail —
        // ScanCardView shows the result and dismisses when the user taps Done.
    },
    onCancelByUser: { }
)

// 2. Present the view — ScanCardView calls coordinator.start() internally
.sheet(isPresented: $showScan) {
    ScanCardView(coordinator: coordinator) {
        showScan = false          // onFinished — user tapped Done
    }
}
// ⚠️ Never call coordinator.start() manually — ScanCardView already does this.
```

### `ExternalNfcReader` protocol

Conform to this to integrate any external reader:

```swift
public protocol ExternalNfcReader: Sendable {
    func connect(onScanEvent: (@Sendable (ScanEvent) -> Void)?,
                 onEvent: @escaping @Sendable (ConnectEvent) -> Void) async throws
    @MainActor
    func beginTransaction(params: TxnParams, events: EdfaContactlessEvents) async
    func stopScanning() async
    func release() async
    // Optional default: @MainActor func submitPin(_ pin: String) async {}
}
```

`beginTransaction` must drive `events` through the full sequence:
`waitingForCard()` → `cardTap()` → `cardConnecting()` → `cardConnectSuccess()` → `onCardConnected(_:)` → `cardSchemesFound()` → `cardSchemeSelected(_:)` → `transactionStarted()` → `transactionProcessing()` → `transactionSuccess()` → `onCardProcessComplete(_:)`.

### `CardData.externalReader` — supplying encrypted card data

When the reader does its own DUKPT encryption, build a `CardData` from the captured values so the reader's KSN wins request tag `53`:

```swift
let card = CardData.externalReader(
    kernelId: "dspread",
    scheme: .visa,
    maskedPan: "4***1234",
    icc: capturedEncryptedHex,   // DUKPT-encrypted ICC data → EMV tag 55
    ksn: capturedKsnHex,         // reader KSN → tag 53 (wins over SDK-derived key)
    isPinRequired: false,
    kernelProcessingFinished: true
)
events.onCardProcessComplete(card)
```

### `MockExternalNfcReader`

Drives the full event flow without hardware. Use during UI development and unit tests.

```swift
let reader = MockExternalNfcReader(
    card: CardData.externalReader(
        kernelId: "mock", scheme: .visa, maskedPan: "4***1234",
        icc: nil, ksn: nil, isPinRequired: false, kernelProcessingFinished: true
    ),
    stepDelay: 300_000_000       // 300 ms between events (0 for instant)
)
```

### `ScanCardViewModel` (custom UI)

If you're not using `ScanCardView`, bind your own UI to the view model:

```swift
let vm = coordinator.viewModel    // ScanCardViewModel: ObservableObject, @MainActor

vm.$uiState       // ScanCardUiState: .scanning | .cardTapped | .processing | .serverProcessing
                  //                  | .showingSchemeAnimation | .pinRequired | .success | .failed
                  //                  | .validationError
vm.$indicatorState  // IndicatorState
vm.allowDismiss     // Bool — false while EMV exchange is in flight
```

---

## Tap to Pay on iPhone (roadmap)

The SDK contains a process-lifetime `TapToPayExternalReader` singleton (`sharedTTPReader()`) conforming to `ExternalNfcReader`, backed by Apple's ProximityReader framework. It requires:

- An explicit Tap to Pay entitlement from Apple
- A ProximityReader JWT supplied either by the backend (`DownloadParams.ttpToken`) or injected manually:

```swift
plugin.setTtpToken("PROXIMITY_READER_JWT")   // inject manually in dev/sandbox
let token = await plugin.terminalTtpToken    // read (checks injection first, then backend)
```

---

## Error handling

```swift
plugin.purchase(/* ... */, onError: { error in
    if let ex = error as? EdfaException {
        switch ex.error {
        case .initialization(.sdkNotInitialized):
            // call configure + initiate first
        case .network(.timeout):
            // retry
        case .card(.invalidOrNotSupported):
            // ask user to try another card
        case .terminal(.registrationFailed):
            // terminal not bound
        default:
            print(ex.error.message)
        }
    }
})
```

### Error categories

| Category | Codes | Common cases |
|---|---|---|
| `.initialization` | 1xxx | SDK not configured, session failed |
| `.network` | 2xxx | timeout, bad URL, server error |
| `.card` | 3xxx | unsupported card, NFC transceiver missing |
| `.kernel` | 4xxx | EMV kernel not initialised |
| `.terminal` | 5xxx | preparation / registration / TSN failures |
| `.transaction` | 6xxx | invalid params, missing RRN, missing data |
| `.authentication` | 7xxx | login failed, location not granted |
| `.validation` | 8xxx | PIN length, env update |
| `.security` | 9xxx | encryption failed |
| `.generic` | — | custom errors, `somethingWentWrong` |

`EdfaException` wraps `EdfaError`:
```swift
exception.error        // EdfaError
exception.code()       // Int (matches Android)
exception.isHttpTimeout() -> Bool
EdfaException.with(anyError)   // converts any Error to EdfaException
EdfaError.custom(message: "…") // factory for ad-hoc errors
```

---

## SDK properties

```swift
plugin.SDK_VERSION            // "v1.0.0"
plugin.SDK_VERSION_TIMESTAMP
plugin.PARTNER                // "swift"
plugin.animationSpeedX        // Float — multiplier for card-tap animations
plugin.enableLogs             // Bool — enable verbose logging (dev only)
plugin.theme()                // SdkTheme — colors/fonts for the built-in ScanCardView
```

```swift
// Async properties (read after configure())
let config      = await plugin.configuration    // EdfapayConfiguration?
let merchant    = await plugin.merchantName     // String? from DownloadParams
let ttpToken    = await plugin.terminalTtpToken // String? ProximityReader JWT
```

---

## Key models

| Type | Description |
|---|---|
| `TxnParams` | Transaction parameters (amount, orderId, originalTransaction) |
| `Transaction` | Server transaction record with `bid`, `rrn`, `status`, `transactionNumber` |
| `TxnResponse` | Server response wrapping a `Transaction` + status code |
| `EdfaPayCredentials` | Login credentials (token or email/password) |
| `EdfapayConfiguration` | Crypto / timeout / variant configuration |
| `EnvironmentURLs` | Per-environment base URL and receipt URLs |
| `DownloadParams` | Terminal configuration downloaded after `initiate` |
| `TerminalInfo` | Active terminal metadata |
| `SessionDetail` | Active session metadata |
| `Pagination` | Page / per-page for history calls |
| `Reconcile` | Reconciliation result |
| `SdkLogin` | Session login response (sessionId, merchant info) |
| `Login` | Credentials-login response (before OTP) |
| `Terminal` | Available terminal for binding |
| `JSONValue` / `JSONObject` | Type-erased JSON value / dictionary |

---

## Enums

```swift
TransactionType  // .purchase .authorize .capture .refund .reversal .void .cashback .changePin .cardActivation
FlowType         // .detail .immediate .status
Env              // .development .staging .sandbox .production .demo .revamp
PaymentScheme    // .visa .mastercard .amex .discover .mada (and others)
PaymentMethod    // .card .cash .link …
AesMode          // .cbc .gcm
FunctionCode     // .fullTerminalConfiguration …
ThreatType       // jailbreak / debugger check identifiers
ReceiptType      // .transaction .reconciliation
Partner          // .saEdfaPay .pkDigikhata .other
```

---

## Threading

All callbacks fire on the caller's context (usually the main thread via `Task { @MainActor in }`). `EdfaPayCore` is a Swift actor — never access it directly; always go through `EdfaPayPlugin.shared`. The public API is `@unchecked Sendable`; closures you pass in must be `@Sendable`.

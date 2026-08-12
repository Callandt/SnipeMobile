# SnipeMobile

Mobile apps to manage [Snipe-IT](https://snipeitapp.com) assets, accessories, users, and locations. Scan QR codes, check in/out hardware, and edit data from your phone or tablet.

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-Support-yellow?logo=buymeacoffee)](https://buymeacoffee.com/Callandt)

## Get the app

### iOS / iPadOS
- **App Store** - [SnipeMobile](https://apps.apple.com/us/app/snipemobile/id6759792710)
- **TestFlight (beta)** - [join the beta](https://testflight.apple.com/join/TjDwstBE)

### Android
- Not on a store yet - build from this repo (see below)

## Requirements

### Shared
- A Snipe-IT instance with API access (API token required)

### iOS / iPadOS
- Xcode 16+
- iOS 18.0+

### Android
- Android Studio (recent stable) or JDK 17+
- Android 8.0+ (API 26)
- Project path: `Android/`

## Building

### iOS / iPadOS
1. Open `IOS:iPadOS/SnipeMobile.xcodeproj` in Xcode.
2. Select a simulator or device and press Run (⌘R).
3. On first launch, enter your Snipe-IT API URL and API token.

### Android
1. Open the `Android/` folder in Android Studio (or use Gradle from that folder).
2. Sync Gradle, then run on an emulator or device.
3. On first launch, enter your Snipe-IT API URL and API token.

```bash
cd Android
./gradlew :app:installDebug
```

## Features

- **Hardware & accessories**: list, search, scan QR codes, check-in/check-out, create and edit.
- **Licenses & components**: list, search, check-in/check-out, create and edit.
- **Consumables**: list, search, check-out, create and edit.
- **Maintenances**: list, view, create and edit maintenance records.
- **Audit**: scan and audit assets.
- **Users & locations**: view and navigate to assigned assets.
- **Management**: models, categories, status labels, companies, suppliers, and related catalogs.
- **Widgets**: home-screen overview for audits, maintenance, assets, and stock (iOS & Android).
- **Theme**: light/dark/system.
- **Language**: Dutch, English, French, Spanish, German, Chinese, Portuguese, Japanese, Italian, Korean, Russian, and Arabic.
- **Security**: optional biometrics on app open (Face ID / Touch ID).
- **iCloud** (iOS): settings (including API configuration) can sync via iCloud.

## License

MIT - see [LICENSE](LICENSE).

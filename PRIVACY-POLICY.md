# SnipeMobile – Privacy Policy
_Last updated: 12 August 2026_

SnipeMobile is an independent mobile client for Snipe-IT, available on iOS/iPadOS and Android. This app does not operate its own cloud service for your inventory data, it connects directly to your existing Snipe-IT instance.

## Data the app processes

### Snipe-IT data (assets, accessories, users, locations, etc.)
- The app displays and modifies data that already exists in your own Snipe-IT server.
- A local cache of that data may be stored on your device so the app can work offline and load faster.
- No copy of this inventory data is sent to any server controlled by the developer of SnipeMobile.

### API configuration (Snipe-IT URL and API token)
- The API URL and API token you enter are stored on your device.
- On **iOS/iPadOS**, they can optionally sync via Apple iCloud if you enable iCloud sync in the app settings.
- On **Android**, they are stored locally, the API token is encrypted using the Android Keystore. SnipeMobile does not offer iCloud-style settings sync on Android.
- These credentials are only used to communicate with your Snipe-IT instance (and, if configured, with Dell TechDirect for optional warranty lookup).
- The developer of SnipeMobile does **not** run any proxy or backend service that receives these credentials.

### Optional Dell TechDirect credentials
- If you enter Dell TechDirect client credentials, they are stored securely on your device and used only to request purchase/warranty details from Dell when you choose that feature.
- Those credentials are not sent to the developer of SnipeMobile.

### Biometric authentication
- If you enable the lock feature, SnipeMobile uses the platform biometric APIs to lock and unlock the app (Face ID / Touch ID on Apple devices, biometric unlock on Android).
- Biometric templates are never accessed by the app and never leave your device.

### Camera and photos
- The camera is used to scan QR and barcodes, and optionally to take photos for assets, audits, maintenance, check-in, or check-out.
- You may also select existing photos from your device library.
- Photos you add are uploaded to **your Snipe-IT server** as part of the action you perform. SnipeMobile does not send them to the developer.

### Widgets
- Home-screen widgets show summary counts derived from the local cache on your device (for example audits, maintenance, assets, or stock).
- Widget data stays on your device and is not sent to the developer.

### Notifications (Android)
- If you enable audit reminders, SnipeMobile schedules local notifications on your device.
- Notification content is generated locally from your cached Snipe-IT data and is not sent to the developer.

### Debug log export
- From Settings you can optionally export a debug log to share when reporting issues.
- That export is scrubbed so it does not include your server URL, API key, or Snipe-IT response data.
- Sharing only happens when you choose to export and send the file yourself.

## Analytics and tracking
- SnipeMobile does **not** use third‑party analytics SDKs.
- SnipeMobile does **not** collect advertising identifiers and does not show third‑party ads.

## Third parties
- All asset data is stored in and served from **your own Snipe-IT server**, which you or your organization operate.
- If you use Dell TechDirect integration, Dell processes the requests needed for that lookup under Dell’s own terms.
- Please refer to your Snipe-IT server’s hosting provider and configuration for details about how that server stores and protects data.

## Children’s privacy
SnipeMobile is intended for use by IT staff and organizations, not by children. The app does not knowingly collect personal information from children.

## Your rights
Because SnipeMobile works against your own Snipe-IT instance, requests to access, correct, or delete personal data should be directed to the administrator of that Snipe-IT server.

If your local law grants you specific privacy rights (for example under GDPR or similar regulations), these rights should be exercised primarily with the controller that operates your Snipe-IT instance.

## Contact
If you have questions about this privacy policy or SnipeMobile, you can contact:

**Avery Callandt**  
Email: avery.callandt@outlook.com

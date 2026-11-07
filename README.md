# Mac ID

Face unlock for the Mac you already own. SwiftUI, SF Symbols, Clerk (auth + Billing) and Meshy.

- **Setup:** one photo from the Mac's camera. **Meshy 7.1** (`ai_model: "meshy-7.1"`) builds your whole textured head. A second photo goes to **Meshy 6 Lite** (`meshy-6-lite`, mesh only), and that scan has to match the 7.1 head.
- **Unlock:** the camera acts like a depth sensor. Vision maps 76 face landmarks, a dot pattern is projected over the face in the UI, and an on-device match (face embedding + landmark geometry + blink/head-turn check) unlocks in about a second. Optionally each unlock also runs a Meshy 6 Lite scan against your 7.1 head (Settings → Unlock scan).
- **Free:** 30 face unlocks a day. When they run out, Mac ID asks for **Touch ID or your password** (system sheet).
- **Pro, $4/month:** unlimited face unlocks, bought inside the app through **Clerk Billing**.

## What Mac ID can and can't do

- macOS does not let third-party apps replace the login window. Mac ID adds its own full-screen lock when the Mac wakes or the screen saver stops **and macOS didn't already ask for a password**. Set *System Settings → Lock Screen → Require password after screen saver begins* to a long delay (for example 1 hour) and Mac ID covers the short wakes in between.
- A normal webcam has no depth sensor. Matching is appearance-based, so a good photo or video of you can fool it more easily than Face ID. Treat Mac ID as a convenience lock. Your macOS password still protects the Mac, and Force Quit (⌥⌘⎋) still works.
- A Meshy scan takes about a minute and costs credits, so it can't be the everyday unlock path on its own. That's why the default unlock is on-device and Meshy runs at setup (and optionally per unlock).
- **The Meshy API key is compiled into the app** (`Sources/MacID/Support/AppConfig.swift`), as requested. Anyone with the .dmg can pull it out of the binary and spend your credits. Rotate it if that happens; for a public release, put Meshy calls behind your own server.

## Project layout

```
project.yml                 XcodeGen spec (macOS 14+, Clerk SPM package)
Sources/MacID/
  App/        MacIDApp (window, menu bar, settings), AppModel (enroll + unlock flow)
  Camera/     AVFoundation capture, mirrored preview
  Face/       Vision analysis, matcher, liveness, depth-dot overlay
  Meshy/      Meshy client, 7.1 head + 6 Lite scan pipeline, OBJ shape compare, SceneKit head viewer
  Unlock/     30/day quota, Touch ID/password, full-screen lock windows
  Billing/    Clerk Billing: plan checks (has(feature:) / has(plan:)), billing data, in-app checkout sheet
  Views/      SwiftUI screens (SF Symbols throughout)
Support/      Info.plist (camera usage text, Clerk callback URL scheme), entitlements (sandbox, camera, network)
Resources/    App icon asset catalog (scripts/make-icon.py draws it), checkout.html for in-app payments
scripts/      build-app.sh, make-dmg.sh, make-pkg.sh, make-icon.py
web/pricing/  Clerk PricingTable page for the $4/month checkout
clerk/        billing.json for `clerk config patch`
marketing/    3D ad (HTML + 1080p MP4), app icon PNG
```

## 1. Clerk

Already set up in the **MacID** Clerk application (`app_3LnB9yZBw6rN1PYEFU3kGcLULPM`, development instance):

| What | Value |
| --- | --- |
| Publishable key | `pk_test_a2Vlbi1ncmlmZm9uLTE3ODkuY2xlcmsuYWNjb3VudHMuZGV2JA` (public by design; the build uses it by default) |
| Billing | On for users. Development instances use Clerk's test payment gateway, so no real charges. |
| Plans | `free_user` (Free, created by Clerk) and `pro` (Pro, $4.00/month, recurring, paid by the user) |
| Feature | `unlimited_unlocks`, attached to `pro` and included in the session token |
| SSO redirect allowlist | `app.macid.MacID://callback` (Google / Microsoft / Apple sign-in from the Mac app) |

`clerk/billing.json` holds the same billing config, so it can be re-applied with `npx -y clerk@latest config patch --file clerk/billing.json --dry-run` (then without `--dry-run`), for example to a production instance.

Before real customers can pay:

1. Create a production instance and connect Stripe (Dashboard → Billing → Settings). Apply `clerk/billing.json` and allowlist `app.macid.MacID://callback` there too.
2. Build with the production key: `CLERK_PUBLISHABLE_KEY=pk_live_… ./scripts/build-app.sh`, and put the same key in `web/pricing/index.html`.
3. Sign in with Apple needs an Apple Developer provisioning profile, so it's left out of the entitlements. Add it with `npx -y clerk@latest init --sign-in-with-apple` if you want it.

The app uses Clerk's prebuilt `AuthView` (sheet) and `UserButton` (toolbar). Pro is checked with `Clerk.shared.has(feature: "unlimited_unlocks") || Clerk.shared.has(plan: "pro")` after a `getToken(skipCache: true)` refresh, the native equivalent of `has()` in Clerk's web SDKs.

### Payments inside the app

**Plan & Billing** (sidebar) is a native SwiftUI screen built on ClerkKit's Billing APIs: the plans from Clerk with live prices, your subscription (status, period, next payment), saved cards, and payment history and statements.

**Subscribe**, **Change or Cancel**, **Add Card / Manage** and **Billing Details** open a sheet inside Mac ID:

- It runs Clerk's own `PricingTable` (checkout drawer) or the account billing page in a web view (`Resources/checkout.html`, `Billing/CheckoutWebView.swift`). Stripe's card form has no native macOS SDK, so the card form is Stripe's web form either way.
- The sheet uses the app's existing Clerk session: ClerkKit's device token (`@_spi(FrameworkIntegration) Clerk.shared.deviceToken`, the hook Clerk provides for exactly this) is attached to each request, the same way Clerk's Expo SDK runs clerk-js. Nobody signs in twice.
- Card details go from Stripe's form straight to Stripe. Nothing is stored on disk (non-persistent web data store).
- After a purchase the sheet closes, the session token is refreshed, and Pro unlocks right away.
- Test mode (`pk_test_…`): pay with card `4242 4242 4242 4242`, any future expiry, any CVC.

Requirements on the Clerk side: the **Native API** must be on (Dashboard → Native applications; the sheet tells you if it's off), and for a production instance add `https://sunela-tech.github.io` to the instance's allowed origins (the checkout page runs under that origin, see `AppConfig.checkoutOrigin`).

The browser version (`web/pricing/index.html`, live at https://sunela-tech.github.io/macid/web/pricing/ through `.github/workflows/static.yml`, which publishes the repo to GitHub Pages on every push) is kept as a fallback behind *Open in Browser*. The 3D ad is published the same way at https://sunela-tech.github.io/macid/marketing/mac-id-ad.html.

## 2. Build the app, .dmg and .pkg

Needs a Mac with **Xcode 26+** (Clerk's SDK requires Swift 6.2) and Homebrew.

```bash
./scripts/build-app.sh
```

```bash
./scripts/make-dmg.sh
```

```bash
./scripts/make-pkg.sh
```

Output: `build/Mac ID.app`, `build/MacID-1.0.0.dmg`, `build/MacID-1.0.0.pkg`. The app is universal (Apple silicon + Intel).

Without signing settings the app is ad-hoc signed and runs on the Mac that built it. To ship to other Macs, sign and notarize with your Developer ID:

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" DEVELOPMENT_TEAM=TEAMID CLERK_PUBLISHABLE_KEY=pk_live_xxx ./scripts/build-app.sh
```

```bash
xcrun notarytool store-credentials macid-notary --apple-id you@example.com --team-id TEAMID
```

```bash
SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=macid-notary ./scripts/make-dmg.sh
```

```bash
INSTALLER_IDENTITY="Developer ID Installer: Your Name (TEAMID)" NOTARY_PROFILE=macid-notary ./scripts/make-pkg.sh
```

To work in Xcode instead: `brew install xcodegen && xcodegen generate && open MacID.xcodeproj`, and run the MacID scheme.

### GitHub Actions

`.github/workflows/release.yml` builds the .dmg and .pkg on a macOS runner on every push to `main`, on pull requests, manually, and on `v*` tags (attaching them to a release). Download them from the run's **Artifacts**. To use a different Clerk app, set the repository variable `CLERK_PUBLISHABLE_KEY`. Add the signing secrets listed at the top of the file for signed, notarized builds.

## 3. Use it

1. Open Mac ID, sign in (top right), allow camera access.
2. **Face & Head → Scan My Face.** Look at the camera and move your head a little. Your face template is saved right away (encrypted, on this Mac). With *Build my 3D head with Meshy* on, Meshy 7.1 and 6 Lite run in the background (35 credits) and the head appears in a rotating 3D view with the match score.
3. **Lock Now** from the window or the menu bar icon, or let the Mac sleep. The lock screen scans automatically; *Use Touch ID* is always there.
4. Settings (⌘,): lock triggers, open at login, unlock scan mode, strictness, blink/head-turn requirement.

## Meshy details

| Step | Endpoint | Model | Credits |
| --- | --- | --- | --- |
| Full head at setup | `POST /openapi/v1/image-to-3d` (textured, GLB/OBJ/USDZ) | `meshy-7.1` | 30 |
| Depth scan at setup | `POST /openapi/v1/image-to-3d` (`should_texture: false`, OBJ) | `meshy-6-lite` | 5 |
| Optional per-unlock scan | same as above | `meshy-6-lite` | 5 each |

Photos go up as base64 data URIs; tasks are polled at `GET /openapi/v1/image-to-3d/{id}` and resume if the app quits mid-build. The 6 Lite mesh is compared to the 7.1 head with a scale-normalized chamfer distance (`MeshCompare.swift`); the pass mark is `AppConfig.meshMatchThreshold` (0.62). It hasn't been tuned on real scans yet, so adjust it after trying a few.

## The ad

`marketing/mac-id-ad.html` is a real-time three.js ad (open it in a browser) and `marketing/mac-id-ad.mp4` is the 20-second 1080p render. The MacBook Pro, MacBook Air, head and icons are all modeled in code, so no Apple artwork or third-party 3D assets are used.

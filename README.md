# Mac ID

Face unlock for the Mac you already own. SwiftUI, SF Symbols, Clerk (auth + Billing) and Meshy.

- **Setup:** one photo from the Mac's camera. **Meshy 7.1** (`ai_model: "meshy-7.1"`) builds your whole textured head. A second photo goes to **Meshy 6 Lite** (`meshy-6-lite`, mesh only), and that scan has to match the 7.1 head.
- **Unlock:** the camera acts like a depth sensor. Vision maps 76 face landmarks, a dot pattern is projected over the face in the UI, and an on-device match (face embedding + landmark geometry + blink/head-turn check) unlocks in about a second. Optionally each unlock also runs a Meshy 6 Lite scan against your 7.1 head (Settings → Unlock scan).
- **Free:** 30 face unlocks a day. When they run out, Mac ID asks for **Touch ID or your password** (system sheet).
- **Pro, $4/month:** unlimited face unlocks, sold through **Clerk Billing**.

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
  Billing/    Clerk Billing plan checks (has(feature:) / has(plan:))
  Views/      SwiftUI screens (SF Symbols throughout)
Support/      Info.plist (camera usage text, Clerk callback URL scheme), entitlements (sandbox, camera, network)
Resources/    Asset catalog with the app icon (scripts/make-icon.py draws it)
scripts/      build-app.sh, make-dmg.sh, make-pkg.sh, make-icon.py
web/pricing/  Clerk PricingTable page for the $4/month checkout
clerk/        billing.json for `clerk config patch`
marketing/    3D ad (HTML + 1080p MP4), app icon PNG
```

## 1. Set up Clerk

Following Clerk's Swift and Billing skills (github.com/clerk/skills):

1. Create an application at dashboard.clerk.com, or let the Clerk CLI do it: `npx -y clerk@latest init` from this folder. Note the **publishable key** (`pk_test_…`).
2. Enable Billing: Dashboard → Billing → Settings, or `npx -y clerk@latest enable billing --for user`. Development instances use Clerk's test gateway; production needs a connected Stripe account.
3. Create the plan in the **User Plans** tab: slug `pro`, $4.00/month, recurring. Add the feature `unlimited_unlocks` to it. To script it: `npx -y clerk@latest config patch --file clerk/billing.json --dry-run`, then without `--dry-run`, then attach the feature to the plan in Dashboard → Billing → Plans → Pro → Features.
4. If Organizations are on, set Membership to **optional** so personal (B2C) subscriptions work.
5. Register the native app with bundle ID `app.macid.MacID` (the Clerk CLI `init` does this; otherwise use the Native applications page in the Clerk Dashboard). Sign in with Apple needs an Apple Developer provisioning profile, so it's left out of the entitlements; add it with `npx -y clerk@latest init --sign-in-with-apple` if you want it.
6. Check the setup: `npx -y clerk@latest doctor`.

The app uses Clerk's prebuilt `AuthView` (sheet) and `UserButton` (toolbar). Pro is checked with `Clerk.shared.has(feature: "unlimited_unlocks") || Clerk.shared.has(plan: "pro")` after a `getToken(skipCache: true)` refresh, the native equivalent of `has()` in Clerk's web SDKs.

### Checkout page

Clerk's Swift SDK reads plans and subscriptions but has no native checkout, so **Upgrade to Pro** opens `web/pricing/index.html`, which mounts Clerk's `PricingTable` (checkout drawer included).

1. Put your publishable key in its `clerk-publishable-key` meta tag.
2. Host it anywhere (Vercel, Netlify, GitHub Pages). Production Clerk instances need that domain added in Clerk.
3. Build the app with `MACID_PRICING_URL=https://your-site/pricing`.

After paying, the user switches back to Mac ID (or clicks *Return to Mac ID*) and the app refreshes the plan.

## 2. Build the app, .dmg and .pkg

Needs a Mac with **Xcode 26+** (Clerk's SDK requires Swift 6.2) and Homebrew.

```bash
CLERK_PUBLISHABLE_KEY=pk_test_xxx MACID_PRICING_URL=https://your-site/pricing ./scripts/build-app.sh
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

To work in Xcode instead: `brew install xcodegen && xcodegen generate && open MacID.xcodeproj`, then set `CLERK_PUBLISHABLE_KEY` in the scheme's environment variables.

### GitHub Actions

`.github/workflows/release.yml` builds the .dmg and .pkg on a macOS runner (manually, or on `v*` tags, attaching them to a release). Set the repository variable `CLERK_PUBLISHABLE_KEY`; add the signing secrets listed at the top of the file for signed, notarized builds.

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

# Mac App Store release readiness

Version 1.2.1, build 8, dated 2026-09-11, is prepared locally. It has not been signed for the Store, uploaded, or submitted.

## Ready in the repository

- The bundle has a stable identifier, version, build number, productivity category, copyright, encryption declaration, and icon.
- The App Store candidate enables App Sandbox, user-selected read-write file access, and outgoing network client access for Send to endpoint….
- Save uses `NSSavePanel`. The app no longer needs direct Desktop access.
- The privacy manifest declares no tracking, collected data, or tracking domains. It declares UserDefaults with reason CA92.1 for Aparte's local preferences.
- The App Store build is universal for Apple silicon and Intel Macs.
- `make check-app-store` builds and runs a sandboxed, ad-hoc signed structural candidate, including a write through its real sandbox container, without touching App Store Connect. It is not upload proof.
- `make package-mas` can create the signed installer after the correct Apple certificates and provisioning profile exist. It verifies the profile's bundle, team, expiration, platform, and authorized entitlements, then validates the embedded profile against the signed app. It does not upload.
- Product-page text, review notes, privacy wording, and support wording are drafted.

## Human and Apple account gates

- Confirm that the Apple Developer team owns or can register `com.pocarles.aparte`.
- Create Apple Distribution and Mac Installer Distribution certificates for that team.
- Create a Mac App Store provisioning profile for the bundle identifier.
- Approve the icon and complete the packaged-app manual checklist.
- Host the privacy and support pages at public URLs.
- Capture compliant 16:10 Mac screenshots with no private writing visible.
- Decide the price, countries or regions, seller details, and release method.
- Create the App Store Connect record, then validate and upload the signed package. These external actions are outside this preparation pass.

## Data continuity

The current local build and the sandboxed Store build use different application-support locations. The existing local document remains untouched, but it will not appear automatically in the sandboxed app. Before replacing the daily local build, save the current note to a Markdown file and import or paste it into the Store build. A migration feature is unnecessary for new App Store customers, but Pierre-Olivier's existing local document needs this one-time handoff.

## Local commands

```sh
make check
make check-app-store
```

After the correct team certificates and profile are available:

```sh
APP_STORE_APP_IDENTITY="Apple Distribution: ..." \
APP_STORE_INSTALLER_IDENTITY="Mac Installer Distribution: ..." \
APP_STORE_PROVISIONING_PROFILE="/absolute/path/to/profile.provisionprofile" \
APP_BUILD_NUMBER="8" \
make package-mas
```

The packaging command creates `dist/Aparte-1.2.1.pkg`. Validate it against App Store Connect only after the app record exists. Upload only after an explicit release decision.

# Build Assessment

What this machine can construct, what it costs, and what building it revealed.

Measured on 21 September 2026 against `main` @ `ebda67f`, Flutter 3.44.8.

---

## Summary

The project **builds**. Every Android output format works: debug APK, release APK,
split-per-ABI APKs, and the Play Store app bundle. The toolchain needed no
installation — the SDK was already complete apart from `cmdline-tools`, which
builds do not require.

Building it surfaced **five defects that static analysis could not**, one of them
ship-blocking: the release APK had no network access.

---

## 1. Environment

| Component | State |
|---|---|
| Free disk before | 60.7 GB |
| Free disk after all builds | 50 GB |
| Consumed by one full build cycle | ~11 GB |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` |
| SDK platforms | 33, 34, 35, 36 |
| Build tools | 30.0.3, 33.0.0, 34.0.0, 35.0.0, 35.0.1, 36.0.0 |
| NDK | 23.1.7779620, 26.1.10909125, 27.0.12077973, 27.1.12297006, **28.2.13676358** |
| SDK licences | accepted |
| Gradle | 9.1.0 cached — exactly the wrapper version, so no download |
| JDK | 17 (`C:\Program Files\Java\jdk-17`) |
| `cmdline-tools` | **missing** |

`flutter doctor` flags the missing `cmdline-tools` as an Android toolchain issue.
It is **not needed to build** — only for `sdkmanager`, `avdmanager` and
`apkanalyzer`. One consequence is real and is covered in §6.

> The first disk reading showed 1.6 GB free. That was a transient state, not the
> steady figure — `df` and `Get-PSDrive` both reported 60.7 GB moments later.
> Worth re-measuring before concluding a build will not fit.

---

## 2. Verified build outputs

| Command | Artifact | Size | Time |
|---|---|---|---|
| `flutter build apk --debug` | `app-debug.apk` | 147 MB | 128 s |
| `flutter build apk --release` | `app-release.apk` | 43.8 MB | 147–243 s |
| `flutter build apk --release --split-per-abi` | `app-arm64-v8a-release.apk` | **15.4 MB** | 99 s |
| | `app-armeabi-v7a-release.apk` | 12.7 MB | |
| | `app-x86_64-release.apk` | 16.7 MB | |
| `flutter build appbundle --release` | `app-release.aab` | 44 MB | |

Incremental rebuilds land near 100–150 s once the Gradle daemon and caches are warm.

### Manifest facts

- `minSdk 24` — Android 7.0 and up
- `targetSdk 36`, `compileSdk 36`
- package `com.putercloud.puter_cloud_storage`
- signed with the **Android Debug** certificate (see §6)

---

## 3. Where the bytes go

The 43.8 MB release APK decomposes as:

| Component | Size | Share |
|---|---|---|
| Native libraries | 43.3 MB | **98.8%** |
| Dart + Java dex | 0.8 MB | 1.8% |
| Flutter assets | 0.1 MB | 0.2% |
| Resources | ~0 | — |

And the native libraries, by ABI:

| ABI | Size |
|---|---|
| `arm64-v8a` | 14.9 MB |
| `x86_64` | 16.2 MB |
| `armeabi-v7a` | 12.2 MB |

**This is the single most useful number here.** The app's own code is 0.8 MB. The
fat APK is 98.8% engine binaries, and it ships three copies of them so one file
works everywhere.

`--split-per-abi` therefore cuts the delivered download by **2.8×** for the ABI
that matters: 15.4 MB for `arm64-v8a`, which covers essentially every Android
phone sold in the last seven years. `x86_64` exists for emulators only.

---

## 4. What building revealed

None of these were visible to `flutter analyze`, and none would have appeared in
a debug build.

### 4.1 The release APK had no network access — ship-blocking

Flutter's template declares `android.permission.INTERNET` **only in the debug and
profile manifests**, where it exists so the tooling can attach for hot reload.
The main manifest had none.

So a debug build works perfectly and a release build cannot make a single network
call. The app installs, launches, and fails every operation — sign-in, listing,
transfer. For a cloud storage client that is total failure, and it would have
shipped.

Confirmed by dumping the built APK: `INTERNET` was absent. Now added to the main
manifest, along with `ACCESS_NETWORK_STATE` so the app can tell "no network"
apart from "server unreachable". Both verified present in the rebuilt APK.

### 4.2 The app label was the package name

`android:label="puter_cloud_storage"` — the launcher showed an identifier with an
underscore, not a product name. Now `Puter Cloud Storage`.

### 4.3 A documented security control was never implemented

`docs/security.md` §3 mandates that secure-storage entries be excluded from
auto-backup, and the checklist at line 114 requires `backup_rules.xml` and
`data_extraction_rules.xml`. **Neither file existed, and neither was referenced
from the manifest.**

The consequence is worse than a leaked token. The Keystore key behind
`flutter_secure_storage` is hardware-bound and never backed up, so a restore onto
another device would produce ciphertext nothing can decrypt — leaving the app
holding a corrupt credential it cannot distinguish from a valid one.

Both files now exist and are wired up via `android:fullBackupContent` and
`android:dataExtractionRules`. `device-transfer` is excluded separately from
`cloud-backup`, since omitting it leaves the token movable during a phone-to-phone
migration.

### 4.4 The fallback transport has no working library

`flutter_inappwebview` 6.1.5 — latest stable, October 2024 — does not build under
the Gradle 9.1.0 toolchain Flutter 3.44 generates.
`flutter_inappwebview_android` 1.1.3 calls
`getDefaultProguardFile('proguard-android.txt')`, which Gradle 9 rejects outright.
No stable release fixes it; only the unreleased `6.2.0-beta.3` moves.

The dependency was also entirely unused. It has been removed, and
`docs/adr/0002-webdav-primary-transport.md` records that **the WebView fallback is
currently a design intention, not a buildable option**. Phase 4 must resolve it.

### 4.5 Thirteen of seventeen dependencies were unused

Only `flutter_riverpod`, `flutter_secure_storage`, `dio` and `xml` were imported
anywhere. The rest were declared for future phases and were actively breaking the
build — `file_picker` pinned `compileSdk 34` against a transitive plugin demanding
36, so the build died on a mismatch that no code caused.

The pubspec now declares what the code uses, with the roadmap stack listed in a
comment against the phase that will add it. **A stale plugin cannot break a build
it is not part of.**

---

## 5. Recommended build outputs

| Purpose | Command | Delivered size |
|---|---|---|
| Sideload / direct distribution | `flutter build apk --release --split-per-abi` | 15.4 MB (`arm64-v8a`) |
| Play Store | `flutter build appbundle --release` | ~15 MB per device after Play splits |
| Testing on an emulator | `flutter build apk --release --split-per-abi` | 16.7 MB (`x86_64`) |
| Development | `flutter run` | — |

Ship the `arm64-v8a` split APK. The fat APK is only useful when you cannot know
the target device's ABI.

---

## 6. Constraints to account for

**`cmdline-tools` is missing, so AAB symbol verification cannot run.**
`flutter build appbundle` completes and produces the bundle, but then reports
`Release app bundle failed to strip debug symbols`. Flutter's check
(`_isAabStrippedOfDebugSymbols`, `gradle.dart:682`) returns `false` immediately
when `cmdlineToolsAvailable` is false, because it needs `apkanalyzer` to inspect
the bundle. **This is a verification gap, not necessarily a real failure** — the
bundle may be correctly stripped and simply unverifiable. Installing
`cmdline-tools` closes it:

```
sdkmanager --install "cmdline-tools;latest"
```

**NDK `27.1.12297006` is broken.** It is installed but missing
`toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe`. Do not pin
`ndkVersion` to it. Flutter 3.44 defaults to `28.2.13676358`, which is present and
intact, so the default is safe.

**Release builds are signed with the Android Debug key.** `android/app/build.gradle.kts`
sets `signingConfig = signingConfigs.getByName("debug")` with a template TODO. The
APK installs and runs, but cannot be published. A release keystore is required
before any distribution.

**Budget ~11 GB of disk per full build cycle**, and keep at least 15 GB free. The
first build downloads Gradle dependencies; later builds are cheaper but the
outputs and caches persist. Do not start a build below ~10 GB free.

**Phase 0 remains the gate.** Nothing in this document changes that. The build
proves the app compiles and packages; it does not prove the backend works, and it
does not answer the quota question that decides whether the product is viable.
`tool/spike/phase0_spike.dart` needs a Puter auth token.

---

## 7. Reproducing this assessment

```bash
flutter pub get
flutter analyze                                    # expect: No issues found
dart run tool/verify/verify_core.dart              # expect: 21/21 pass
dart run tool/verify/verify_transport.dart         # expect: 64/64 pass

flutter build apk --release --split-per-abi
ls -lh build/app/outputs/flutter-apk/*.apk

# Confirm the permissions actually reached the artifact — this is the check
# that catches §4.1, and it can only be run against a built APK.
"$ANDROID_HOME/build-tools/36.0.0/aapt2.exe" dump badging \
  build/app/outputs/flutter-apk/app-release.apk | grep -E "uses-permission|application-label"
```

Expect `android.permission.INTERNET`, `android.permission.ACCESS_NETWORK_STATE`,
and `application-label:'Puter Cloud Storage'`.

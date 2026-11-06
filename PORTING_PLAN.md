# Twilight on iOS, iPadOS, and visionOS

This started as a scope against Twilight 7.1.0 (`c2a0a038e94efc001abd7f8e7311c40163a44120`) and moonlight-ios 9.0.2 (`02dc978`). Pull requests #2 through #6 are on master (`494a982`). This file now records what those pulls landed and what is still open. It does not change the app.

Twilight for Mac is a fork of Moonlight Qt. This repository is a fork of [moonlight-ios](https://github.com/moonlight-stream/moonlight-ios). The clients share the GameStream protocol through moonlight-common-c (`f900dd4767759c7b9d0e93bcea666b55c69ea62f`). They do not share UI, settings storage, or a video renderer.

The submission worksheet is [APP_STORE.md](APP_STORE.md).

## What #2–#6 landed

### #2 — Rebrand, bitrate, overlay, Automatic codec

Merged to master as `494a982`.

- Display name Twilight on iPhone, iPad, and Apple TV. Bundle id `io.github.neguete10.twilight.ios` on both targets. That is not the Mac id `io.github.neguete10.twilight`.
- Moonlight's signing team `DM46QST4M7` is gone. Signing stays automatic. Simulator builds turn signing off.
- Preferences are `Twilight.sqlite` on iOS and iPadOS, and `Twilight_tvOS.bin` on tvOS.
- The bitrate list runs from 0.5 Mb/s to 1 Gbps (`TWILIGHT_BITRATE_MAX_KBPS`). There is no Unlimited notch. A stored value above 1 Gbps is kept until the slider moves. A stream never requests more than 1.5 Gbps (`TWILIGHT_BITRATE_SEND_CAP_KBPS`).
- The stats overlay includes `%.1f Mbps requested, %.1f Mbps estimated encoder target, %.1f Mbps measured`. The estimate is 80% of the request.
- Automatic offers AV1 Main 8 when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` is true, then HEVC when hardware HEVC exists, then H.264. PyroWave is not advertised. Xcode targets are still named Moonlight and Moonlight TV.

### #3 — Adaptive bitrate, DualSense triggers, microphone, Vision Pro prep

Merged into the phase 2 branch as `4593667`, and that branch is what #2 brought to master.

- Adaptive bitrate is off until the user turns it on. The worker calls `api/abr/capabilities` and changes the rate only when the body contains `runtime_bitrate`. Stock Sunshine and GeForce Experience do not implement that endpoint, so the launch bitrate stays put. The overlay appends `%.1f Mbps adaptive` while the worker is running. Adaptive requests are capped at 500 Mb/s even when the slider is higher.
- DualSense adaptive triggers go through `GCDualSenseAdaptiveTrigger` (off, feedback, weapon, vibration, slope feedback). Unmapped host effects turn that trigger off. Rumble stays on Core Haptics. There is no raw HID report.
- Microphone passthrough is off by default and exists only on iPhone and iPad. Capture is 48 kHz mono Opus, sent as ENet type `0x3003`. `NSMicrophoneUsageDescription` is on the iOS plist only. tvOS does not open a capture device.
- `LiSendRawControlStreamPacket` is not in the pinned common-c commit. A build phase runs `moonlight-common/apply-raw-control-packet.py` and inserts it into the checkout. The submodule pin is unchanged.
- `UIRequiredDeviceCapabilities` is `arm64`, so Designed for iPad is not blocked on Vision Pro. `UIPreferredDefaultInterfaceOrientation` is landscape right.
- CI includes a continue-on-error visionOS Simulator job. The Moonlight scheme has no native visionOS destination. The job says so and exits 0.

### #4 — iOS 27 launch, App Store worksheet, AV1, quit on host

Merged into the phase 3 branch as `b0e310c`.

- The iOS target uses one `UIScene`. `SceneDelegate` builds the window and loads `iPhone.storyboard` or `iPad.storyboard` (iPad, and Designed for iPad on visionOS, including `UIUserInterfaceIdiomVision`). tvOS still launches from its storyboard.
- The codec picker shows AV1 only when hardware decode works, matched by title. tvOS settings list Auto, H.264, HEVC, and AV1. A stored AV1 value on hardware that fails the runtime check is read back as Automatic. HDR can add AV1 Main 10 when the display supports HDR10. The host still has to offer that profile.
- **Quit App on Host** (`quitAppAfter`) is off by default. A user end of the stream can send the existing quit-app request. Core Data current model is `Twilight v1.12`. tvOS stores the same key in its settings bundle.
- `PrivacyInfo.xcprivacy` is in both app bundles. `APP_STORE.md` is the Connect worksheet. Release builds of both targets define `ENABLE_APP_STORE_RESTRICTIONS`.
- The about sheet shows the GPL text and the App Store distribution exception. Settings has no separate license row.

### #5 — Twilight shell

Merged into the phase 4 branch as `a66026a`.

- iPhone opens on the selected host's library. The host name and settings sit in the top bar. Hosts, pairing, wake, and removal stay in that shell. iPad, including Designed for iPad, keeps a host sidebar beside the library.
- App tiles are squircles. A Desktop app is a banner with Stream and Quit. Settings open as a sheet. HDR has no beta label.
- Stream start uses a launch card. In a stream, FPS, bitrate, and RTT sit in a HUD.
- tvOS still uses the previous host list.

### #6 — Layout, version row, landscape-only iPhone

Merged into the phase 5 branch as `5ac3f8f`.

- The shell bar stays in the safe area beside the collection view. The grid scrolls under it. The bar hides while a stream covers the grid and comes back when the stream ends, when the transition ends, and when the app returns to the foreground.
- Tiles use a 2:3 cover. The column count follows the width. The host sheet is an opaque card. Settings controls wrap inside the margins. The launch card's progress bar stays inside the card. Custom resolution is entered in the app.
- Settings shows `Version %@ (build %@)` after Quit App on Host.
- iPhone is landscape-only: `UISupportedInterfaceOrientations` is landscape left and landscape right, hosted controllers return that mask, and scene connect requests landscape geometry so an upright phone still opens in landscape. The launch screen is landscape. iPad still allows portrait and both landscapes.

## Still open

These were in the original scope, or they showed up while #2–#6 landed, and they are not done.

- A native visionOS target. The shipping binary is the iPad app. Reference clients for a later target are [Neo Moonlight](https://github.com/NeoVectorX/NeoMoonlight) and Moonlight XrOS ([moonlight-ios-vision](https://github.com/RikuKunMS2/moonlight-ios-vision)). A native target that consumes streamed game content can request `com.apple.developer.low-latency-streaming` only for a team Apple has allowed to use it. This build does not include that entitlement.
- App Store Connect: create the Twilight record, pick screenshots, the age rating, and the privacy questionnaire, then upload a Release archive. The steps are in `APP_STORE.md`. The signing team is still chosen in Xcode. It is not in the project.
- `MARKETING_VERSION` is still `9.0.2`, the moonlight-ios version this tree started from. Set Twilight's own version before the first upload if that number should not stay.
- The GeForce Experience 100 Mb/s attribute clamp is still inside moonlight-common-c. The settings screen does not say that a 1 Gbps choice is clamped there. Sunshine uses the requested bitrate.
- The stats overlay does not print a present-mode word. iPhone, iPad, Apple TV, and visionOS stay on the existing display-link lock (`preferredFrameRateRange` pinned to the stream frame rate). That is Twilight's ProMotion policy. Continuous VRR is not available on these platforms, and it should not be ported unless Apple exposes a continuous refresh range.
- tvOS was not restyled. It still uses the host list from before the Twilight shell.
- Device checks that CI cannot replace: a real stream, microphone passthrough, a DualSense, a launch on iOS 27 hardware, and the Designed for iPad window opening in landscape on Vision Pro.
- Publishing `LiSendRawControlStreamPacket` into moonlight-common-c, if that repository can take the commit. Until then the build-phase patch is the copy that compiles.

Explicitly not part of this port: PyroWave, a Core Audio spatial mixer, picture in picture, CoreHID, a GitHub update check, and the Mac quit-with-controller and cursor fixes.

## Platforms in this tree

| Target | What exists today | visionOS |
| --- | --- | --- |
| `Moonlight` (`TARGETED_DEVICE_FAMILY` 1,2) | iPhone and iPad. Deployment target iOS 15.0. One scene. iPhone storyboard and iPad storyboard. iPhone is landscape-only. iPad allows portrait and landscape. | No xrOS target. Designed for iPad is the visionOS path. The window opens in landscape right. |
| `Moonlight TV` (`TARGETED_DEVICE_FAMILY` 3) | Separate tvOS app. Shared sources under `Limelight/`. Settings in `Moonlight TV/Settings.bundle`. The host list is the pre-shell UI. | Not applicable. |

## Effort and feasibility

The tables below use the same scale as the original scope.

- **S** — a limit, a mask, or a label on a screen that already exists.
- **M** — a new setting or a new use of an API the app already links.
- **L** — a new capture pipeline, a common-c API that is not in the pin, or a platform with no public API for the behavior.

Feasibility: **Ships** means the Twilight behavior can be done with public APIs. **Partial** means a useful subset ships. **Unavailable** means there is no supported API.

# 1. Features carried from Twilight 7.1.0

## 1.1 Bitrate cap of 1 Gbps, with no Unlimited option

**Status: shipped in #2.**

The slider and the tvOS list accept 0.5 Mb/s through 1 Gbps. There is no Unlimited control. A stored value above 1 Gbps is kept until the user moves the control. The value copied into the stream configuration is clamped at 1,500,000 kbps.

GeForce Experience still clamps the NVIDIA bitrate attributes at 100 Mb/s inside `SdpGenerator.c`. That clamp was left in place. Saying so in the settings UI is still open. Sunshine reads the bitrate the client sends.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Ships | `bitrateTable` in `SettingsViewController.m`. |
| iPadOS | S | Ships | Same controller. |
| tvOS | S | Ships | `Moonlight TV/Settings.bundle/Root.plist` includes 1 Gbps. |
| visionOS, Designed for iPad | S | Ships | Inherits the iPad slider. |
| visionOS, native | S | Ships | Same limit, once a native settings screen exists. |

## 1.2 Opt-in adaptive bitrate (Vibepollo `/bitrate`)

**Status: shipped in #3.**

The setting is off until the user turns it on, on iPhone, iPad, and Apple TV. A worker off the decode and input threads calls `GET api/abr/capabilities`. The host counts as capable when the JSON body contains `runtime_bitrate`, including when that feature says `supported: false`. A failed or empty check logs and leaves the launch bitrate alone.

While the stream runs, the worker samples about once a second. It cuts the wire target to 70% on loss above 2%, any FEC failure, an RTT spike, or the poor-connection flag, and not more often than once a second. The floor is 5 Mb/s, or the user's bitrate when that is lower. After 10 seconds clean (loss at or below 0.5%) it raises the wire target by 5%, never above the user's bitrate. Adaptive requests are capped at 500,000 kbps. The value written to the host is the encoder rate: `wire * 0.80 - audio - 500` kbps. A rejected request is logged and the stream continues.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | M | Ships | Toggle plus the two HTTPS calls. |
| iPadOS | M | Ships | Same code as iOS. |
| tvOS | M | Ships | Toggle in the settings bundle. |
| visionOS, Designed for iPad | M | Ships | Inherits the iOS toggle and the worker. |
| visionOS, native | M | Ships | Same worker once a native toggle exists. |

## 1.3 Requested, target, and actual bitrate on the stats overlay

**Status: shipped in #2, adaptive suffix in #3.** The separate in-stream HUD (FPS, bitrate, RTT) shipped with the shell in #5. A present-mode word is still open. See [VRR](#17-vrr-handling).

The classic line is:

`%.1f Mbps requested, %.1f Mbps estimated encoder target, %.1f Mbps measured`

When adaptive bitrate has a live wire target, it appends `%.1f Mbps adaptive`.

Requested is the bitrate this stream asked for at launch. Estimated encoder target is 80% of that request. Measured is received video bytes over the stats window. The tvOS settings bundle already had a statistics-overlay toggle, and the stream view honors it. #3 did not add a second one.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Ships | `StreamManager` builds the line. |
| iPadOS | S | Ships | Shared stream view. |
| tvOS | S | Ships | Shared stream view and the existing settings-bundle toggle. |
| visionOS, Designed for iPad | S | Ships | The iPad overlay draws inside the iPad window. |
| visionOS, native | S | Ships | Same string, once a native stream view exists. |

## 1.4 DualSense adaptive triggers and rumble

**Status: shipped in #3.** Rumble was already Core Haptics. Adaptive triggers are the high-level GameController modes, not the Mac HID report.

`setAdaptiveTriggers` is delivered on the main queue. A `GCDualSenseGamepad` maps host effects onto off, feedback, weapon, vibration, and slope feedback. Effects the class cannot express turn that trigger off. Both triggers are cleared when the stream ends. Xbox pads and the on-screen controls are skipped. Trigger rumble and adaptive triggers stay separate callbacks.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | M | Partial | Rumble through Core Haptics. Triggers through `GCDualSenseAdaptiveTrigger`. |
| iPadOS | M | Partial | Same GameController path. |
| tvOS | M | Partial | `GCDualSenseGamepad` on tvOS 14.5+. |
| visionOS, Designed for iPad | M | Partial | The iOS binary's GameController code runs in the compatible app. |
| visionOS, native | M | Partial | Same framework once a native target links GameController. Still not HID. |

## 1.5 Microphone passthrough

**Status: shipped in #3 on iPhone and iPad.** tvOS stays without the toggle, which is the intended scope.

Capture is 48 kHz mono, 20 ms, Opus at 64 kbps, DTX off. The ENet payload is type `0x3003`: a 2-byte big-endian sequence, one channel, flags 0, then one Opus packet of at most 247 bytes. Denied permission, a missing input route, or a host that never plays the packets leaves the stream running. There is no audio background mode. Stock Sunshine does not decode `0x3003`.

The send function is inserted at build time because it is not in pin `f900dd47`. Moving that function into the published submodule is still open.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | L | Ships | `AVAudioEngine` plus the build-phase send. Foreground only. |
| iPadOS | L | Ships | Same capture. |
| tvOS | L | Unavailable | No toggle. The Siri Remote mic is not a general Opus uplink. |
| visionOS, Designed for iPad | L | Partial | The iOS path runs in the compatible app. A refused audio session must not drop the stream. |
| visionOS, native | L | Partial | Same usage string, once a native target has its own audio session. |

## 1.6 Automatic codec: AV1 or HEVC, never PyroWave

**Status: shipped in #2 and tightened in #4.**

Automatic sets AV1 Main 8 when hardware AV1 decode works, then HEVC when hardware HEVC exists, then H.264. moonlight-common-c takes AV1 when the host's RTSP DESCRIBE offers `AV1/90000`, otherwise HEVC, otherwise H.264. An explicit AV1 choice uses the same fallback. AV1 Main 10 is added when AV1 is in the mask, HDR is on, and the display supports HDR10. The iPhone and iPad picker hides the AV1 segment when the hardware check fails. tvOS cannot hide the row per device, so an unsupported stored AV1 value reads as Automatic.

This is not the Mac order. Twilight on Apple offers HEVC ahead of AV1 when HEVC hardware decode works. The iOS client prefers AV1 when the device can decode it. YUV 4:4:4 stays a Mac-only toggle. PyroWave is not a choice and is not advertised.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Ships | Mask in `prepareToStreamApp`. The picker drops AV1 when hardware decode is missing. |
| iPadOS | S | Ships | Same function. |
| tvOS | S | Partial | Automatic follows the same hardware check. The AV1 row cannot be hidden per Apple TV. |
| visionOS, Designed for iPad | S | Partial | Same mask as the iPad app. First-generation Vision Pro does not hardware-decode AV1, so Automatic is HEVC. |
| visionOS, native | S | Partial | Same rule once a native target calls the same selector. |

## 1.7 VRR handling

**Status: policy kept. The overlay label is still open.**

iPhone and iPad ProMotion panels are the displays Twilight refuses to treat as continuous VRR. This tree already pins `preferredFrameRateRange` so minimum, maximum, and preferred are the stream frame rate, and it clamps the stream to `UIScreen.maximumFramesPerSecond`. That is the behavior to keep.

Apple TV has no ProMotion panel. An `AVDisplayManager` mode switch was not added. visionOS composites at a fixed rate. A compatible iPad app's display link runs inside that compositor.

Remaining: when the stats overlay gains a present-mode word, print the fixed mode. Do not print VRR.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Partial | ProMotion stays locked to the stream rate. Continuous VRR is unavailable. |
| iPadOS | S | Partial | Same lock. External displays do not add an app-controlled VRR range. |
| tvOS | S | Partial | Display-link lock. No `AVDisplayManager` mode switch. |
| visionOS, Designed for iPad | S | Partial | The iPad lock runs inside a fixed compositor rate. |
| visionOS, native | S | Unavailable | No app-controlled VRR. |

## 1.8 Other Twilight 7.1.0 behavior

| Mac behavior | Carry? | Where it stands |
| --- | --- | --- |
| PyroWave, Metal or Vulkan, opt-in | No | Not advertised. This client has no PyroWave decoder. |
| Core Audio spatial mixer and head tracking | Later | Playback here is SDL and Opus. |
| Picture in picture | Later | The stream is a VideoToolbox display layer, not an `AVPlayerLayer`. |
| CoreHID raw mouse | No | iPad already has `GCMouse` through the controller code. |
| Game Mode | Already declared | Both Info.plists set `LSSupportsGameMode`. |
| Twilight HUD and performance graphs | HUD shipped, graphs no | #5 added the FPS, bitrate, and RTT HUD. Section 1.3 is the classic bitrate line. Performance graphs were not ported. |
| GitHub update check | No | Updates go through App Store Connect. |
| Separate bundle id so Local Network permission does not collide with Moonlight | Shipped | Section 2. The id is `io.github.neguete10.twilight.ios`. |
| Quit-with-controller crash fix, cursor and trackpad fixes | No | Those are in the Qt/SDL Mac shell. |
| Quit the app on the host | Shipped in #4 | `quitAppAfter`, default off. |

# 2. Rebranding

**Status: shipped in #2, with the version number and the Xcode target names left as they are.**

The name on the device is Twilight. User-facing strings do not present this app as Moonlight. The README says the project is a fork and that Moonlight has not endorsed it. The Xcode targets are still Moonlight and Moonlight TV, which is what a developer opens.

## Bundle id

Both targets use `io.github.neguete10.twilight.ios`. Designed for iPad on visionOS is that same binary. A separate tvOS id was not created.

`DEVELOPMENT_TEAM` `DM46QST4M7` is not set. The team is chosen in Signing & Capabilities when someone runs on a device. Simulator builds set `CODE_SIGNING_ALLOWED` to NO.

`MARKETING_VERSION` is still `9.0.2`. Changing it is part of the first App Store Connect upload, not something #2–#6 decided.

## Preference storage

- iOS file `Twilight.sqlite`.
- tvOS file `Twilight_tvOS.bin`, also the `NSUserDefaults` key.
- The current model is `Twilight v1.12`, after `Moonlight v1.11`. Lightweight migration keeps an existing Twilight install. A new bundle id does not open official Moonlight's database.
- The client unique id and the pairing certificate live in this store. A new file means a new pairing identity.

Settings keys inside the model (`bitrate`, `preferredCodec`, and the rest) kept their names.

## Strings and assets

Done:

- `CFBundleDisplayName` is Twilight on both plists.
- Usage strings, including the microphone string on iOS, describe Twilight.
- The app icon and the launch screen are Twilight's. The launch screen is landscape.
- The README describes Twilight and points at the Mac client. It does not add a personal name, and it does not add a license section. The license file stays `LICENSE.txt`. The about sheet is where the GPL notice is shown.
- The old in-settings license screen is gone. HDR has no beta label.

Left as they were on purpose:

- Help links and `CONN_TEST_SERVER` (`ios.conntest.moonlight-stream.org`) still call upstream infrastructure. `APP_STORE.md` tells review what that host is.
- Copyright headers in source files still name Moonlight Stream. Those are attributions, not the name on the device.

# 3. App Store readiness

**Status: the binary-side checklist from #4 is in the tree. The Connect record is not.** `APP_STORE.md` is the worksheet for the steps that still need a Mac and an Apple Developer account.

## Signing

- The publisher's own team, selected in Xcode. The upstream team id is already removed.
- App ID `io.github.neguete10.twilight.ios`, with the iOS and tvOS platforms on one record if both ship together.
- Archive the Release configuration. Release defines `ENABLE_APP_STORE_RESTRICTIONS` on the iOS target and on the tvOS target.
- No extra entitlements file was added. The low-latency streaming entitlement is for a later native visionOS target, and only if the team is allowed to use it.

## Entitlements

| Need | Entitlement | Where it stands |
| --- | --- | --- |
| Find hosts with `NSNetServiceBrowser` on `_nvstream._tcp` | None beyond `NSBonjourServices` | Unchanged |
| Wake-on-LAN directed broadcast | `com.apple.developer.networking.multicast` | Not added. Add it only if review or the console requires it |
| Microphone capture in the foreground | No entitlement. The usage string is the gate | Shipped on iOS |
| Mac hardened-runtime microphone exception | Do not copy it | Not an iOS entitlement |
| `com.apple.developer.low-latency-streaming` | visionOS only | Not in this binary. See [Vision Pro](#vision-pro) |

## Privacy strings and manifest

Present:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` = `_nvstream._tcp`
- `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` (Citrix X1 mouse)
- `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` = true, for user-specified hosts
- `NSMicrophoneUsageDescription` on the iOS target only
- `PrivacyInfo.xcprivacy` in both bundles. User defaults reason `CA92.1`. System boot time reason `35F9.1` for the SDL2 audio timer. Tracking is off and the collected-data array is empty.

The Connect privacy answers are written in `APP_STORE.md`. They still have to be entered there.

## Export compliance

Both Info.plists set `ITSAppUsesNonExemptEncryption` to false. `APP_STORE.md` says to answer **No** in Connect. The binary uses HTTPS through the system stack and AES inside moonlight-common-c, which is what upstream moonlight-ios ships with this flag. If that AES layer is later classified as non-exempt, the plist and the filing change at that time.

## Review risks

These are how the Release build tries to pass review:

- `ENABLE_APP_STORE_RESTRICTIONS` is on for Release of both targets. `DiscoveryManager` rejects a manually added IPv4 address that is not RFC 1918, link-local, or the CGN range. `AppListResponse` removes the default Steam entry and keeps a Steam app the user added. Debug builds do not define the macro. Store archives must be Release.
- The host is a computer the user owns. The UI is not a store.
- The name Twilight still has to be checked in App Store Connect. Do not use Moonlight's name, icon, or screenshots.
- The microphone string matches opt-in, foreground, host passthrough. Capture does not start at launch.
- `NSAllowsArbitraryLoads` and `ios.conntest.moonlight-stream.org` need the review note in `APP_STORE.md`.
- No in-app update check was ported.
- `UIRequiredDeviceCapabilities` is `arm64` on iOS and on tvOS.
- `UIRequiresFullScreen` is true.
- The app has no store and no account. The age rating follows the questionnaire for a client that displays whatever the user's computer sends.

## Designed for iPad on visionOS

- In App Store Connect, make the iOS app available on Apple Vision Pro as Designed for iPad. That does not require an xrOS target. This step is still open. It is in `APP_STORE.md`.
- The iPad storyboard is what that window loads, including when the idiom is Vision.
- Native visionOS (a full space, a native window scene, compositor-timed frames) is a later target. None of the features in section 1 require it.

## Vision Pro

This build runs as the existing iPad app. There is no native visionOS target, and the bundle id stays `io.github.neguete10.twilight.ios`.

`UIPreferredDefaultInterfaceOrientation` is `UIInterfaceOrientationLandscapeRight`, so the Designed for iPad window opens in landscape. iPhone rotation is landscape-only because `UISupportedInterfaceOrientations` lists only landscape left and landscape right (#6). iPad, which is the binary Vision Pro runs, still lists portrait and both landscapes. The preferred key does not change that iPad mask. The tvOS plist is unchanged.

A native target comes later. The reference clients are [Neo Moonlight](https://github.com/NeoVectorX/NeoMoonlight) and Moonlight XrOS ([moonlight-ios-vision](https://github.com/RikuKunMS2/moonlight-ios-vision)).

A native target that consumes streamed game content can request `com.apple.developer.low-latency-streaming`. The system turns that mode on when it has resources. This Designed for iPad build does not include the entitlement. A later native target should add it only for a team Apple has allowed to use it. Moonlight XrOS tells local device builds to remove the entitlement when the signing team does not have it, or the app will not sign.

# 4. GPL-3 and the App Store terms

This section is information about the licenses already in the tree. It is not legal advice. A lawyer should read the licenses and the Apple Developer Program License Agreement before a submission.

## What the tree is under

`LICENSE.txt` is the GNU General Public License version 3. After the standard GPL text, the file adds:

> App Store Distribution Exception
>
> As additional permission under section 7, you are allowed to distribute the software through an app store, even if that store has restrictive terms and conditions that are incompatible with the GPL, provided that the source is also available under the GPL with or without this permission through a channel without those restrictive terms and conditions.

The same paragraph was added to moonlight-common-c in commit `5a2632990f` ("Add section 7 exception for app store distribution", 2026-09-26). The submodule pin `f900dd47` is one commit ahead of that, so the pinned common-c license includes it.

GPL version 3, section 7, is the part of the license that allows additional permissions. Permissions that apply to the whole Program may be used by anyone who receives it. A later recipient may also remove them. Adding a new permission to code whose copyright you do not hold requires the copyright holders.

Other components keep their own licenses. The FFmpeg headers under `libs/FFmpeg` are LGPL 2.1 or later. Opus is the BSD license in `libs/opus`. SDL2 ships its own license. X1Kit is a separate submodule. The section 7 paragraph in `LICENSE.txt` does not relicense those.

The about sheet shows this text. The README does not have a license section.

## Why this comes up

The Free Software Foundation's longstanding position is that the App Store's usage rules are further restrictions, which the GPL (section 10, and the conveying rules in section 6) does not allow a distributor to add. That is the conflict the VLC App Store removal turned on, and it is why an additional permission exists at all. Upstream Moonlight chose to ship moonlight-ios on the App Store with the exception above. The Mac Twilight 7.1.0 build does not use that path: it is a Developer ID signed, notarized disk image, and the Mac README describes the Mac App Store package flag as optional and unused for that image.

This fork does not have copyright assignments from the Moonlight contributors. That fact decides what the fork can change.

## Options

1. **Keep the exception that is already in `LICENSE.txt`, and keep the source public.** The permission is already granted in the copy this fork received. Using it does not require a new grant. The exception's own condition is that source stays available under the GPL, with or without the extra permission, somewhere that does not carry the store's terms. A public git repository is that channel. Making the repository private would drop the condition the paragraph states. The about sheet offers the license. The README does not need a license section.

2. **Ask the Moonlight maintainers if a fork is what the paragraph covers.** The text says "you are allowed to distribute the software." It does not name forks, and it does not name Twilight. A written answer from the maintainers is the way to confirm they read it as covering a fork. That ask is optional for as long as the publisher is comfortable relying on the paragraph as written. It is the right ask if a store review, a mirror, or a lawyer wants something the paragraph does not say.

3. **Ask those copyright holders for a different exception or a dual license.** Relicensing the app to MIT, Apache, or a proprietary license, or writing a new exception, needs permission from the copyright holders of the GPL code that remains. This fork does not have that permission. New code written for Twilight can carry whatever terms its author attaches, and those terms do not replace the GPL on the Moonlight code they are combined with. A combined work stays under GPL-3.

4. **Remove the exception.** Section 7 allows a recipient to strip additional permissions. The file that remains is plain GPL-3, which is the text the App Store conflict is about. Removing the paragraph works against shipping on the store. There is no reason to remove it as part of the rebrand.

5. **Ship outside the App Store.** Ad-hoc, enterprise, or a direct sideload never accepts the store's usage rules, so it does not need the exception. It also does not meet the goal of an App Store release. TestFlight is still Apple's distribution and uses the store's signing.

The practical path that matches this repository is option 1: leave the exception in place, keep the git repository public under GPL-3, and keep the license notice in the about sheet rather than in the README. Option 2 is the conversation to open with the Moonlight maintainers if that reading needs to be confirmed. Option 3 is the conversation to open only if the goal changes from "ship this GPL fork" to "ship under some other license."

# What is left

#2 through #6 finished the feature carry-over that could be done in this tree, the rebrand, the Twilight shell, and the landscape-only iPhone app. The work that is still a person's to do, rather than another code pass on this branch:

1. Choose the signing team and install a device build.
2. Decide `MARKETING_VERSION` before the first upload.
3. Create the App Store Connect record from `APP_STORE.md`, including Designed for iPad on Vision Pro, and upload a Release archive.
4. Exercise microphone passthrough, a DualSense, a real stream, and an iOS 27 launch on hardware.
5. A native visionOS target, the tvOS shell, the GFE bitrate note, and a present-mode word on the overlay, if those are still wanted after the store record exists.

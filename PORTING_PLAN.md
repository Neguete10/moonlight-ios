# Twilight on iOS, iPadOS, and visionOS

Phase 1 is a scope. This document does not change the app. It compares [Twilight 7.1.0](https://github.com/Neguete10/twilight/releases/tag/v7.1.0) (`c2a0a038e94efc001abd7f8e7311c40163a44120`) with this tree (`02dc978`, moonlight-ios 9.0.2). The pinned `moonlight-common-c` is `f900dd4767759c7b9d0e93bcea666b55c69ea62f`.

Twilight for Mac is a fork of Moonlight Qt, rebuilt on Andy Grundman's `v6.2.0-metal-v9b` tree. This repository is a fork of [moonlight-ios](https://github.com/moonlight-stream/moonlight-ios). The two clients share the GameStream protocol through moonlight-common-c. They do not share UI, settings storage, or a video renderer. Carrying a Mac feature means reimplementing its behavior on the UIKit client, not compiling the Qt sources.

## Platforms in this tree

| Target | What exists today | visionOS |
| --- | --- | --- |
| `Moonlight` (`TARGETED_DEVICE_FAMILY` 1,2) | iPhone and iPad. Deployment target iOS 15.0. Storyboards `iPhone.storyboard` and `iPad.storyboard`. | No xrOS target. A compatible iPad app is the only visionOS path available without a new target. |
| `Moonlight TV` (`TARGETED_DEVICE_FAMILY` 3) | Separate tvOS app. Same sources under `Limelight/`, settings in `Moonlight TV/Settings.bundle`. | Not applicable. |

"Designed for iPad" on visionOS runs the iOS binary inside a visionOS window. It picks up iOS code changes and does not pick up a native immersive renderer. A native visionOS app would be a new target (CompositorServices or a UIKit-on-xrOS scene). That target is out of scope until the iPad app is the product.

Both targets currently use the bundle id `com.moonlight-stream.Moonlight`, the display name Moonlight, and `DEVELOPMENT_TEAM` `DM46QST4M7`. Those three values belong to the upstream Moonlight app. They have to change before any Twilight build is signed or submitted. See [Rebranding](#rebranding).

## Effort and feasibility

Effort:

- **S** — the screen, callback, or request already exists. The change is a limit, a mask, or a label.
- **M** — a new setting or a new use of an API the app already links (GameController, VideoToolbox, the existing HTTPS client).
- **L** — a new capture pipeline, a moonlight-common-c API that is not in the pin, or a platform with no public API for the behavior.

Feasibility:

- **Ships** — the Twilight behavior can be done with public APIs on that platform.
- **Partial** — a useful subset ships. The Mac behavior does not.
- **Unavailable** — there is no supported API, or the feature would not function.

# 1. Features to carry from Twilight 7.1.0

The seven behaviors below are the Phase 1 feature set. A short list of other 7.1.0 behavior follows them.

## 1.1 Bitrate cap of 1 Gbps, with no Unlimited option

Twilight (`app/settings/bitrate_choice.h`):

- The slider and the typed field accept 0.5 Mb/s through 1 Gbps (`kMinKbps` 500, `kMaxKbps` 1,000,000). There is no Unlimited control.
- A stored value of 500000, or the word `unlimited`, loads as 500 Mb/s. It is not remapped to the top of the slider. A stale `bitrateunlimited` key is ignored.
- A stored number outside the field is kept until the user changes it. New input above 1 Gbps is rejected.
- The number placed in the stream configuration is capped at 1,500,000 kbps (`kAbsoluteSendCapKbps`).
- Sunshine reads `x-ml-video.configuredBitrateKbps` as the value the client sends. The overlay's encoder-target estimate is 80% of that request (the FEC budget). The label says it is an estimate.
- GeForce Experience still clamps the NVIDIA bitrate attributes at 100 Mb/s. That clamp lives in `SdpGenerator.c` in moonlight-common-c (`adjustedBitrate > 100000`), and the pinned iOS submodule has the same clamp. Sunshine is unaffected because it uses `configuredBitrateKbps`.

This tree (`Limelight/ViewControllers/SettingsViewController.m`):

- The iPhone and iPad slider is a table of fixed notches from 0.5 Mb/s to 150 Mb/s. The top entry is `150000` kbps. There is already no Unlimited notch.
- `Moonlight TV/Settings.bundle/Root.plist` lists the same ceiling, 150 Mb/s, as a multi-value setting.
- The chosen integer is stored in Core Data and copied into `StreamConfiguration.bitRate`.

Work:

- Raise the iOS slider and the tvOS multi-value list so the highest choice the user can make is 1,000,000 kbps, and the lowest stays 500 kbps.
- Keep the control as a finite list or a finite slider. Do not add an Unlimited segment.
- On load, leave a stored value above 1 Gbps unchanged until the user moves the control, matching Twilight. This store has never written the string `unlimited`, so that legacy word has nothing to migrate.
- Before `LiStartConnection`, clamp the outgoing value at 1,500,000 kbps.
- Leave the GFE 100 Mb/s attribute clamp inside moonlight-common-c. Document it in the settings UI so a 1 Gbps choice is not surprising on GeForce Experience: Sunshine can use the request, GeForce Experience will not.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Ships | `bitrateTable` in `SettingsViewController.m` and the bitrate label in `iPhone.storyboard`. |
| iPadOS | S | Ships | Same controller, `iPad.storyboard`. |
| tvOS | S | Ships | Extend `Moonlight TV/Settings.bundle/Root.plist`. The focus engine already edits this list. |
| visionOS, Designed for iPad | S | Ships | Inherits the iPad slider. |
| visionOS, native | S | Ships | Same limit, applied when a native settings screen exists. The cap itself is not a renderer feature. |

## 1.2 Opt-in adaptive bitrate (Vibepollo `/bitrate`)

Twilight (`app/streaming/adaptive_bitrate.h`, `adaptive_bitrate.cpp`, `app/backend/nvhttp.cpp`):

- The setting `enableAdaptiveBitrate` is off until the user turns it on.
- A worker thread, separate from the renderer and the input loop, calls `GET api/abr/capabilities` on the existing paired HTTPS client.
- The host is treated as capable when the JSON body contains `"runtime_bitrate"`. Vibepollo returns that feature name with `supported: false` when the client, rather than the host, decides the rate. Twilight treats the feature name as the signal. A failed or empty capability check logs and leaves the launch bitrate alone.
- While the stream runs, the worker samples about once a second. It cuts the wire target to 70% on loss above 2%, any FEC failure, an RTT spike, or the poor-connection flag, and not more often than once a second. The floor is 5 Mb/s, or the user's bitrate when that is lower. After 10 seconds clean (loss at or below 0.5%), it raises the wire target by 5%, and never above the user's bitrate.
- The user's bitrate is capped at 500,000 kbps for this controller (`kHostBitrateLimitKbps`), even when the slider is higher. The initial stream configuration can still carry the higher slider value.
- The value written to the host is the encoder rate, not the wire rate: `wire * 0.80 - audio - 500` kbps, with audio assumed at 512 kbps stereo on a LAN and 96 kbps stereo remotely, scaled by channel pairs. The request is `bitrate?bitrate=<kbps>` (`NvHTTP::setBitrate`). The host's XML `bitrate` element is the applied value. A rejected request is logged and the stream continues.

This tree:

- `HttpManager` already speaks the paired Sunshine/GFE HTTPS API. It has no `/bitrate` or `api/abr/capabilities` call.
- There is no adaptive-bitrate setting in the storyboards or the tvOS settings bundle.
- `StreamManager` already surfaces a poor-connection warning. That flag is the same input Twilight's worker ORs into a cut.

Work:

- Add an opt-in toggle, default off, on iPhone, iPad, and tvOS.
- Add the two requests on the existing HTTPS client. Use the same certificate and host address as launch and resume.
- Port the controller rules above. Keep the worker off the decode and input threads.
- If the capability check fails, or the body has no `runtime_bitrate`, do not change the bitrate and do not fail the stream.
- Cap adaptive requests at 500,000 kbps. Show the live wire target on the stats overlay (section 1.3).
- Stock Sunshine and GeForce Experience do not implement this endpoint. The feature stays off for those hosts even when the toggle is on.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | M | Ships | New toggle plus two HTTPS calls. No new system permission. |
| iPadOS | M | Ships | Same code as iOS. |
| tvOS | M | Ships | Same client. The toggle lives in the settings bundle. |
| visionOS, Designed for iPad | M | Ships | Inherits the iOS toggle and the worker. |
| visionOS, native | M | Ships | Same worker once a native toggle exists. The endpoint is not platform-specific. |

## 1.3 Requested, target, and actual bitrate on the stats overlay

Twilight (`BitrateChoice::formatBitrateOverlay`, `app/streaming/stats.cpp`):

The classic stats overlay includes one bitrate line:

`%.1f Mbps requested, %.1f Mbps estimated encoder target, %.1f Mbps measured`

When adaptive bitrate has a live wire target, it appends `%.1f Mbps adaptive`.

- Requested is the bitrate this stream asked for at launch (`streamRequestedBitrateKbps`).
- Estimated encoder target is 80% of that request. It is not clamped by the GeForce Experience 100 Mb/s cap or by the 500 Mb/s `/bitrate` cap.
- Measured is the smoothed average of received video bytes.
- The separate Twilight HUD (frame rate, bitrate, latency, End) is a second overlay and is off by default. This phase carries the classic line, not that HUD.

This tree (`StreamManager.getStatsOverlayText`, `StreamFrameViewController`):

- A `UITextView` overlay already updates about once a second when the stats overlay setting is on.
- The text is resolution, FPS, codec name, network drop percentage, RTT, and host processing latency. It does not include a bitrate.
- `video_stats_t` in `Connection.h` counts frames and host latency. It does not count bytes, so a measured rate has to be added beside the existing frame counters.
- The tvOS settings bundle has no stats-overlay toggle. The shared stream view can draw the overlay once the setting is reachable on tvOS.

Work:

- Record received video bytes in the existing one-second stats window.
- Extend the overlay string with requested, estimated encoder target (80% of requested), and measured megabits per second, in that order, plus the adaptive wire target when the worker is running.
- Add the tvOS toggle next to the other video options.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Ships | `StreamFrameViewController` already owns the overlay. |
| iPadOS | S | Ships | Shared stream view. |
| tvOS | S | Ships | Shared stream view, plus a settings-bundle toggle that is missing today. |
| visionOS, Designed for iPad | S | Ships | The iPad overlay draws inside the iPad window. |
| visionOS, native | S | Ships | Same string, once a native stream view exists. |

## 1.4 DualSense adaptive triggers and rumble

Twilight (`app/streaming/session.cpp`, `app/streaming/input/dualsense_effects.*`, `dualsense_hid_mac.mm`, `gamepad.cpp`):

- Rumble and trigger rumble are the existing Moonlight callbacks (`clRumble`, `clRumbleTriggers`).
- Adaptive triggers are a later callback, `ConnListenerSetAdaptiveTriggers`. Sunshine sends them as control packet `0x5503`: controller index, event flags, a type byte and 10 parameter bytes per trigger.
- Twilight copies that payload into the 47-byte `DS5EffectsState` SDL already uses, then calls `SDL_GameControllerSendEffect`. If SDL refuses the report, the Mac build writes a USB output report (id `0x02`, 48 bytes) or a Bluetooth output report (id `0x31`, 78 bytes, CRC32) through IOHID.
- That HID fallback is macOS-only. `DualSenseHidOutput` returns false on other platforms.

This tree:

- `ControllerSupport` already implements `rumble` and `rumbleTriggers` with `HapticContext` (`CHHapticEngine` continuous events, amplitude scaled by 65535).
- On iOS 14 and tvOS 14, a controller that advertises `GCHapticsLocalityHandles` is reported as `LI_CCAP_RUMBLE`, and one that advertises `GCHapticsLocalityTriggers` is reported as `LI_CCAP_TRIGGER_RUMBLE`.
- A `GCDualSenseGamepad` (iOS 14.5 / tvOS 14.5) is reported to the host as `LI_CTYPE_PS`.
- The pinned `Limelight.h` declares `ConnListenerSetAdaptiveTriggers`. `Connection.m` initializes connection callbacks through `setControllerLED` and does not assign `setAdaptiveTriggers`. Host `0x5503` packets are ignored.
- There is no IOHID, and an App Store build cannot add one. Raw DualSense output reports are a macOS path.

Work for rumble:

- Keep the Core Haptics motors. Confirm on a DualSense that handle rumble and trigger rumble both fire when the host sends them, on iPhone, iPad, and Apple TV. The code path is already shared.
- Trigger rumble (motors) and adaptive triggers (resistance effects) stay separate callbacks, as they are in Twilight.

Work for adaptive triggers:

- Assign `setAdaptiveTriggers` and deliver the effect on the main queue, the same way `rumbleTriggers` is delivered.
- When `controller.extendedGamepad` is a `GCDualSenseGamepad`, map the host effect type onto `GCDualSenseAdaptiveTrigger`: off, feedback, weapon, vibration, and slope feedback. Those are the modes the GameController framework exposes.
- Effects that do not correspond to one of those modes turn that trigger off. The Mac HID report can represent effect types the iOS class cannot. The iOS result is a subset of the host effect, which is the public API Apple ships.
- Clear both triggers when the stream ends, including when the app leaves the stream view.
- Skip controllers that are not a DualSense. An Xbox pad and the on-screen controls have no adaptive triggers.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | M | Partial | Rumble already ships through Core Haptics. Adaptive triggers ship as `GCDualSenseAdaptiveTrigger` modes, not as raw HID. Needs a DualSense paired over Bluetooth. |
| iPadOS | M | Partial | Same GameController path. USB-C pairing of a DualSense uses the same `GCController`. |
| tvOS | M | Partial | `GCDualSenseGamepad` is available on tvOS 14.5+, and the deployment target is newer. Apple TV pairs a DualSense from the system Bluetooth UI. The same mode mapping applies. |
| visionOS, Designed for iPad | M | Partial | The iOS binary's GameController code runs in the compatible app. A DualSense paired to the Vision Pro is a `GCController`. |
| visionOS, native | M | Partial | Same framework once a native target links GameController. Still the high-level trigger modes, not HID. |

## 1.5 Microphone passthrough

Twilight (`app/streaming/audio/microphone/`):

- Opt-in. `MicrophoneCapture::start` returns false when permission is missing, the control stream is not encrypted, or the device cannot be opened. A false return must not fail the stream.
- Capture is 48 kHz mono, 20 ms (960 samples), Opus at 64 kbps, DTX off, so a quiet mic still produces packets.
- The ENet payload is packet type `0x3003`: a 2-byte big-endian sequence, a channel count of 1, a flags byte of 0, then one Opus packet. The Opus packet is at most 247 bytes, because moonlight-common-c copies the control payload into a 256-byte buffer with a 4-byte header (`paylen` must be 251 or less).
- The bytes are sent with `LiSendRawControlStreamPacket`. Stock Moonlight has no microphone path. Stock LizardByte Sunshine does not decode `0x3003`. GeForce Experience does not receive it. The host that plays the audio is a Vibepollo / Vibelight build. The older `0x5510` microphone header and `LiSendMicrophoneOpusDataEx` are different protocols, and Twilight does not emit them.

This tree:

- Opus is already linked, and the stream already decodes host audio with `OpusMSDecoder`.
- There is no microphone session, no `NSMicrophoneUsageDescription`, and no privacy manifest.
- `LiSendRawControlStreamPacket` is not declared in `Limelight.h` at the iOS pin `f900dd47`, and it is not declared at Twilight's own submodule pin `7feb0a66` either. Twilight's capture file calls it. The iOS port needs that symbol in moonlight-common-c before any packet can be sent on the encrypted control stream. Adding a side UDP socket would be a different protocol than 7.1.0.

Work:

- Add `LiSendRawControlStreamPacket` to the pinned moonlight-common-c (encrypted control stream, caller-supplied packet type and payload, the existing 256-byte ceiling). Keep the payload layout identical to Twilight so a Vibepollo host accepts it.
- Capture with `AVAudioEngine`'s input node, convert to 48 kHz mono, encode 20 ms Opus frames with the linked libopus, and send them only after the control stream is up.
- Add an opt-in toggle, default off. Denied permission, a missing input route, or a host that never asked for audio leaves the stream running.
- Add `NSMicrophoneUsageDescription` that says the microphone is sent to the user's own streaming host. Do not start the capture engine until the toggle is on.
- Stop capture when the stream ends. Do not add the `audio` background mode; the stream UI is in the foreground, and a background mode is a separate review question.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | L | Ships | `AVAudioEngine` plus the missing common-c send. Foreground only. The host must understand `0x3003`. |
| iPadOS | L | Ships | Same capture. iPad mic and connected headsets both appear as the input route. |
| tvOS | L | Unavailable | The Siri Remote microphone is not a general capture device for a continuous Opus uplink, and a tvOS mic prompt for PC game chat is a review risk with no useful hardware behind it. Do not add the toggle on tvOS. |
| visionOS, Designed for iPad | L | Partial | The iOS permission prompt and `AVAudioEngine` path run in the compatible app. Routing is the headset mic, and visionOS may refuse the session even when iPadOS would allow it. Failure must not drop the stream. |
| visionOS, native | L | Partial | A native target can request the microphone with the same usage string. It still depends on the common-c send, and it needs its own audio session design. |

## 1.6 Automatic codec: AV1 or HEVC, never PyroWave

Twilight (`Session` video-format selection in `app/streaming/session.cpp`, codec list in `app/gui/ui/v2/SettingsSheetV2.qml`):

- The settings list is Automatic, H.264, HEVC, and AV1. PyroWave is appended only when a PyroWave backend was compiled (`hasPyroWaveVulkan` or `hasPyroWaveMetal`).
- Automatic builds a candidate list of AV1, then HEVC, then H.264, including the 10-bit and 4:4:4 profiles the user enabled. It never appends `VIDEO_FORMAT_PYROWAVE*`. Those four formats are inserted only for the forced PyroWave choice, which replaces the list.
- On Apple platforms, if HEVC hardware decode works, AV1 is deprioritized: it stays in the mask, and HEVC is offered first. HDR with no HEVC hardware decoder leaves AV1 at the top. H.264 remains the last fallback.
- The Mac README states the same rule: Automatic stays on HEVC or AV1 and does not advertise PyroWave.

This tree (`MainFrameViewController.prepareToStreamApp`, `Utils av1HardwareDecodeSupported`):

- The storyboard segments are H.264, HEVC, AV1, and Auto. AV1 is removed when `VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1)` is false. The remaining segments are matched by title. There is no PyroWave segment.
- Automatic sets AV1 Main 8 when that hardware check passes, then HEVC when hardware HEVC exists, then H.264. moonlight-common-c takes AV1 when the host's RTSP DESCRIBE offers `AV1/90000`, otherwise HEVC, otherwise H.264. An explicit AV1 choice uses the same fallback.
- AV1 Main 10 is added when AV1 is in the mask, HDR is on, and `AVPlayer.availableHDRModes` includes HDR10. HEVC Main 10 is the HDR fallback. The host still has to report `SCM_AV1_MAIN10` before common-c selects the 10-bit AV1 profile.
- The tvOS settings bundle lists Auto, H.264, HEVC, and AV1 (`preferredCodec` 0, 1, 2, 3). The system Settings bundle cannot hide a row per device, so a stored AV1 value on hardware that fails the runtime check is read back as Automatic.
- Hardware AV1 decode is an A17 Pro / M3-class feature and later. The check is `VTIsHardwareDecodeSupported`, not a device list. Apple TV models through the A15, and the first Vision Pro (M2), do not report hardware AV1. Automatic on those devices is HEVC, then H.264.

YUV 4:4:4 stays a Mac-only toggle. This client does not advertise PyroWave.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Ships | Mask change in `prepareToStreamApp`. The VideoToolbox decoder already accepts AV1 and HEVC. PyroWave is omitted. |
| iPadOS | S | Ships | Same function. AV1 appears on iPad models whose SoC reports hardware AV1. |
| tvOS | S | Partial | Automatic prefers AV1 only when `VTIsHardwareDecodeSupported` is true, otherwise HEVC. The settings row cannot be hidden per device; an unsupported AV1 value is read as Automatic. No PyroWave. |
| visionOS, Designed for iPad | S | Partial | Same mask as the iPad app. First-generation Vision Pro does not hardware-decode AV1, so Automatic is HEVC. |
| visionOS, native | S | Partial | Same rule once a native target calls the same selector. Still no PyroWave. |

## 1.7 VRR handling

Twilight (`app/streaming/video/ffmpeg-renderers/vt_metal.mm`):

- Present modes are Auto, Fixed, VRR, and No VSync.
- Auto selects VRR only when `NSScreen` reports a refresh-interval range and the window is fullscreen. Otherwise it uses fixed vsync, or no vsync when vsync is off.
- A ProMotion display (`displayUpdateGranularity > 0`, the MacBook Pro panels) is detected as a range and then treated as a fixed display at its maximum rate. Twilight's comment says those panels only hit a few discrete rates (120 Hz, 60 Hz, and a few lower ones) and behave badly if driven as continuous VRR. A developer flag can override that.
- Real VRR presentation waits on `present(afterMinimumDuration:)` using average GPU time, optionally the frame PTS delta, and forces immediate frame pacing.
- The stats overlay prints the active mode as `VRR`, `fixed vsync`, or `no vsync`.

This tree (`VideoDecoderRenderer.start`, `MainFrameViewController.prepareToStreamApp`):

- On iOS 15 and tvOS 15, the display link's `preferredFrameRateRange` is pinned so minimum, maximum, and preferred are all the stream frame rate. That asks ProMotion to lock to the stream rate. It is the fixed-rate behavior, not Mac VRR.
- The requested frame rate is clamped to `UIScreen.maximumFramesPerSecond`.
- Frame pacing, when enabled, holds one frame if the measured display rate is at least 90% of the stream rate.
- There is no present-mode setting.

What each platform can do:

- iPhone and iPad ProMotion panels are the same class of display Twilight refuses to treat as VRR. The matching behavior is the one this tree already has: lock the display link to the stream frame rate, and clamp the stream to the panel's maximum. Do not port `present(afterMinimumDuration:)` as if the panel were a variable-refresh monitor. An external display on iPadOS does not give an app HDMI VRR.
- Apple TV has no ProMotion panel. `AVDisplayManager` can request a content refresh rate for video playback. That is a fixed mode switch, not VRR, and it fights the GameStream frame pacer. Leave tvOS on the display-link lock.
- visionOS composites at a fixed rate (90 Hz on the first Vision Pro). A compatible iPad app's display link runs inside that compositor. A native app's CompositorServices frame schedule is also fixed. There is no VRR present mode to select.

Work for this phase is the policy, not a new renderer:

- Treat iPhone, iPad, Apple TV, and visionOS as fixed-refresh, using the existing display-link lock and the existing FPS clamp.
- When the stats overlay gains a present-mode word (section 1.3), print the fixed mode. Do not print VRR.
- Revisit VRR only if Apple later exposes a continuous refresh range to these platforms. The Mac Metal present path is not that API.

| Platform | Effort | Feasibility | Notes |
| --- | --- | --- | --- |
| iOS | S | Partial | ProMotion stays locked to the stream rate, which is Twilight's ProMotion policy. Continuous VRR is unavailable. |
| iPadOS | S | Partial | Same lock. External displays do not add an app-controlled VRR range. |
| tvOS | S | Partial | Keep the display-link lock. Do not add an `AVDisplayManager` mode switch in this phase. |
| visionOS, Designed for iPad | S | Partial | The iPad lock runs inside a fixed compositor rate. |
| visionOS, native | S | Unavailable | No app-controlled VRR. A native target would schedule frames on the compositor's fixed rate. |

## 1.8 Other Twilight 7.1.0 behavior

These are in the 7.1.0 release and are not part of the seven items above. They are listed so a later phase does not assume they came along.

| Mac behavior | Carry? | Why |
| --- | --- | --- |
| PyroWave, Metal or Vulkan, opt-in | No | Automatic must not advertise it, and this client has no PyroWave decoder. Forcing it would require a new renderer and a host that encodes PyroWave. |
| Core Audio spatial mixer and head tracking | Later | Playback here is SDL and Opus, not the Mac Core Audio renderer. A separate audio project. |
| Picture in picture | Later | iOS picture in picture expects an `AVPlayerLayer`. The stream is a VideoToolbox display layer. tvOS and visionOS windowing are different again. |
| CoreHID raw mouse | No | macOS IOHID. iPad already has `GCMouse` through the existing controller code. |
| Game Mode | Already declared | Both Info.plists set `LSSupportsGameMode`. A compatible iPad app on visionOS does not get a Mac-style Game Mode scheduling pass. |
| Twilight HUD and performance graphs | No for this phase | Section 1.3 carries the classic bitrate line only. |
| GitHub update check | No | An App Store build that offers an update outside the store is a review rejection. Updates go through App Store Connect. |
| Own Mac bundle id so Local Network permission does not collide with Moonlight | Yes, as rebranding | Section 2. The iOS mechanism is the bundle id and the usage strings, not a Mac TCC identity. |
| Quit-with-controller crash fix, cursor and trackpad fixes | No | Those are in the Qt/SDL Mac shell. |

# 2. Rebranding

The shipping name is Twilight. User-facing strings, the bundle display name, and the App Store name say Twilight. They do not say Moonlight, and they do not say that Moonlight endorses the app. The Mac README already says Moonlight has not endorsed Twilight.

## Bundle id

Use `io.github.neguete10.twilight` for the iOS/iPadOS target. That id is also the Designed for iPad listing on visionOS, because a compatible iPad app is the same binary.

`io.github.neguete10.twilight.ios` also satisfies Apple's reverse-DNS check. The shorter id is the better default: a later native visionOS build can join the same App Store record without a platform name baked into the id. Pick one before the first App Store Connect record is created. The id cannot be changed after the first upload.

tvOS today shares `com.moonlight-stream.Moonlight` with the iOS target, which is how a single App Store record ships both platforms. Keep that shape: the tvOS target uses `io.github.neguete10.twilight` as well. A separate `io.github.neguete10.twilight.tv` record is only worth it if the tvOS app should be installed and sold independently.

Clear `DEVELOPMENT_TEAM` `DM46QST4M7` from every build configuration. That team id is Moonlight's. Twilight signs with its own Apple Developer team. Automatic signing against the upstream team will fail, and a profile from that team must not ship.

`MARKETING_VERSION` is `9.0.2`, which is the moonlight-ios version. The Mac feature release being ported is 7.1.0. The store version should be Twilight's own line (start at 1.0, or track 7.1.x once the feature set matches). Do not submit the fork as version 9.0.2 of Moonlight.

## Preference storage

A new bundle id already gets a new container, so an install of Twilight will not open official Moonlight's database. The on-disk names should still change, so logs, backups, and any future app group do not keep Moonlight's filenames.

Today (`AppDelegate.m`):

- iOS stores Core Data in Documents as `Limelight_iOS.sqlite`.
- tvOS stores a binary file `Moonlight_tvOS.bin` and copies that file into `NSUserDefaults` under the same string.
- The model versions are named `Moonlight v1.0` through `Moonlight v1.10`.

Twilight:

- iOS file `Twilight.sqlite`.
- tvOS file `Twilight_tvOS.bin`, and the same string as the `NSUserDefaults` key.
- A new model named Twilight, starting at v1. There is no store to migrate: the bundle id is new, and the Moonlight v1.x chain belongs to the other app.
- The client unique id and the pairing certificate live in this store (`IdManager`, `CryptoManager`). A new file means a new pairing identity, so a host sees Twilight as its own client.

Do not copy the Mac app's `QSettings` identity. Twilight 7.1.0 on Mac still calls `setOrganizationName("Moonlight Game Streaming Project")`, `setOrganizationDomain("moonlight-stream.com")`, and `setApplicationName("Moonlight")`, with the display name set to Twilight. Sharing that domain would make a Mac and an iOS build contend for the same preference files if they ever moved to a shared mechanism. The iOS store names above are the split.

Settings keys inside the model (`bitrate`, `preferredCodec`, and the rest) can keep their names. They are not visible across apps.

## Strings and assets that still say Moonlight

Phase 2, when code changes are allowed:

- `CFBundleDisplayName` / `PRODUCT_NAME` on both targets. The tvOS Info.plist hardcodes `Moonlight`. The iOS plist uses `${PRODUCT_NAME}`, and the product is the target name `Moonlight`.
- Alerts that say Moonlight, including the network-block copy in `DiscoveryManager.m` and the connectivity-test failure in `MainFrameViewController.m`.
- Usage strings in both Info.plists (`NSLocalNetworkUsageDescription`, both Bluetooth strings). They currently explain why Moonlight wants the permission.
- The app icon, the launch screen, and the README. The README rewrite should describe Twilight and point at the Mac client. It should not add a personal name, and it should not add a license section. The license file stays `LICENSE.txt`. An in-app about box is the right place for the license notice the GPL asks a GUI program to show.
- Help links and `CONN_TEST_SERVER` (`ios.conntest.moonlight-stream.org`) call upstream infrastructure. They can stay for the port, with the understanding that the host is someone else's. They are not branding.

# 3. App Store readiness

This is a checklist for the submission, not a review prediction. Official Moonlight iOS is already a shipping remote-desktop client (`id1000551566`). The fork inherits that review surface and adds a new bundle id, a microphone, and a new name.

## Signing

- Apple Developer Program membership under the publisher's own team.
- New App ID for `io.github.neguete10.twilight`, with Game Controller capability. Add the iOS and tvOS platforms to that record if both targets share the id.
- Distribution certificate and an App Store provisioning profile. Development signing stays automatic against the same team.
- Remove `DEVELOPMENT_TEAM = DM46QST4M7` before the first device build that is meant to be Twilight.
- No `CODE_SIGN_ENTITLEMENTS` file exists today. Add one when a capability needs a signed entitlement, and keep it limited to what the binary uses.
- Archive the Release configuration. Release is the configuration that defines `ENABLE_APP_STORE_RESTRICTIONS`.

## Entitlements

| Need | Entitlement | When |
| --- | --- | --- |
| Find hosts with `NSNetServiceBrowser` on `_nvstream._tcp` | None beyond the Info.plist Bonjour declaration, as long as `NSBonjourServices` lists that type | Already how `MDNSManager` works |
| Wake-on-LAN directed broadcast, if a build is rejected for raw UDP broadcast | `com.apple.developer.networking.multicast`, requested from Apple | Only if review or the console requires it. Do not add it speculatively |
| Microphone capture in the foreground | No entitlement. The usage string is the gate | Section 1.5 |
| Mac hardened-runtime microphone exception `com.apple.security.device.audio-input` | Do not copy it | That key is for the Mac Developer ID build. It is not an iOS entitlement |
| App Groups, iCloud, push, HomeKit, Health | None | The app does not use them |

## Privacy strings and manifest

Already present, and due for Twilight wording:

- `NSLocalNetworkUsageDescription`
- `NSBonjourServices` = `_nvstream._tcp`
- `NSBluetoothAlwaysUsageDescription` and `NSBluetoothPeripheralUsageDescription` (Citrix X1 mouse)
- `NSAppTransportSecurity` / `NSAllowsArbitraryLoads` = true. The client connects to whatever host the user paired. App Store Connect will ask for the reason. Keep the exception and describe it as user-specified game-streaming hosts.

Add before the build that needs them:

- `NSMicrophoneUsageDescription` on the iOS target only, when microphone passthrough lands. State that audio is sent to the user's computer. Absence of this key crashes at the first capture request.
- A `PrivacyInfo.xcprivacy` in the app bundle. The tree does not have one. `NSUserDefaults` (tvOS writes the whole database into defaults) is a required-reason API and needs a declared reason such as `CA92.1`. Add the manifest before submission, including the statically linked copies of FFmpeg, Opus, and SDL if their SDK snapshots ship manifests.

App Store Connect privacy labels, matching what the binary does:

- Data not collected by the developer, as long as no analytics SDK is added. The pairing certificate and unique id stay on device.
- Local network: yes, it is used to reach the host.
- Microphone: declare it when the toggle exists. Audio goes to the user's host, not to a Twilight server.
- Bluetooth: only if the X1 mouse path stays.

## Export compliance

Both Info.plists set `ITSAppUsesNonExemptEncryption` to false. That matches upstream and skips the per-build encryption question. It is a declaration the publisher makes, not a determination this plan can confirm.

What the binary actually uses:

- HTTPS to the host, through the system HTTP stack. Apple treats OS-provided TLS as exempt.
- The GameStream control and video protection inside moonlight-common-c (AES, via the crypto library that submodule builds).

For a new App Store Connect record, answer the encryption questions to match the plist. If the GameStream AES layer is later classified as non-exempt, the plist flag has to change and the usual annual self-classification (or a CCATS filing) follows. Do not flip the flag as part of rebranding without that classification.

## Review risks

Keep these. They are already how the Release build tries to pass review:

- `ENABLE_APP_STORE_RESTRICTIONS` is set only on the iOS target's Release configuration (`project.pbxproj`). `DiscoveryManager` then rejects a manually added IPv4 address that is not RFC 1918, link-local, or the CGN range, which the comment names as Guideline 4.2.7a. `AppListResponse` removes the default Steam entry and keeps a Steam app the user added, which the comment names as Guideline 4.2.7d. Debug builds do not define the macro. Store archives must be Release. Confirm the tvOS target gets the same macro before a tvOS submission; today the flag is on the iOS Release configuration.
- Remote-desktop rules still apply to a game-streaming client: the host is a computer the user owns, the UI is not a store, and the app does not browse or sell software. Hiding the stock Steam tile is part of that.
- The name Twilight has to be checked in App Store Connect against existing apps. A confusingly similar name is a metadata rejection. The subtitle and screenshots should describe PC game streaming.
- Do not use Moonlight's name, icon, or App Store screenshots. Do not imply the Moonlight project ships this app.
- Microphone: the purpose string has to match the behavior (host passthrough, opt-in, foreground). A string that says "audio quality" or a capture session that starts at launch will be rejected.
- `NSAllowsArbitraryLoads` needs the review note about user-specified hosts.
- The connectivity test host `ios.conntest.moonlight-stream.org` is a third-party server the app contacts. Mention it in the review notes.
- In-app update checks against GitHub must not be ported.
- `UIRequiredDeviceCapabilities` on the iOS plist is `arm64`. It was `armv7`. Apple Vision Pro does not advertise armv7, so that requirement would keep the Designed for iPad build off the headset. Every device that can run the iOS 15 deployment target is arm64, and the tvOS plist was already `arm64`. iPhone and iPad install eligibility is unchanged.
- `UIRequiresFullScreen` is true. That is acceptable for a streaming client. Designed for iPad on visionOS still runs fullscreen inside the iPad window.
- Age rating follows the questionnaire for a client that displays whatever the user's computer sends. The app itself has no store and no account.
- TestFlight uses the same signed binary and the same license question as the store. It is a test channel, not a different distribution license.

## Designed for iPad on visionOS

- In App Store Connect, make the iOS app available on Apple Vision Pro. That is the compatible-iPad path. It does not require an xrOS target.
- Test the iPhone-disabled, iPad storyboard layout in the visionOS simulator as a Designed for iPad app: host list, settings (including the new toggles), launch, and the stats overlay.
- Native visionOS (a full space, a native window scene, compositor-timed frames) is a later target. None of the seven features require it.

## Vision Pro

This pass keeps Twilight running as the existing iPad app ("Designed for iPad"). There is no native visionOS target, and the bundle id stays `io.github.neguete10.twilight.ios`.

The iOS Info.plist sets `UIPreferredDefaultInterfaceOrientation` to `UIInterfaceOrientationLandscapeRight`, so the window opens in landscape on Vision Pro. `UISupportedInterfaceOrientations` and `UISupportedInterfaceOrientations~ipad` are still landscape left and landscape right. That preferred key does not change iPhone or iPad rotation. The tvOS plist is unchanged.

A native visionOS target comes later. The reference clients are [Neo Moonlight](https://github.com/NeoVectorX/NeoMoonlight) and Moonlight XrOS ([moonlight-ios-vision](https://github.com/RikuKunMS2/moonlight-ios-vision)).

A native target that consumes streamed game content can request the visionOS entitlement `com.apple.developer.low-latency-streaming`. The system turns that mode on when it has resources. This Designed for iPad build does not include the entitlement. A later native target should add it only for a team Apple has allowed to use it. Moonlight XrOS tells local device builds to remove the entitlement when the signing team does not have it, or the app will not sign.

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

## Why this comes up

The Free Software Foundation's longstanding position is that the App Store's usage rules are further restrictions, which the GPL (section 10, and the conveying rules in section 6) does not allow a distributor to add. That is the conflict the VLC App Store removal turned on, and it is why an additional permission exists at all. Upstream Moonlight chose to ship moonlight-ios on the App Store with the exception above. The Mac Twilight 7.1.0 build does not use that path: it is a Developer ID signed, notarized disk image, and the Mac README describes the Mac App Store package flag as optional and unused for that image.

This fork does not have copyright assignments from the Moonlight contributors. That fact decides what the fork can change.

## Options

1. **Keep the exception that is already in `LICENSE.txt`, and keep the source public.** The permission is already granted in the copy this fork received. Using it does not require a new grant. The exception's own condition is that source stays available under the GPL, with or without the extra permission, somewhere that does not carry the store's terms. A public git repository is that channel. Making the repository private would drop the condition the paragraph states. The in-app about box should offer the license, which the GPL's "How to Apply These Terms" asks a GUI program to do. The README does not need a license section.

2. **Ask the Moonlight maintainers if a fork is what the paragraph covers.** The text says "you are allowed to distribute the software." It does not name forks, and it does not name Twilight. A written answer from the maintainers is the way to confirm they read it as covering a fork. That ask is optional for as long as the publisher is comfortable relying on the paragraph as written. It is the right ask if a store review, a mirror, or a lawyer wants something the paragraph does not say.

3. **Ask those copyright holders for a different exception or a dual license.** Relicensing the app to MIT, Apache, or a proprietary license, or writing a new exception, needs permission from the copyright holders of the GPL code that remains. This fork does not have that permission. New code written for Twilight can carry whatever terms its author attaches, and those terms do not replace the GPL on the Moonlight code they are combined with. A combined work stays under GPL-3.

4. **Remove the exception.** Section 7 allows a recipient to strip additional permissions. The file that remains is plain GPL-3, which is the text the App Store conflict is about. Removing the paragraph works against shipping on the store. There is no reason to remove it as part of the rebrand.

5. **Ship outside the App Store.** Ad-hoc, enterprise, or a direct sideload never accepts the store's usage rules, so it does not need the exception. It also does not meet the goal of an App Store release. TestFlight is still Apple's distribution and uses the store's signing.

The practical path that matches this repository is option 1: leave the exception in place, keep the git repository public under GPL-3, and put the license notice in the app's about box rather than in the README. Option 2 is the conversation to open with the Moonlight maintainers if that reading needs to be confirmed. Option 3 is the conversation to open only if the goal changes from "ship this GPL fork" to "ship under some other license."

# Suggested order of work

Code changes start after this plan. A sensible order, so later settings are not written into the Moonlight store:

1. Rebrand the target names, bundle id, team, version, usage strings, and store filenames. Confirm a Release build signs with the new team.
2. Raise the bitrate ceiling and extend the stats overlay. Both are visible without a special host.
3. Put AV1 into the Automatic mask, and leave PyroWave out.
4. Add the adaptive-bitrate toggle and the two HTTPS calls, tested against a Vibepollo host and against stock Sunshine (where the toggle must do nothing).
5. Wire `setAdaptiveTriggers` to `GCDualSenseAdaptiveTrigger`, and check existing rumble on a DualSense.
6. Add `LiSendRawControlStreamPacket` to moonlight-common-c, then the microphone toggle, on iOS and iPadOS only.
7. Leave VRR as the existing fixed display-link lock, and label it that way on the overlay.
8. Privacy manifest, App Store Connect record, and a Release archive with `ENABLE_APP_STORE_RESTRICTIONS` on every target that will be submitted. The submission worksheet is `APP_STORE.md`.

# App Store Connect prep

This is the submission worksheet for Twilight on iPhone, iPad, Apple TV, and Apple Vision Pro (Designed for iPad). It is not a review prediction, and it is not legal advice. The binary that goes to App Store Connect is a Release archive. A Run from Xcode uses Debug, which does not define `ENABLE_APP_STORE_RESTRICTIONS`.

Bundle id for both targets: `io.github.neguete10.twilight.ios`.

`DEVELOPMENT_TEAM` `DM46QST4M7` is not set on any configuration. Signing stays automatic (`CODE_SIGN_STYLE = Automatic`, and `ProvisioningStyle = Automatic` on both app targets). Xcode uses the team selected in Signing & Capabilities. Simulator builds turn signing off, so they do not need a team.

## Review notes

Paste this into App Review Information:

> Twilight is a game-streaming client. The user pairs it with a computer they run (Sunshine or GeForce Experience). The app does not sell or browse software.
>
> NSAllowsArbitraryLoads is on because the paired host is an address the user chooses. It is not a fixed server. Pairing, the app list, and the stream use HTTP and HTTPS to that host.
>
> The connectivity test contacts ios.conntest.moonlight-stream.org on port 443. That host only checks whether the network blocks the streaming ports. It is not an update server and it does not receive an account.
>
> Release builds define ENABLE_APP_STORE_RESTRICTIONS. That build hides the default Steam tile (Guideline 4.2.7d) and rejects a manually entered IPv4 address that is not a private LAN address (Guideline 4.2.7a). A Steam app the user added stays in the list.
>
> Microphone passthrough is off until the user turns it on in settings. The permission prompt is shown only then. Captured audio is sent to the paired computer on the existing encrypted control stream. It is not uploaded to a Twilight server. The app does not declare the audio background mode.
>
> The app does not check GitHub, or any other server, for a new version. Updates are delivered through App Store Connect.
>
> The app does not include an analytics SDK. The pairing certificate and the client id stay on the device.

The icon and top-shelf images are Twilight's mark. They are not Moonlight's icon or screenshots.

## Privacy label

In App Store Connect, answer that the app does not collect data. Nothing is sent to the developer or to an analytics service. The pairing certificate, client id, and settings stay on the device.

| Question | Answer |
| --- | --- |
| Do you or your third-party partners collect data from this app? | No |
| Data used to track the user | No |
| Data linked to the user | No |

Purpose strings, which are separate from the collection label:

| Permission | What to say if asked |
| --- | --- |
| Local network | Used to find and stream from the user's computer. Bonjour service `_nvstream._tcp`. |
| Microphone | Opt-in, iPhone and iPad only. Audio goes to the user's computer when microphone passthrough is on. The developer does not receive it. |
| Bluetooth | Used to connect a Citrix X1 mouse. Bluetooth data is not collected. |

`PrivacyInfo.xcprivacy` is in both app bundles. Tracking is off and the collected-data array is empty.

Required-reason APIs declared in that file:

| API | Reason | Why |
| --- | --- | --- |
| User defaults | `CA92.1` | The app reads and writes its own settings. On tvOS it also keeps a copy of its database in its own defaults. Nothing is shared with another app. |
| System boot time | `35F9.1` | The linked SDL2 audio timer calls `mach_absolute_time` to measure elapsed time inside the app (`SDL_Delay` and the audio clock). SDL2 does not ship a privacy manifest. |

Checked, and not given an entry in this manifest:

| Library | Result |
| --- | --- |
| Opus | No required-reason symbols in the static archives. No privacy manifest is shipped with the library. |
| FFmpeg | No privacy manifest. The only required-reason symbol is `fstat`, inside `libavutil`'s `file.o` (`av_file_map`). Nothing in the app or the other static libraries references that object, so the linker does not pull it in. |
| OpenSSL | The Swift package is a framework and ships its own `PrivacyInfo.xcprivacy` (file timestamps, reason `C617.1`). Xcode merges that manifest from the framework. It is not copied into the app file. |

## Export compliance

Both Info.plists set `ITSAppUsesNonExemptEncryption` to false. In App Store Connect, set **Uses Non-Exempt Encryption** to **No**. That matches the plist and skips the per-upload encryption question.

The binary uses HTTPS through the system HTTP stack, and AES inside the GameStream code in moonlight-common-c. Those are the same mechanisms upstream moonlight-ios ships with this plist value. Leave the flag false. If a later classification decides the GameStream AES layer is non-exempt, change the plist and file the annual self-classification report (or a CCATS filing) at that time.

## Apple Vision Pro

In the iOS app's availability, turn on **Apple Vision Pro** and choose **Designed for iPad**. That installs the iOS binary. There is no visionOS target to upload.

`UIRequiredDeviceCapabilities` is `arm64`, so the headset can install the app. The iOS Info.plist sets `UIPreferredDefaultInterfaceOrientation` to landscape right, so the window opens in landscape. iPhone and iPad rotation are unchanged.

## Install a development build on an iPhone

1. Enroll the Apple ID in the Apple Developer Program. A free personal team can install a debug build for a few days. TestFlight and the store need a paid membership.
2. Install Xcode. Clone with submodules: `git clone --recursive https://github.com/Neguete10/moonlight-ios.git`
3. Open `Moonlight.xcodeproj`. Select the **Moonlight** target, then Signing & Capabilities. Set **Team** to the Apple Developer team. Leave **Automatically manage signing** on. The bundle id is `io.github.neguete10.twilight.ios`. Do not type `DM46QST4M7`.
4. Connect the iPhone, trust the computer, and select that iPhone as the run destination. The scheme is **Moonlight**. Product → Run.
5. On the iPhone, if iOS blocks the app, open Settings → General → VPN & Device Management and trust the developer certificate.
6. This Run uses the Debug configuration. The LAN-address limit and the hidden default Steam tile are off in Debug. They are on in a Release archive.

iOS 27 refuses to finish launching an app that still uses `UIMainStoryboardFile` and has no scene manifest. The iOS target adopts a single `UIScene`. `SceneDelegate` builds the window from `iPhone.storyboard` or `iPad.storyboard` (iPad, including Designed for iPad on visionOS). tvOS is unchanged and still uses its storyboard. A launch that dies in the first second on an iOS 27 simulator is a failed scene adoption, not a settings bug.

Apple TV is the same sequence with the **Moonlight TV** scheme and an Apple TV destination.

## Upload to TestFlight

1. In App Store Connect, create a new app named Twilight. Platform iOS. Bundle id `io.github.neguete10.twilight.ios`. Add the tvOS platform to the same record so one listing covers iPhone, iPad, and Apple TV. Turn on Designed for iPad for Apple Vision Pro.
2. Check that the name Twilight is available. A similar existing name is a metadata rejection. The subtitle and screenshots should say PC game streaming. Do not use Moonlight's name, icon, or screenshots.
3. In Xcode, select **Any iOS Device (arm64)** (and archive **Moonlight TV** separately for Apple TV). Product → Archive. Archives use Release, so `ENABLE_APP_STORE_RESTRICTIONS` is defined.
4. In the Organizer, Distribute App → App Store Connect → Upload. Signing stays automatic.
5. When the build finishes processing, open TestFlight, answer the export-compliance prompt with **No** (non-exempt encryption), and enable the build for internal testing.
6. The store version in the project is still `9.0.2`, which is the moonlight-ios version this tree started from. Set Twilight's own version (1.0, or a 7.1.x line) before the first upload if that number should not be 9.0.2.

`MARKETING_VERSION` was left at 9.0.2 in this change. The first App Store Connect record is the point where that number becomes permanent for that version.

## Still done on a Mac, with an Apple Developer account

- Choose the signing team and install a build on a device.
- Create the App Store Connect record, screenshots, age rating, and the privacy questionnaire using the answers above. The app has no account and no store of its own. The age rating follows whatever the user's computer sends.
- Device-check microphone passthrough, a DualSense, a real stream, and a launch on iOS 27. GitHub Actions builds the iOS simulator and the tvOS simulator, checks the visionOS destination, and launches the iOS app on an iOS 27 simulator when that runtime is installed on the runner. A runner without the iOS 27 runtime skips that launch and does not fail the build.

# Twilight

[![CI](https://github.com/Neguete10/moonlight-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/Neguete10/moonlight-ios/actions/workflows/ci.yml)

Twilight streams a game from a computer you own to iPhone, iPad, and Apple TV. It is a fork of [Moonlight for iOS and tvOS](https://github.com/moonlight-stream/moonlight-ios). Moonlight has not endorsed it.

The Mac client is [Twilight](https://github.com/Neguete10/twilight). Hosts are [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream.

The name on the device is Twilight. The Xcode targets are still Moonlight (iPhone and iPad) and Moonlight TV (Apple TV). Both use the bundle id `io.github.neguete10.twilight.ios`.

Preferences for this app live in `Twilight.sqlite` on iOS and iPadOS, and in `Twilight_tvOS.bin` on tvOS.

Adaptive bitrate and microphone passthrough are off until turned on in settings. Adaptive bitrate changes the rate only when the host's capability list contains `runtime_bitrate`. Microphone passthrough is an iPhone and iPad setting.

## Building

* Install Xcode from the [App Store](https://apps.apple.com/us/app/xcode/id497799835)
* Clone with submodules: `git clone --recursive https://github.com/Neguete10/moonlight-ios.git`
  * If the clone was not recursive, run `git submodule update --init --recursive`
* Open `Moonlight.xcodeproj` in Xcode
* The signing team is unset. A simulator build does not need one. To run on a device, select the Moonlight or Moonlight TV target, open Signing & Capabilities, and choose your Apple Developer team.

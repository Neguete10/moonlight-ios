# Twilight

[![Build](https://github.com/Neguete10/twilight-ios/actions/workflows/build.yml/badge.svg)](https://github.com/Neguete10/twilight-ios/actions/workflows/build.yml)
![Platforms](https://img.shields.io/badge/platforms-iPhone%20%26%20iPad-black)

Twilight is an Apple-native client for streaming a game from a computer you own to iPhone and iPad.

The Mac client is [Twilight](https://github.com/Neguete10/twilight).

## Features

- Landscape iPhone, and iPad in portrait or landscape
- Hosts that speak the Sunshine protocol, including Vibeshine and Apollo-style hosts
- H.264, HEVC, and AV1, plus HDR when the device and the host both support them
- DualSense adaptive triggers, with rumble through Core Haptics
- System keyboard and a special-key bar (Done, Win, Esc, Tab, Shift, Ctrl, Alt, Delete) from a three-finger tap
- Adaptive bitrate, off until it is turned on, and only when the host advertises `runtime_bitrate`
- Microphone passthrough on iPhone and iPad, off until it is turned on

## Requirements

- Mac with Xcode from the App Store
- iOS or iPadOS 15 or later on the device

## Building

```sh
git clone --recursive https://github.com/Neguete10/twilight-ios.git
```

If the clone was not recursive, run `git submodule update --init --recursive`.

Open `Moonlight.xcodeproj` and build the **Moonlight** scheme. The name on the device is Twilight. The bundle id is `io.github.neguete10.twilight.ios`. A simulator build does not need a signing team. To run on a device, select the Moonlight target, open Signing & Capabilities, and choose an Apple Developer team.

The Xcode project also contains a **Moonlight TV** scheme. Continuous integration builds and tests the iPhone and iPad app.

## Tests

Simulator unit and UI tests, from the repo root:

```sh
export TEST_RUNNER_TWILIGHT_SCREENSHOT_DIR="$PWD/ui-test-screenshots"
export TEST_RUNNER_TWILIGHT_EXPECT_LANDSCAPE=1
xcodebuild test \
  -project Moonlight.xcodeproj \
  -scheme Moonlight \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:TwilightUnitTests \
  -only-testing:TwilightUITests
```

`TEST_RUNNER_*` has to be in the environment of `xcodebuild`. The same names placed after the command are build settings and do not reach the test process. Xcode strips the `TEST_RUNNER_` prefix, so the tests read `TWILIGHT_SCREENSHOT_DIR` and `TWILIGHT_EXPECT_LANDSCAPE`. Leave `TEST_RUNNER_TWILIGHT_EXPECT_LANDSCAPE` unset for iPad. Turn off **Connect Hardware Keyboard** in Simulator before the keyboard UI test, and dismiss the QuickPath tip if it covers the bar.

## Credits

Twilight for iOS is a fork of [moonlight-stream/moonlight-ios](https://github.com/moonlight-stream/moonlight-ios). Moonlight has not endorsed it. Thanks to the Moonlight contributors, and to the people who maintain [Sunshine](https://github.com/LizardByte/Sunshine).

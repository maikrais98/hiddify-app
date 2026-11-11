<div align="center">

<img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/app-icon-1024.png" alt="Luma app icon" width="112" />

# Luma

A personal proxy client for myself, family and friends.

A non-commercial learning project based on [Hiddify](https://github.com/hiddify/hiddify-app).

[Русский](README.md) · **English** · [Development](CONTRIBUTING.md) · [License](LICENSE.md)

</div>

---

## About

I develop Luma for everyday use with a small circle of people, to learn and experiment with the interface and connection flows. There are no plans to sell it or turn it into a commercial product.

Luma is a public fork of Hiddify with its own presentation and changes, built on Hiddify's open-source client and proxy core.

## Features

- Import profiles from a link, QR code or file.
- Connect using an imported profile, select a server and check latency.
- View available traffic and profile expiry information.
- Configure routing and export a safe diagnostic summary.

You need your own profile or a link supplied by an administrator to connect.

## Status and installation

The current focus is **iOS**, interface improvements and test builds for a small group. Android, macOS, Windows and Linux source code inherited from Hiddify remains in the repository; this does not mean a tested Luma release is available for each platform.

Test installation is arranged with the project author. Hiddify store listings and downloads are not Luma builds.

## Changes from upstream

- **13 July 2026:** introduced the Woman in Red identity, including the app icon, colors and user-facing platform identifiers.
- **July–November 2026:** worked on the iOS interface, connection flows, server selection, settings, safe diagnostics and test-build verification. See the [commit history](https://github.com/maikrais98/hiddify-app/commits/main/) for individual changes.
- **11 November 2026:** adopted **Luma** as the public project name and updated the repository presentation for a personal, non-commercial project.

Woman in Red and Hiddify names remain in parts of the source and historical documentation. Some internal names are retained for compatibility.

## Development and feedback

See [CONTRIBUTING.md](CONTRIBUTING.md) for source setup. Main areas:

| Area | Location |
| --- | --- |
| Flutter application | [lib/](lib/) |
| Native iOS code | [ios/](ios/) |
| Tests | [test/](test/) |
| Design experiments | [design/](design/) |
| Safe diagnostics | [docs/safe-diagnostics.md](docs/safe-diagnostics.md) |
| Data inventory | [docs/privacy-data-inventory.md](docs/privacy-data-inventory.md) |

Testers can send feedback directly to the author, including device, build version, steps and expected behavior. Check screenshots and diagnostics for private links, QR codes and credentials before sharing.

## Credits and license

Thanks to the authors and contributors of [Hiddify](https://github.com/hiddify/hiddify-app), [sing-box](https://github.com/SagerNet/sing-box) and the other [project dependencies](pubspec.yaml).

Luma remains under the original [Hiddify Extended GPLv3 license](LICENSE.md). Original attribution and license terms are preserved. Distribution notes are recorded in [docs/gpl-compliance.md](docs/gpl-compliance.md).

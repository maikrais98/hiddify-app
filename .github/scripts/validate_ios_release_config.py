#!/usr/bin/env python3
"""Fail CI when the iOS archive, signing, or version settings drift apart."""

from pathlib import Path
import plistlib
import re
import sys


ROOT = Path(__file__).resolve().parents[2]


def fail(message: str) -> None:
    print(f"iOS release configuration: {message}", file=sys.stderr)
    raise SystemExit(1)


def xcconfig_value(name: str) -> str:
    content = (ROOT / "ios/Base.xcconfig").read_text()
    match = re.search(rf"^{re.escape(name)}\s*=\s*(\S+)\s*$", content, re.MULTILINE)
    if not match:
        fail(f"{name} is missing from ios/Base.xcconfig")
    return match.group(1)


def main() -> None:
    bundle_id = xcconfig_value("BASE_BUNDLE_IDENTIFIER")
    team_id = xcconfig_value("DEVELOPMENT_TEAM")
    project = (ROOT / "ios/Runner.xcodeproj/project.pbxproj").read_text()

    project_teams = set(re.findall(r"DEVELOPMENT_TEAM\s*=\s*([A-Z0-9]+);", project))
    if project_teams != {team_id}:
        fail(f"Xcode Team IDs {sorted(project_teams)} do not match {team_id}")

    pubspec = (ROOT / "pubspec.yaml").read_text()
    version_match = re.search(r"^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$", pubspec, re.MULTILINE)
    if not version_match:
        fail("pubspec.yaml must contain a semantic version and numeric build number")
    marketing_version, build_number = version_match.groups()
    uses_flutter_version = False
    for setting, literal, variable in (
        ("MARKETING_VERSION", marketing_version, "FLUTTER_BUILD_NAME"),
        ("CURRENT_PROJECT_VERSION", build_number, "FLUTTER_BUILD_NUMBER"),
    ):
        values = {
            value.strip().removeprefix('"').removesuffix('"')
            for value in re.findall(rf"{setting}\s*=\s*([^;]+);", project)
        }
        reference = f"$({variable})"
        if not values or not values <= {literal, reference}:
            fail("pubspec and Xcode target versions are inconsistent")
        uses_flutter_version |= reference in values

    if uses_flutter_version:
        base_config = (ROOT / "ios/Base.xcconfig").read_text()
        if not re.search(
            r'^\s*#include\??\s+"Flutter/Generated\.xcconfig"\s*$',
            base_config,
            re.MULTILINE,
        ):
            fail("Flutter versions require ios/Base.xcconfig to include Flutter/Generated.xcconfig")

    with (ROOT / "ios/exportOptions.plist").open("rb") as handle:
        export_options = plistlib.load(handle)
    if export_options.get("teamID") != team_id:
        fail("exportOptions.plist Team ID does not match ios/Base.xcconfig")

    expected_profiles = {bundle_id, f"{bundle_id}.HiddifyPacketTunnel"}
    profiles = export_options.get("provisioningProfiles")
    signing_style = export_options.get("signingStyle")
    if signing_style not in {"automatic", "manual"}:
        fail("exportOptions.plist signingStyle must be automatic or manual")
    if profiles is not None and not isinstance(profiles, dict):
        fail("exportOptions.plist provisioningProfiles must be a dictionary")
    actual_profiles = set(profiles or {})
    if (signing_style == "manual" or "provisioningProfiles" in export_options) and (
        actual_profiles != expected_profiles
        or any(not isinstance(value, str) or not value.strip() for value in (profiles or {}).values())
    ):
        fail(
            "exportOptions.plist provisioning profile bundle IDs must be "
            f"{sorted(expected_profiles)}, got {sorted(actual_profiles)}"
        )

    for relative_path in (
        "ios/Runner/Runner.entitlements",
        "ios/HiddifyPacketTunnel/HiddifyPacketTunnel.entitlements",
        "ios/Runner/Info.plist",
        "ios/HiddifyPacketTunnel/Info.plist",
        "ios/Runner/PrivacyInfo.xcprivacy",
        "ios/HiddifyPacketTunnel/PrivacyInfo.xcprivacy",
    ):
        with (ROOT / relative_path).open("rb") as handle:
            plistlib.load(handle)

    # Must be in Copy Bundle Resources or the IPA ships without the privacy manifest.
    if project.count("PrivacyInfo.xcprivacy in Resources") < 2:
        fail(
            "PrivacyInfo.xcprivacy must be in the Runner and HiddifyPacketTunnel "
            "Resources build phases"
        )

    print(
        f"iOS release configuration is consistent: {bundle_id}, "
        f"team {team_id}, version {marketing_version} ({build_number})"
    )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Validate the security-critical declarations in a merged Android manifest."""

from __future__ import annotations

import argparse
import copy
import subprocess
import sys
import xml.etree.ElementTree as ET
from collections.abc import Callable
from pathlib import Path


ANDROID = "{http://schemas.android.com/apk/res/android}"
EXPECTED_PACKAGE = "io.github.holyglory.devcoordinator"
EXPECTED_ACTIVITY = f"{EXPECTED_PACKAGE}.MainActivity"
EXPECTED_SCHEME = EXPECTED_PACKAGE
EXPECTED_HOST = "oauth"
EXPECTED_PATH = "/callback"


class ManifestValidationError(ValueError):
    pass


def _attr(node: ET.Element, name: str) -> str | None:
    return node.get(f"{ANDROID}{name}")


def _names(node: ET.Element, child_tag: str) -> list[str | None]:
    return [_attr(child, "name") for child in node.findall(child_tag)]


def validate_manifest_xml(xml_text: str) -> None:
    try:
        manifest = ET.fromstring(xml_text)
    except ET.ParseError as error:
        raise ManifestValidationError("Merged Android manifest is malformed.") from error

    if manifest.tag != "manifest" or manifest.get("package") != EXPECTED_PACKAGE:
        raise ManifestValidationError("Unexpected Android package in merged manifest.")

    applications = manifest.findall("application")
    if len(applications) != 1:
        raise ManifestValidationError("Merged manifest must contain one application.")
    application = applications[0]
    if _attr(application, "allowBackup") != "false":
        raise ManifestValidationError("Android backup must remain disabled.")
    if _attr(application, "usesCleartextTraffic") != "false":
        raise ManifestValidationError("Cleartext Android traffic must remain disabled.")

    main_activities = [
        activity
        for activity in application.findall("activity")
        if _attr(activity, "name") == EXPECTED_ACTIVITY
    ]
    if len(main_activities) != 1:
        raise ManifestValidationError("Merged manifest must contain one MainActivity.")
    main_activity = main_activities[0]
    if _attr(main_activity, "exported") != "true":
        raise ManifestValidationError("OAuth callback MainActivity must be exported.")

    metadata = [
        item
        for item in main_activity.findall("meta-data")
        if _attr(item, "name") == "flutter_deeplinking_enabled"
    ]
    if len(metadata) != 1 or _attr(metadata[0], "value") != "false":
        raise ManifestValidationError(
            "Flutter automatic deep-link handling must remain disabled."
        )

    all_filters = list(application.iter("intent-filter"))
    view_filters = [
        intent_filter
        for intent_filter in all_filters
        if "android.intent.action.VIEW" in _names(intent_filter, "action")
    ]
    if len(view_filters) != 1:
        raise ManifestValidationError(
            "Merged manifest must expose exactly one VIEW callback filter."
        )
    callback_filter = view_filters[0]
    if callback_filter not in main_activity.findall("intent-filter"):
        raise ManifestValidationError("OAuth callback must target MainActivity.")
    if callback_filter.attrib:
        raise ManifestValidationError(
            "OAuth callback filter contains unexpected attributes."
        )
    if _names(callback_filter, "action") != ["android.intent.action.VIEW"]:
        raise ManifestValidationError("OAuth callback action set is not exact.")
    callback_categories = _names(callback_filter, "category")
    if any(name is None for name in callback_categories) or sorted(
        name for name in callback_categories if name is not None
    ) != [
        "android.intent.category.BROWSABLE",
        "android.intent.category.DEFAULT",
    ]:
        raise ManifestValidationError("OAuth callback categories are not exact.")
    callback_data = callback_filter.findall("data")
    if len(callback_data) != 1:
        raise ManifestValidationError(
            "OAuth callback must contain exactly one data declaration."
        )
    expected_data = {
        f"{ANDROID}scheme": EXPECTED_SCHEME,
        f"{ANDROID}host": EXPECTED_HOST,
        f"{ANDROID}path": EXPECTED_PATH,
    }
    if callback_data[0].attrib != expected_data:
        raise ManifestValidationError(
            "OAuth callback must use only the exact production scheme and path."
        )

    scheme_declarations = [
        data
        for data in application.iter("data")
        if _attr(data, "scheme") == EXPECTED_SCHEME
    ]
    if scheme_declarations != callback_data:
        raise ManifestValidationError(
            "Unexpected alternate production callback declaration."
        )

    launcher_filters = [
        intent_filter
        for intent_filter in main_activity.findall("intent-filter")
        if "android.intent.action.MAIN" in _names(intent_filter, "action")
    ]
    if len(launcher_filters) != 1:
        raise ManifestValidationError("MainActivity launcher declaration is not exact.")
    launcher = launcher_filters[0]
    if _names(launcher, "action") != ["android.intent.action.MAIN"] or _names(
        launcher, "category"
    ) != ["android.intent.category.LAUNCHER"]:
        raise ManifestValidationError("MainActivity launcher declaration is malformed.")


def _base_self_test_manifest() -> ET.Element:
    return ET.fromstring(
        f"""\
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          package="{EXPECTED_PACKAGE}">
  <application android:allowBackup="false"
               android:usesCleartextTraffic="false">
    <activity android:name="{EXPECTED_ACTIVITY}" android:exported="true">
      <meta-data android:name="flutter_deeplinking_enabled"
                 android:value="false" />
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
      <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data android:scheme="{EXPECTED_SCHEME}"
              android:host="{EXPECTED_HOST}"
              android:path="{EXPECTED_PATH}" />
      </intent-filter>
    </activity>
    <activity android:name="io.example.UnrelatedActivity"
              android:exported="false" />
  </application>
</manifest>
"""
    )


def _xml(root: ET.Element) -> str:
    return ET.tostring(root, encoding="unicode")


def run_self_test() -> None:
    base = _base_self_test_manifest()
    validate_manifest_xml(_xml(base))

    mutations: list[tuple[str, Callable[[ET.Element], None]]] = [
        (
            "wrong callback scheme",
            lambda root: root.find(".//data").set(
                f"{ANDROID}scheme", "io.example.attacker"
            ),
        ),
        (
            "wrong callback path",
            lambda root: root.find(".//data").set(f"{ANDROID}path", "/other"),
        ),
        (
            "non-exported callback",
            lambda root: root.find(".//activity").set(
                f"{ANDROID}exported", "false"
            ),
        ),
        (
            "missing browsable category",
            lambda root: root.find(
                ".//category[@android:name='android.intent.category.BROWSABLE']",
                {"android": ANDROID[1:-1]},
            ).clear(),
        ),
        (
            "alternate callback data",
            lambda root: root.find(".//intent-filter[2]").append(
                ET.Element(
                    "data",
                    {
                        f"{ANDROID}scheme": EXPECTED_SCHEME,
                        f"{ANDROID}host": EXPECTED_HOST,
                        f"{ANDROID}path": "/oauth/alternate",
                    },
                )
            ),
        ),
        (
            "duplicate callback filter",
            lambda root: root.find(".//activity").append(
                copy.deepcopy(root.find(".//intent-filter[2]"))
            ),
        ),
    ]
    for label, mutate in mutations:
        candidate = copy.deepcopy(base)
        mutate(candidate)
        try:
            validate_manifest_xml(_xml(candidate))
        except ManifestValidationError:
            continue
        raise AssertionError(f"Self-test failed to catch: {label}")


def _manifest_from_apk(apk: Path, apkanalyzer: Path) -> str:
    if not apk.is_file():
        raise ManifestValidationError(f"APK does not exist: {apk}")
    try:
        result = subprocess.run(
            [str(apkanalyzer), "manifest", "print", str(apk)],
            check=True,
            capture_output=True,
            text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise ManifestValidationError(
            "apkanalyzer could not read the merged Android manifest."
        ) from error
    return result.stdout


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--apkanalyzer", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        run_self_test()
    if args.apk is not None:
        if args.apkanalyzer is None:
            parser.error("--apkanalyzer is required with --apk")
        validate_manifest_xml(_manifest_from_apk(args.apk, args.apkanalyzer))
    if not args.self_test and args.apk is None:
        parser.error("select --self-test and/or --apk")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ManifestValidationError, AssertionError) as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)

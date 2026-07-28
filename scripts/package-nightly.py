#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_FORMATS = {"linux": "deb", "windows": "zip-powershell", "macos": "dmg"}
VERSION_PATTERN = re.compile(r"\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?")


def load_json(path: Path) -> dict[str, object]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"{path} must contain a JSON object")
    return payload


def require_file(path: Path) -> Path:
    if not path.is_file():
        raise FileNotFoundError(path)
    return path


def require_dir(path: Path) -> Path:
    if not path.is_dir():
        raise FileNotFoundError(path)
    return path


def copy_tree_contents(source: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    for item in source.iterdir():
        target = destination / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)


def validate_release_inputs(platform: str, config: dict[str, object], versions: dict[str, object]) -> str:
    if versions.get("schema_version") != 1:
        raise ValueError("invalid release versions schema")
    if config.get("schema_version") != 1 or config.get("platform") != platform:
        raise ValueError(f"invalid {platform} package schema")
    if config.get("package_format") != PACKAGE_FORMATS[platform]:
        raise ValueError(f"invalid {platform} package format")
    signing = config.get("signing")
    if not isinstance(signing, dict) or signing.get("status") not in {"configured", "explicit-gap"}:
        raise ValueError(f"invalid {platform} signing policy")
    if signing.get("status") == "explicit-gap" and not str(signing.get("reason", "")).strip():
        raise ValueError(f"missing {platform} signing gap reason")
    automatic_updates = config.get("automatic_updates")
    if not isinstance(automatic_updates, bool):
        raise ValueError(f"invalid {platform} automatic update policy")
    if signing.get("status") != "configured" and automatic_updates:
        raise ValueError(f"unsigned {platform} package cannot enable automatic updates")
    core_version = versions.get("core_version")
    if not isinstance(core_version, str) or not VERSION_PATTERN.fullmatch(core_version):
        raise ValueError("invalid core version")
    adapters = versions.get("platform_adapters")
    adapter_version = adapters.get(platform) if isinstance(adapters, dict) else None
    if not isinstance(adapter_version, str) or not VERSION_PATTERN.fullmatch(adapter_version):
        raise ValueError(f"missing or invalid adapter version for {platform}")
    return adapter_version


def package_linux(config: dict[str, object], output: Path, version: str) -> Path:
    build = require_dir(ROOT / str(config["build_relative_path"]))
    with tempfile.TemporaryDirectory(prefix="vityo-deb-") as raw_stage:
        stage = Path(raw_stage)
        app_root = stage / "opt/vityo"
        copy_tree_contents(build, app_root)
        control_root = stage / "DEBIAN"
        control_root.mkdir(parents=True)
        control = require_file(ROOT / str(config["installer_definition"])).read_text(encoding="utf-8")
        debian_version = version.split("+", 1)[0].replace("-", "~", 1)
        control = control.replace("Version: 0.1.0", f"Version: {debian_version}")
        (control_root / "control").write_text(control, encoding="utf-8")
        bin_root = stage / "usr/bin"
        bin_root.mkdir(parents=True)
        wrapper = bin_root / "vityo"
        wrapper.write_text('#!/usr/bin/env sh\nexec /opt/vityo/vityo_app "$@"\n', encoding="utf-8")
        wrapper.chmod(wrapper.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        applications = stage / "usr/share/applications"
        applications.mkdir(parents=True)
        shutil.copy2(
            ROOT / "packaging/linux/io.vityo.desktop",
            applications / "io.vityo.desktop",
        )
        metainfo = stage / "usr/share/metainfo"
        metainfo.mkdir(parents=True)
        shutil.copy2(
            ROOT / "packaging/linux/io.vityo.metainfo.xml",
            metainfo / "io.vityo.metainfo.xml",
        )
        icons = stage / "usr/share/icons/hicolor/512x512/apps"
        icons.mkdir(parents=True)
        shutil.copy2(
            require_file(ROOT / str(config["icon_relative_path"])),
            icons / "io.vityo.png",
        )
        subprocess.run(["dpkg-deb", "--build", "--root-owner-group", stage, output], check=True)
    return output


def package_windows(config: dict[str, object], output: Path) -> Path:
    build = require_dir(ROOT / str(config["build_relative_path"]))
    with tempfile.TemporaryDirectory(prefix="vityo-win-") as raw_stage:
        stage = Path(raw_stage) / "Vityo-Nightly"
        copy_tree_contents(build, stage)
        shutil.copy2(ROOT / "packaging/windows/install.ps1", stage / "install.ps1")
        shutil.copy2(ROOT / "packaging/windows/uninstall.ps1", stage / "uninstall.ps1")
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(stage.parent))
    return output


def package_macos(config: dict[str, object], output: Path) -> Path:
    app = require_dir(ROOT / str(config["build_relative_path"]))
    script = require_file(ROOT / str(config["installer_definition"]))
    subprocess.run(["bash", script, app, output], check=True)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Build one independently releasable Vityo Nightly package")
    parser.add_argument("--platform", required=True, choices=("linux", "windows", "macos"))
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/nightly")
    args = parser.parse_args()
    config = load_json(ROOT / f"packaging/{args.platform}/nightly.json")
    versions = load_json(ROOT / "packaging/release-versions.json")
    version = validate_release_inputs(args.platform, config, versions)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    suffix = {"linux": ".deb", "windows": ".zip", "macos": ".dmg"}[args.platform]
    output = args.output_dir / f"vityo-nightly-{args.platform}-{version}{suffix}"
    if output.exists():
        output.unlink()
    artifact = {"linux": package_linux, "windows": package_windows, "macos": package_macos}[args.platform]
    if args.platform == "linux":
        artifact(config, output, version)
    else:
        artifact(config, output)
    evidence = {
        "schema_version": 1,
        "platform": args.platform,
        "core_version": versions["core_version"],
        "adapter_version": version,
        "artifact": output.name,
        "signing": config["signing"],
        "automatic_updates": config["automatic_updates"],
    }
    output.with_suffix(output.suffix + ".json").write_text(
        json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

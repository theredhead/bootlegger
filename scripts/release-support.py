#!/usr/bin/env python3
"""Freeze release inputs, collect vendor notices, and audit universal app bundles."""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile
import tempfile

DEPENDENCIES = {
    "libusb.tar.bz2": "5977fc950f8d1395ccea9bd48c06b3f808fd3c2c961b44b0c2e6e29fc3a70a85",
    "libgpg-error.tar.bz2": "95b178148863f07d45df0cea67e880a79b9ef71f5d230baddc0071128516ef78",
    "libgcrypt.tar.bz2": "24e91c9123a46c54e8371f3a3a2502f1198f2893fbfbf59af95bc1c21499b00e",
    "libsndfile.tar.xz": "3799ca9924d3125038880367bf1468e53a1b7e3686a934f098b7e1d286cdb80e",
}
ROOT_FILES = {"LICENSE", ".gitignore", ".swift-format", ".swiftlint.yml", "bootlegger icons.png"}
ROOTS = {"Sources", "Vendor", "Tests", "scripts", "Bootlegger.xcodeproj"}


def run(*args):
    return subprocess.check_output(args, text=True).strip()


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def snapshot(root, destination):
    exported = root / "SOURCE-MANIFEST.json"
    if not (root / ".git").exists() and exported.exists():
        origin = json.loads(exported.read_text())
        paths = origin["files"]
        commit = origin["gitCommit"]
        modified = origin["workingTreeModified"] or any(
            not (root / name).is_file() or digest(root / name) != expected
            for name, expected in origin["sha256"].items() if name in paths
        )
    else:
        paths = run("git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z").split("\0")
        commit = run("git", "-C", str(root), "rev-parse", "HEAD")
        modified = bool(run("git", "-C", str(root), "status", "--porcelain"))
    selected = []
    for name in sorted(set(paths)):
        if not name:
            continue
        path = Path(name)
        if path.parts[0] not in ROOTS and not (
            len(path.parts) == 1 and (name in ROOT_FILES or path.suffix in {".md", ".sh"})
        ):
            continue
        if "xcuserdata" in path.parts or path.suffix == ".xcuserstate":
            continue
        source = root / path
        if not source.is_file():
            raise RuntimeError("Missing release input: " + name)
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        selected.append(name)
    downloads = destination / ".build/NetMD/downloads"
    downloads.mkdir(parents=True, exist_ok=True)
    for name in DEPENDENCIES:
        cached = root / ".build/NetMD/downloads" / name
        if cached.exists():
            shutil.copy2(cached, downloads / name)
    write_json(destination / "SOURCE-MANIFEST.json", {
        "gitCommit": commit,
        "workingTreeModified": modified,
        "files": selected,
    })
    print("Frozen", len(selected), "release source files.")


def collect_notices(source):
    licenses = source / "Licenses"
    licenses.mkdir(exist_ok=True)
    shutil.copy2(source / "LICENSE", licenses / "Application-MIT.txt")
    shutil.copy2(source / "Vendor/NetMD/LICENSE", licenses / "GPL-3.0.txt")
    shutil.copy2(source / "Vendor/ATRACDEnc/LICENSE", licenses / "LGPL-2.1.txt")
    shutil.copy2(source / "THIRD_PARTY_NOTICES.md", licenses / "THIRD_PARTY_NOTICES.md")
    notices = {}
    name_pattern = re.compile(r"^(copying|licen[cs]e|notice|authors|copyright)([._-].*)?$", re.I)

    def collect(tree, label):
        for path in sorted(tree.rglob("*")):
            if not path.is_file():
                continue
            relative = path.relative_to(tree)
            if name_pattern.match(path.name) or any(part.upper() == "LICENSES" for part in relative.parts):
                target = licenses / label / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
            if path.suffix.lower() in {".c", ".cc", ".cpp", ".h", ".hpp", ".mm"}:
                text = path.read_text(errors="replace")
                for comment in re.findall(r"/\*.*?\*/", text, flags=re.S):
                    if re.search(r"copyright|redistribution|permission is hereby|SPDX-License|free software|warranty", comment, re.I):
                        notices.setdefault(comment, []).append(str(Path(label) / relative))

    collect(source / "Vendor", "Vendor")
    with tempfile.TemporaryDirectory(prefix="release-licenses-") as folder:
        for name, expected in DEPENDENCIES.items():
            archive = source / ".build/NetMD/downloads" / name
            if not archive.is_file() or digest(archive) != expected:
                raise RuntimeError("Missing or incorrect dependency source: " + name)
            tree = Path(folder) / name
            tree.mkdir()
            subprocess.run(["tar", "-xf", str(archive), "-C", str(tree)], check=True)
            collect(tree, name.split(".tar")[0])
    text = "Embedded source copyright and license notices\n\n"
    for comment, paths in sorted(notices.items()):
        text += "Files: " + ", ".join(paths) + "\n" + comment + "\n\n"
    if "Mark Borgerding" not in text or "FFmpeg" not in text:
        raise RuntimeError("Embedded Kiss FFT / FFmpeg notices were not collected")
    (licenses / "Embedded-Source-Notices.txt").write_text(text)
    return licenses


def source_package(source, output):
    manifest_path = source / "SOURCE-MANIFEST.json"
    manifest = json.loads(manifest_path.read_text())
    licenses = collect_notices(source)
    files = list(manifest["files"])
    files += [".build/NetMD/downloads/" + name for name in DEPENDENCIES]
    files += [str(path.relative_to(source)) for path in licenses.rglob("*") if path.is_file()]
    hashes = {name: digest(source / name) for name in sorted(set(files))}
    source_id = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
    manifest.update(sha256=hashes, sourceID=source_id, dependencyArchives=DEPENDENCIES)
    write_json(manifest_path, manifest)
    files.append("SOURCE-MANIFEST.json")
    archive = output / ("Bootlegger-source-" + source_id[:12] + ".tar.gz")
    # Normalize source archive metadata. DMG/signature timestamps are not claimed bit-identical.
    with archive.open("wb") as raw, gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as package:
            for name in sorted(set(files)):
                path = source / name
                info = package.gettarinfo(str(path), arcname="Bootlegger/" + name)
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mtime = 0
                info.mode = 0o755 if os.access(path, os.X_OK) else 0o644
                with path.open("rb") as data:
                    package.addfile(info, data)
    shutil.copy2(manifest_path, output / "SOURCE-MANIFEST.json")
    return archive


def verify_apps(stage, output):
    records = []
    magic = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"}
    for app in sorted(stage.glob("*.app")):
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        binaries = []
        for path in sorted(app.rglob("*")):
            if not path.is_file():
                continue
            with path.open("rb") as stream:
                if stream.read(4) not in magic:
                    continue
            for architecture in ["arm64", "x86_64"]:
                subprocess.run(["lipo", "-verify_arch", architecture, str(path)], check=True)
            dependencies = run("otool", "-arch", "all", "-L", str(path))
            for line in dependencies.splitlines():
                if not line.startswith("\t"):
                    continue
                dependency = line.strip().split(" (", 1)[0]
                if not dependency.startswith(("/usr/lib/", "/System/Library/")):
                    raise RuntimeError("Non-system runtime dependency: " + dependency)
            binaries.append({"path": str(path.relative_to(stage)), "sha256": digest(path), "architectures": ["arm64", "x86_64"]})
        if len(binaries) < 3:
            raise RuntimeError("Missing universal application/helpers: " + str(app))
        for name in ["CorrespondingSource.tar.gz", "SOURCE-MANIFEST.json", "Licenses/LGPL-2.1.txt", "Licenses/GPL-3.0.txt"]:
            if not (app / "Contents/Resources" / name).is_file():
                raise RuntimeError("Missing distribution material: " + name)
        records.append({"app": app.name, "binaries": binaries})
    manifest = json.loads((output / "SOURCE-MANIFEST.json").read_text())
    write_json(output / "BUILD-MANIFEST.json", {
        "sourceID": manifest["sourceID"], "gitCommit": manifest["gitCommit"],
        "workingTreeModified": manifest["workingTreeModified"], "applications": records,
        "xcode": run("xcodebuild", "-version"), "sdk": run("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "cmake": run("cmake", "--version").splitlines()[0], "deploymentTarget": "15.0",
    })
    print("Verified universal binaries, signatures, runtime dependencies, and source/license materials.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=["snapshot", "source-package", "verify"])
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    if args.operation == "snapshot":
        snapshot(args.source.resolve(), args.destination.resolve())
    elif args.operation == "source-package":
        print(source_package(args.source.resolve(), args.destination.resolve()))
    else:
        verify_apps(args.source.resolve(), args.destination.resolve())


if __name__ == "__main__":
    main()

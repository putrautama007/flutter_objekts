#!/usr/bin/env python3
"""Prepare an automatic patch release for the package repository."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
VERSION_RE = re.compile(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$")
TAG_RE = re.compile(r"^v(?P<version>\d+\.\d+\.\d+)$")
VERSION_LINE_RE = re.compile(r"(?m)^(version:\s*)([^\s#]+)(\s*)$")
SECTION_RE = re.compile(r"(?m)^##\s+(.+?)\s*$")
RELEASE_COMMIT_RE = re.compile(r"^chore\(release\):\s+v\d+\.\d+\.\d+$")


class ReleaseError(RuntimeError):
    """Raised when the repository is not in a safe release state."""


@dataclass(frozen=True, order=True)
class Version:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, value: str, *, label: str) -> "Version":
        match = VERSION_RE.fullmatch(value)
        if not match:
            raise ReleaseError(
                f"{label} must be a plain semantic version like 0.1.0; got {value!r}"
            )
        return cls(
            int(match.group("major")),
            int(match.group("minor")),
            int(match.group("patch")),
        )

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    @property
    def tag(self) -> str:
        return f"v{self}"

    def next_patch(self) -> "Version":
        return Version(self.major, self.minor, self.patch + 1)


@dataclass(frozen=True)
class ReleaseResult:
    version: Version
    tag: str
    changed: bool
    notes: str


def run_git(repo: Path, *args: str) -> str:
    process = subprocess.run(
        ["git", *args],
        cwd=repo,
        check=False,
        capture_output=True,
        text=True,
    )
    if process.returncode != 0:
        detail = process.stderr.strip() or process.stdout.strip()
        raise ReleaseError(f"git {' '.join(args)} failed: {detail}")
    return process.stdout.strip()


def read_package_version(pubspec: str) -> Version:
    matches = list(VERSION_LINE_RE.finditer(pubspec))
    if len(matches) != 1:
        raise ReleaseError("pubspec.yaml must contain exactly one version field")
    return Version.parse(matches[0].group(2), label="pubspec.yaml version")


def replace_package_version(pubspec: str, version: Version) -> str:
    updated, count = VERSION_LINE_RE.subn(
        lambda match: f"{match.group(1)}{version}{match.group(3)}",
        pubspec,
        count=1,
    )
    if count != 1:
        raise ReleaseError("could not update the version in pubspec.yaml")
    return updated


def parse_changelog(changelog: str) -> tuple[str, list[tuple[str, str]]]:
    matches = list(SECTION_RE.finditer(changelog))
    if not matches:
        raise ReleaseError("CHANGELOG.md must contain at least one level-two section")

    prefix = changelog[: matches[0].start()].strip()
    sections: list[tuple[str, str]] = []
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(changelog)
        sections.append((match.group(1).strip(), changelog[match.end() : end].strip()))
    return prefix, sections


def section_body(sections: list[tuple[str, str]], heading: str) -> str:
    for current_heading, body in sections:
        if current_heading == heading:
            return body
    return ""


def release_notes_from_changelog(changelog: str, version: Version) -> str:
    _, sections = parse_changelog(changelog)
    body = section_body(sections, str(version))
    if not body:
        raise ReleaseError(f"CHANGELOG.md has no section for version {version}")
    return f"## {version}\n\n{body.strip()}\n"


def latest_tag(repo: Path) -> tuple[str, Version] | None:
    tags = run_git(repo, "tag", "--list", "v*").splitlines()
    versions: list[tuple[str, Version]] = []
    for tag in tags:
        match = TAG_RE.fullmatch(tag.strip())
        if match:
            versions.append((tag.strip(), Version.parse(match.group("version"), label="tag")))
    if not versions:
        return None
    return max(versions, key=lambda item: item[1])


def commit_subjects(repo: Path, previous_tag: str | None) -> list[str]:
    revision = f"{previous_tag}..HEAD" if previous_tag else "HEAD"
    subjects = run_git(repo, "log", "--format=%s", revision).splitlines()
    unique: list[str] = []
    for subject in subjects:
        subject = subject.strip()
        if not subject or RELEASE_COMMIT_RE.fullmatch(subject) or subject in unique:
            continue
        unique.append(subject)
    return unique


def build_release_body(
    existing_target: str,
    existing_unreleased: str,
    subjects: list[str],
) -> str:
    body_parts: list[str] = []
    if existing_target.strip():
        body_parts.append(existing_target.strip())

    existing_text = "\n".join(body_parts)
    additions: list[str] = []
    if existing_unreleased.strip():
        additions.append(existing_unreleased.strip())
    additions.extend(
        f"- {subject}" for subject in subjects if f"- {subject}" not in existing_text
    )

    if additions:
        if body_parts:
            body_parts.append("")
        body_parts.extend(["### Changes", "", "\n\n".join(additions)])
    if not body_parts:
        body_parts = ["### Changes", "", "- No changes recorded."]
    return "\n".join(body_parts).strip()


def render_changelog(
    prefix: str,
    sections: list[tuple[str, str]],
    version: Version,
    release_body: str,
) -> str:
    lines = [prefix, "", "## Unreleased", "", f"## {version}", "", release_body]
    for heading, body in sections:
        if heading in {"Unreleased", str(version)}:
            continue
        lines.extend(["", f"## {heading}", ""])
        if body:
            lines.append(body)
    return "\n".join(lines).rstrip() + "\n"


def prepare_release(repo: Path, notes_path: Path) -> ReleaseResult:
    pubspec_path = repo / "pubspec.yaml"
    changelog_path = repo / "CHANGELOG.md"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    changelog = changelog_path.read_text(encoding="utf-8")
    package_version = read_package_version(pubspec)
    previous = latest_tag(repo)
    head = run_git(repo, "rev-parse", "HEAD")

    if previous and run_git(repo, "rev-list", "-n", "1", previous[0]) == head:
        if package_version != previous[1]:
            raise ReleaseError(
                "HEAD is tagged, but pubspec.yaml does not match the tagged version"
            )
        notes = release_notes_from_changelog(changelog, package_version)
        notes_path.write_text(notes, encoding="utf-8")
        return ReleaseResult(package_version, previous[0], False, notes)

    if previous is None:
        version = package_version
    else:
        if package_version != previous[1]:
            raise ReleaseError(
                "pubspec.yaml version must match the latest vX.Y.Z tag before a patch release"
            )
        version = package_version.next_patch()

    tag = version.tag
    all_tags = run_git(repo, "tag", "--list").splitlines()
    if tag in all_tags:
        raise ReleaseError(f"tag {tag} already exists but is not the current release HEAD")

    prefix, sections = parse_changelog(changelog)
    existing_target = section_body(sections, str(version)) if previous is None else ""
    existing_unreleased = section_body(sections, "Unreleased")
    subjects = commit_subjects(repo, previous[0] if previous else None)
    release_body = build_release_body(existing_target, existing_unreleased, subjects)
    updated_changelog = render_changelog(prefix, sections, version, release_body)

    updated_pubspec = replace_package_version(pubspec, version)
    pubspec_path.write_text(updated_pubspec, encoding="utf-8")
    changelog_path.write_text(updated_changelog, encoding="utf-8")
    notes = f"## {version}\n\n{release_body}\n"
    notes_path.write_text(notes, encoding="utf-8")
    return ReleaseResult(version, tag, True, notes)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=ROOT)
    parser.add_argument("--output", type=Path, default=Path(".release-notes.md"))
    args = parser.parse_args(argv)

    repo = args.repo.resolve()
    notes_path = args.output if args.output.is_absolute() else repo / args.output
    try:
        result = prepare_release(repo, notes_path)
    except (OSError, ReleaseError) as error:
        print(f"release preparation failed: {error}", file=sys.stderr)
        return 1

    print(f"version={result.version}")
    print(f"tag={result.tag}")
    print(f"changed={'true' if result.changed else 'false'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

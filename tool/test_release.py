import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


sys.path.insert(0, str(Path(__file__).parent))
from release import ReleaseError, prepare_release


class ReleasePreparationTest(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = Path(tempfile.mkdtemp(prefix="objekts-release-test-"))
        self.run_git("init", "-q")
        self.run_git("config", "user.name", "Release Test")
        self.run_git("config", "user.email", "release-test@example.com")
        self.write(
            "pubspec.yaml",
            "name: objekts\nversion: 0.1.0\npublish_to: none\n",
        )
        self.write(
            "CHANGELOG.md",
            "# Changelog\n\n"
            "## Unreleased\n\n"
            "- Added an unreleased feature.\n\n"
            "## 0.1.0\n\n"
            "- Initial release.\n",
        )
        self.write("README.md", "initial\n")
        self.commit("initial commit")

    def tearDown(self) -> None:
        shutil.rmtree(self.repo)

    def run_git(self, *args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=self.repo,
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def write(self, name: str, contents: str) -> None:
        (self.repo / name).write_text(contents, encoding="utf-8")

    def commit(self, message: str) -> None:
        self.run_git("add", ".")
        self.run_git("commit", "-qm", message)

    def prepare(self):
        return prepare_release(self.repo, self.repo / ".release-notes.md")

    def test_bootstraps_existing_version_and_merges_unreleased_notes(self) -> None:
        result = self.prepare()

        self.assertEqual(str(result.version), "0.1.0")
        self.assertTrue(result.changed)
        changelog = (self.repo / "CHANGELOG.md").read_text(encoding="utf-8")
        self.assertEqual(changelog.count("## 0.1.0"), 1)
        self.assertIn("- Added an unreleased feature.", changelog)
        self.assertIn("- Initial release.", changelog)
        self.assertIn("## Unreleased\n\n## 0.1.0", changelog)

    def test_increments_patch_and_generates_notes(self) -> None:
        self.run_git("tag", "-a", "v0.1.0", "-m", "Release v0.1.0")
        self.write("README.md", "updated\n")
        self.commit("fix: make release notes deterministic")

        result = self.prepare()

        self.assertEqual(result.tag, "v0.1.1")
        self.assertEqual(result.version.patch, 1)
        self.assertIn("- fix: make release notes deterministic", result.notes)
        self.assertIn("version: 0.1.1", (self.repo / "pubspec.yaml").read_text())

    def test_rejects_version_mismatch(self) -> None:
        self.run_git("tag", "-a", "v0.1.0", "-m", "Release v0.1.0")
        self.write("pubspec.yaml", "name: objekts\nversion: 0.2.0\n")
        self.commit("manual version change")

        with self.assertRaisesRegex(ReleaseError, "must match the latest"):
            self.prepare()

    def test_rejects_invalid_version(self) -> None:
        self.write("pubspec.yaml", "name: objekts\nversion: 1.0\n")
        self.commit("invalid version")

        with self.assertRaisesRegex(ReleaseError, "plain semantic version"):
            self.prepare()

    def test_is_idempotent_when_release_commit_is_already_tagged(self) -> None:
        self.run_git("tag", "-a", "v0.1.0", "-m", "Release v0.1.0")
        self.write(
            "CHANGELOG.md",
            "# Changelog\n\n"
            "## Unreleased\n\n"
            "## 0.1.0\n\n"
            "- Initial release.\n\n"
            "## 0.1.1\n\n"
            "- Patch release.\n",
        )
        self.write(
            "pubspec.yaml",
            "name: objekts\nversion: 0.1.1\npublish_to: none\n",
        )
        self.commit("chore(release): v0.1.1")
        self.run_git("tag", "-a", "v0.1.1", "-m", "Release v0.1.1")

        result = self.prepare()

        self.assertFalse(result.changed)
        self.assertEqual(result.tag, "v0.1.1")
        self.assertIn("## 0.1.1", result.notes)


if __name__ == "__main__":
    unittest.main()

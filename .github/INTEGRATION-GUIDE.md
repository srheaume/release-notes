# GitHub Actions Integration Guide

To simplify integration with your CI/CD pipeline, this repository provides a reusable GitHub Action that automates the
generation of release notes.

This action is designed to be composable and lives in the `.github/actions/` directory of your repository.

### Actions Overview

- **`generate-release-notes`:** An action that parses your Git history and Conventional Commits to produce a
  Markdown-formatted release notes file.

---

### `generate-release-notes` Action

This action automates the creation of release documentation. It calculates the range of commits between two points (
e.g., the last tag and the current HEAD), groups them by type (Features, Fixes, Breaking Changes), and formats them into
a clean Markdown summary. It is ideal for populating the body of GitHub Releases or generating changelog files.

**Inputs:**

| Name                          | Description                                                                         | Required | Default           |
|-------------------------------|-------------------------------------------------------------------------------------|----------|-------------------|
| `from_ref`                    | The starting Git reference (exclusive). Set to `'auto'` to detect the previous tag. | `false`  | `'auto'`          |
| `to_ref`                      | The ending Git reference (inclusive).                                               | `false`  | `'HEAD'`          |
| `repo_url`                    | Base URL for clickable links.                                                       | `false`  | `""`              |
| `version_label`               | Version label for the header (e.g. `'1.0.0'`).                                      | `false`  | `"Unreleased"`    |
| `exclude_authors`             | Comma-separated list of authors to ignore (e.g. `'dependabot[bot]'`).               | `false`  | `""`              |
| `exclude_types`               | Comma-separated list of commit types to ignore (e.g. `'chore,docs'`).               | `false`  | `""`              |
| `exclude_scopes`              | Comma-separated list of scopes to ignore (e.g. `'internal'`).                       | `false`  | `""`              |
| `exclude_invalid_commits`     | Set to `'true'` to exclude non-conventional commits.                                | `false`  | `'false'`         |
| `release_notes_artifact_name` | Name of the artifact to upload containing the generated file.                       | `false`  | `'release-notes'` |

**Outputs:**

There are no direct variable outputs. The action produces a file artifact named as per `release_notes_artifact_name` (
default: `release-notes`) which contains the `RELEASE-NOTES.md` file.

**Workflow Example (Automated Release Creation):**

This workflow runs when a new tag is pushed. It generates release notes from the *previous* tag to the *current* tag and
creates a GitHub Release.

```yaml
name: "Create Release"

on:
  push:
    tags:
      - "v*.*.*"

jobs:
  release:
    name: "Create GitHub Release"
    runs-on: "ubuntu-latest"
    steps:
      - name: "Checkout Source Code"
        uses: "actions/checkout@v5"
        with:
          fetch-depth: 0 # Required to access full commit history

      - name: "Generate Release Notes"
        id: "notes"
        uses: "srheaume/release-notes/.github/actions/generate-release-notes@v0.1.0-stable"
        with:
          from_ref: "auto"
          to_ref: "${{ github.ref_name }}"
          repo_url: "${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}"
          version_label: "${{ github.ref_name }}"
          exclude_authors: "dependabot[bot]"
          exclude_types: "chore,ci,test"

      - name: "Download Release Notes Artifact"
        uses: "actions/download-artifact@v6"
        with:
          name: "release-notes"
          path: "."

      - name: "Create Release"
        uses: "softprops/action-gh-release@v2"
        with:
          body_path: "RELEASE-NOTES.md"
          draft: false
          prerelease: false
```

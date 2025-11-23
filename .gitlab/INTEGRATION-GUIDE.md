# GitLab CI/CD Integration Guide

To simplify integration with your CI/CD pipeline, this repository provides a reusable GitLab CI/CD Component that
automates the generation of release documentation.

### Component Overview

- **`.generate-release-notes`:** A component that parses Git history and Conventional Commits to produce a
  Markdown-formatted release notes file.

---

### `.generate-release-notes` Component

Calculates the range of commits between two points (e.g., the last tag and the current HEAD), groups them by type (
Features, Fixes, Breaking Changes), and formats them into a clean Markdown summary. It is ideal for populating the body
of Release pages or generating changelog files.

**Inputs (`spec:inputs`):**

| Name                      | Description                                                                         | Required | Default        |
|---------------------------|-------------------------------------------------------------------------------------|----------|----------------|
| `from_ref`                | The starting Git reference (exclusive). Set to `'auto'` to detect the previous tag. | `false`  | `'auto'`       |
| `to_ref`                  | The ending Git reference (inclusive).                                               | `false`  | `'HEAD'`       |
| `repo_url`                | Base URL for clickable links. Defaults to the current project URL.                  | `false`  | `""`           |
| `version_label`           | Version label for the header (e.g. `'1.0.0'`).                                      | `false`  | "'Unreleased'" |
| `exclude_authors`         | Comma-separated list of authors to ignore (e.g. `'dependabot[bot]'`).               | `false`  | `""`           |
| `exclude_types`           | Comma-separated list of commit types to ignore (e.g. `'chore,docs'`).               | `false`  | `""`           |
| `exclude_scopes`          | Comma-separated list of scopes to ignore (e.g. `'internal'`).                       | `false`  | `""`           |
| `exclude_invalid_commits` | Set to `'true'` to exclude non-conventional commits.                                | `false`  | `false`        |

**Outputs (`dotenv` Artifact):**

| Variable             | Description                              | Example            |
|----------------------|------------------------------------------|--------------------|
| `RELEASE_NOTES_FILE` | The path to the generated Markdown file. | `RELEASE-NOTES.md` |

**Usage Example (Automated Release Creation):**

This pipeline runs when a new tag is pushed. It generates release notes covering changes since the *previous* tag and
creates a GitLab Release.

```yaml
workflow:
  rules:
    - if: $CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/

stages: [ prepare, release ]

include:
  - remote: 'https://raw.githubusercontent.com/srheaume/release-notes/refs/tags/v0.1.0-stable/.gitlab/ci-templates/jobs/generate-release-notes/generate-release-notes.yml'
    inputs:
      from_ref: auto
      to_ref: $CI_COMMIT_TAG
      repo_url: $CI_PROJECT_URL
      version_label: $CI_COMMIT_TAG
      exclude_authors: "dependabot[bot]"
      exclude_types: "chore,ci,test"

generate-release-notes:
  stage: prepare
  extends: .generate-release-notes

create-release:
  stage: release
  image: registry.gitlab.com/gitlab-org/release-cli:latest
  needs: [ generate-release-notes ]
  script:
    - echo "Creating release for $CI_COMMIT_TAG"
  release:
    name: "Release $CI_COMMIT_TAG"
    description: $RELEASE_NOTES_FILE
    tag_name: $CI_COMMIT_TAG
```

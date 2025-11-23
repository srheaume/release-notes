# release-notes.sh

This Bash script automates the generation of Markdown release notes from Git history following
the [Conventional Commits](https://www.conventionalcommits.org/) specification. It is designed for CI pipelines and
release automation, ensuring consistent, readable, and categorized summaries. It parses raw commit logs, groups them by
impact (features, fixes, performance), and formats them into a clean Markdown structure.

## Table of Contents

- [Key Features](#key-features)
- [Usage](#usage)
    - [Syntax](#syntax)
    - [Arguments & Options](#arguments--options)
    - [Examples](#examples)
- [How It Works](#how-it-works)
    - [Commit Parsing](#commit-parsing)
    - [Section Ordering](#section-ordering)
- [CI/CD Integration](#cicd-integration)

## Key Features

### Conventional Commit Support:

- **Automated Categorization:** Automatically groups commits into meaningful sections based on their type (e.g., `feat`,
  `fix`, `perf`, `chore`).
- **Breaking Change Detection:** Highlights critical updates by detecting `!` in the commit header or `BREAKING CHANGE:`
  in the body/footer. These are placed at the very top of the notes.
- **Scope Formatting:** bolds the scope of a commit for better readability (e.g., **api**: update endpoint).

### Robust Filtering:

- **Author Exclusion:** Easily filter out commits from bots or specific users using `--exclude-authors` (e.g.,
  `dependabot[bot]`).
- **Noise Reduction:** Filters out irrelevant commits using `--exclude-types` (e.g., removing `chore` or `docs`) or
  `--exclude-scopes` (e.g., removing `internal`).
- **Strict Mode:** Optionally excludes non-conventional commits entirely via `--exclude-invalid-commits`.

### High Performance:

- **Optimized Parsing:** Uses native Bash parameter expansion instead of subshells (`sed`/`awk`) for string
  manipulation, making it capable of processing thousands of commits in seconds.
- **Dependency Free:** Requires only `git` and `bash`. No Python, Node.js, or compiled binaries required.

### Markdown Integration:

- **Clickable Links:** Generates hyperlinks for commit hashes if a `--repo-url` is provided.
- **Standard Formatting:** Output is written to standard output (stdout), ready to be piped directly into release
  bodies (GitHub Releases, GitLab Tags, or `RELEASE_NOTES.md` files).

## Usage

### Syntax

```
Usage: release-notes.sh <from_ref> <to_ref> [OPTION]...

Generates Markdown release notes from Git history based on Conventional Commits.
Output is written to standard output (stdout).

Arguments:
  <from_ref>      Previous release tag or commit hash (exclusive).
  <to_ref>        Current release tag, commit hash, or HEAD (inclusive).

Options:
  -r, --repo-url <url>
                  Base URL of the repository (e.g., "https://github.com/user/repo").
                  Used to generate hyperlinks for commit hashes.
  -v, --version <version>
                  Title version string for the header (default: "Unreleased").
      --exclude-authors <list>
                  Comma-separated list of commit authors to ignore.
                  Example: --exclude-authors "dependabot\[bot\]"
      --exclude-types <list>
                  Comma-separated list of commit types to ignore.
                  Example: --exclude-types "chore,docs,test"
      --exclude-scopes <list>
                  Comma-separated list of scopes to ignore.
                  Example: --exclude-scopes "internal,deps"
      --exclude-invalid-commits
                  Omit commits that do not adhere to the Conventional Commits
                  specification (usually listed under "Other Changes").
  -h, --help      Display this help message and exit.
```

### Arguments & Options

#### 1. References (`<from_ref>` ` <to_ref>`)

The script requires a range of commits.

* `from_ref`: The specific Git SHA of the previous deployment/release.
* `to_ref`: The specific Git SHA of the current deployment/release.

#### 2. Repository URL (`--repo-url`)

If provided, the script appends the commit hash to this URL to create clickable links.

* **Format:** `[<short_hash>](<repo-url>/commit/<full_hash>)`
* **Header Link:** It also creates a "Compare" link in the release header.

#### 3. Filtering (`--exclude-*`)

Allows you to curate the notes to reduce noise.

* `--exclude-authors`: Removes commits from specific Git authors (exact match).
* `--exclude-types`: Useful for hiding internal changes like `ci` or `test`.
* `--exclude-scopes`: Useful for hiding changes to specific sub-systems.
* `--exclude-invalid-commits`: Removes the "Other Changes" section entirely.

### Examples

1. Basic usage between two specific commit hashes:
   ```bash
   ./release-notes.sh 5011dfa 3884114
   ```

2. Generate notes with hyperlinks for GitHub:
   ```bash
   ./release-notes.sh 5011dfa 3884114 --repo-url "https://github.com/my/repo"
   ```

3. Filter out bots and maintenance commits:
   ```bash
   ./release-notes.sh 5011dfa 3884114 \
      --version "1.1.0" \
      --exclude-authors "dependabot\[bot\]" \
      --exclude-types "chore,ci,docs"
   ```

4. Strict mode (Only Conventional Commits) between a hash and HEAD:
   ```bash
   ./release-notes.sh 5011dfa HEAD --exclude-invalid-commits
   ```

Here is the **How It Works** section, formatted to match the style of the rest of the documentation.

## How It Works

### Commit Parsing

The script reads the Git log between the specified references (`<from_ref>` to `<to_ref>`). It utilizes a strict regex
pattern to parse the header of every commit to identify components of
the [Conventional Commits](https://www.conventionalcommits.org/) specification:

`type(scope)!: subject`

* **Type:** Determines the categorization (e.g., `feat` maps to "✨ New Features").
* **Scope:** Optional context (e.g., `(api)`). The script formats this in **bold** to make scanning easier.
* **Breaking Changes:** The script scans both the header and the footer for breaking indicators. A commit is flagged as
  breaking if:
    1. The header contains a `!` (e.g., `feat!: change api`).
    2. The body or footer contains the text `BREAKING CHANGE:` or `BREAKING CHANGES:`.

**Note:** If a commit is identified as a Breaking Change, it is promoted to the **⚠ BREAKING CHANGES** section at the
very top of the release notes, regardless of its original type, to ensure visibility.

### Section Ordering

To ensure the most critical information is read first, sections are rendered in a specific priority order based on user
impact rather than alphabetical order:

1. **⚠ BREAKING CHANGES** (Critical for upgrades)
2. **✨ New Features** (Value add)
3. **🐛 Bug Fixes** (Stability)
4. **⚡ Performance** (Improvements)
5. **⏪ Reverts** (Rollbacks)
6. **🔨 Refactors** (Code structure)
7. **💄 Styling** (Formatting)
8. **📚 Documentation** (Docs)
9. **🧪 Tests** / **🏗️ Build** / **🤖 CI** / **🧹 Maintenance**
10. **🔹 Other Changes** (Non-conventional commits, unless excluded)

Here is the **CI/CD Integration** section, adapted for `release-notes.sh` while maintaining the exact structure and
professional tone of your reference text.

## CI/CD Integration

We provide comprehensive guides and reusable workflows to integrate release-notes.sh into your CI/CD pipelines on both
GitHub and GitLab. These guides cover the automation of your release documentation.

For detailed instructions and complete workflow examples, please see the platform-specific guides:

- **[GitHub Actions Integration Guide](.github/INTEGRATION-GUIDE.md)**
- **[GitLab CI/CD Integration Guide](.gitlab/INTEGRATION-GUIDE.md)**

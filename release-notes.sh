#!/usr/bin/env bash

#
#  This file is part of release-notes.sh.
#
#  release-notes.sh is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Lesser General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  release-notes.sh is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Lesser General Public License for more details.
#
#  You should have received a copy of the GNU Lesser General Public License
#  along with release-notes.sh.  If not, see <https://www.gnu.org/licenses/>.
#

set -eo pipefail

__SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}")"
readonly __SCRIPT_NAME

#=============================================================================
# Private Constants

# Mapping of commit types to display titles
declare -rA __SECTION_TITLES=(
    ["breaking-change"]="⚠ BREAKING CHANGES"
    ["build"]="🏗️ Build System"
    ["chore"]="🧹 Maintenance"
    ["ci"]="🤖 CI/CD"
    ["docs"]="📚 Documentation"
    ["feat"]="✨ New Features"
    ["fix"]="🐛 Bug Fixes"
    ["other"]="🔹 Other Changes"
    ["perf"]="⚡ Performance"
    ["refactor"]="🔨 Refactors"
    ["revert"]="⏪ Reverts"
    ["style"]="💄 Styling"
    ["test"]="🧪 Tests"
)

# Define the hierarchy of sections in the final output
# Optimized order: High Impact (User) -> Stability -> Internal (Dev)
readonly __SECTION_ORDER=(
    "breaking-change" # ⚠ Major impact
    "feat"            # ✨ New features
    "fix"             # 🐛 Bug fixes
    "perf"            # ⚡ Performance
    "revert"          # ⏪ Reverts
    "refactor"        # 🔨 Code restructuring
    "style"           # 💄 Formatting
    "docs"            # 📚 Documentation
    "test"            # 🧪 Tests
    "build"           # 🏗️ Build
    "ci"              # 🤖 CI
    "chore"           # 🧹 Maintenance
    "other"           # 🔹 Fallback
)

# Regex for Conventional Commits: type(scope)!: subject
# Captures: 1=Type, 3=Scope, 4=Breaking(!), 5=Subject
readonly __REGEX_CONVENTIONAL='^(feat|fix|chore|docs|style|refactor|perf|test|build|ci|revert)(\(([^)]+)\))?(!)?:[[:space:]]*(.+)'

#=============================================================================
# Private Variables

__arg_from_ref=""
__arg_to_ref=""
__opt_repo_url=""
__opt_version=""
__opt_exclude_invalid_commits=false

# Associative arrays allow O(1) lookup time for exclusions,
# preventing performance degradation as the exclusion list grows
declare -A __opt_exclude_authors_map
declare -A __opt_exclude_scopes_map
declare -A __opt_exclude_types_map

#=============================================================================
# Private Methods

#-----------------------------------------------------------------------------
# Usage
#-----------------------------------------------------------------------------

__usage_print() {
    cat <<EOF
Usage: ${__SCRIPT_NAME} <from_ref> <to_ref> [OPTION]...

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
EOF
}

#-----------------------------------------------------------------------------
# Logging Utilities
#-----------------------------------------------------------------------------

__info_log() {
    local __param_message="${1}"

    printf "\033[0;34mINFO\033[0m: %b\n" "${__param_message}" >&2
}

__error_log() {
    local __param_message="${1}"

    printf "\033[0;31mERROR\033[0m: %b\n" "${__param_message}" >&2
    exit 1
}

#-----------------------------------------------------------------------------
# Git Utilities
#-----------------------------------------------------------------------------

__git_ref_exists() {
    local __param_ref="${1}"

    git rev-parse --verify --quiet "${__param_ref}^{commit}" &>/dev/null
}

#-----------------------------------------------------------------------------
# Command-Line Argument Parsing and Validation
#-----------------------------------------------------------------------------

__populate_exclude_map() {
    local __param_string="${1}"
    local -n __param_map_ref="${2}"

    local IFS=','
    local -a __items
    read -ra __items <<<"${__param_string}"
    for __item in "${__items[@]}"; do
        __param_map_ref["${__item}"]=1
    done
}

__command_line_parse() {
    local __opts
    if ! __opts="$(getopt --options "hr:v:" --longoptions "exclude-authors:,exclude-invalid-commits,exclude-types:,exclude-scopes:,help,repo-url:,version:" -n "${__SCRIPT_NAME}" -- "${@}")"; then
        __error_log "failed parsing options"
    fi

    eval set -- "${__opts}"

    while true; do
        case "${1}" in
        "--exclude-authors")
            __populate_exclude_map "${2}" __opt_exclude_authors_map
            shift 2
            ;;
        "--exclude-invalid-commits")
            __opt_exclude_invalid_commits=true
            shift
            ;;
        "--exclude-types")
            __populate_exclude_map "${2}" __opt_exclude_types_map
            shift 2
            ;;
        "--exclude-scopes")
            __populate_exclude_map "${2}" __opt_exclude_scopes_map
            shift 2
            ;;
        "-r" | "--repo-url")
            __opt_repo_url="${2}"
            shift 2
            ;;
        "-v" | "--version")
            __opt_version="${2}"
            shift 2
            ;;
        "-h" | "--help")
            __usage_print
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            __error_log "internal error"
            ;;
        esac
    done

    if [[ $# -lt 2 ]]; then
        __error_log "missing arguments"
    fi

    if [[ $# -gt 2 ]]; then
        __error_log "too many arguments"
    fi

    __arg_from_ref="${1}"
    __arg_to_ref="${2}"
}

__command_line_validate() {
    if ! command -v git &>/dev/null; then
        __error_log "git is not installed or not in PATH"
    fi

    if ! __git_ref_exists "${__arg_from_ref}"; then
        __error_log "invalid 'from' ref: '${__arg_from_ref}'"
    fi

    if ! __git_ref_exists "${__arg_to_ref}"; then
        __error_log "invalid 'to' ref: '${__arg_to_ref}'"
    fi
}

#-----------------------------------------------------------------------------
# Core Business Logic
#-----------------------------------------------------------------------------

#
# Parses the raw Git log, applies filtering rules, and standardizes data.
# Output format: type|hash|scope|description
#
__generate_commit_data() {
    local __commit_block=""
    local __line

    # Git log format: Hash, AuthorName, Subject, Body, EndDelimiter
    local __git_format="%H%n%an%n%s%n%b%n==END=="

    while IFS= read -r __line || [[ -n "${__line}" ]]; do
        if [[ "${__line}" == "==END==" ]]; then
            if [[ -n "${__commit_block}" ]]; then

                # ---------------------------------------------------------
                # Parsing: Hash, Author, Rest
                # ---------------------------------------------------------

                # 1. Extract Hash (Line 1)
                local __commit_hash="${__commit_block%%$'\n'*}"

                # 2. Initialize __commit_rest with everything AFTER the hash
                #    Currently: Author\nSubject\nBody...
                local __commit_rest="${__commit_block#*$'\n'}"

                # 3. Extract Author (First line of __commit_rest)
                local __commit_author="${__commit_rest%%$'\n'*}"

                # 4. Remove Author from __commit_rest
                #    Currently: Subject\nBody...
                __commit_rest="${__commit_rest#*$'\n'}"

                # ---------------------------------------------------------
                # Filtering (Author)
                # ---------------------------------------------------------

                if [[ -n "${__opt_exclude_authors_map[${__commit_author}]:-}" ]]; then
                    __commit_block=""
                    continue
                fi

                # 5. Extract Subject (First line of new __commit_rest)
                local __subject="${__commit_rest%%$'\n'*}"

                # ---------------------------------------------------------
                # Rule 1: Conventional Commit Detection
                # ---------------------------------------------------------
                if [[ "${__commit_rest}" =~ ${__REGEX_CONVENTIONAL} ]]; then
                    local __type="${BASH_REMATCH[1]}"
                    local __scope="${BASH_REMATCH[3]}"
                    local __is_header_breaking="${BASH_REMATCH[4]}"
                    local __subject_text="${BASH_REMATCH[5]}"
                    local __desc=""
                    local __is_breaking_change=false

                    # Check Type Exclusion
                    if [[ -n "${__opt_exclude_types_map[${__type}]:-}" ]]; then
                        __commit_block=""
                        continue
                    fi

                    # Check Scope Exclusion
                    if [[ -n "${__scope}" ]] && [[ -n "${__opt_exclude_scopes_map[${__scope}]:-}" ]]; then
                        __commit_block=""
                        continue
                    fi

                    # Determine if this is a breaking change (Header '!' OR Footer text)
                    if [[ -n "${__is_header_breaking}" ]] || [[ "${__commit_rest}" == *"BREAKING CHANGE:"* ]] || [[ "${__commit_rest}" == *"BREAKING CHANGES:"* ]]; then
                        __is_breaking_change=true
                    fi

                    # Format the description (Bold the scope if present)
                    if [[ -n "${__scope}" ]]; then
                        __desc="**${__scope}**: ${__subject_text}"
                    else
                        __desc="${__subject_text}"
                    fi

                    # Output Normal Entry
                    # ONLY if it is NOT a breaking change.
                    # This prevents double listing (once in Features, once in Breaking).
                    if [[ "${__is_breaking_change}" == "false" ]]; then
                        printf "%s|%s|%s|%s\n" "${__type}" "${__commit_hash}" "${__scope}" "${__desc}"
                    fi

                    # Output Breaking Change Entry
                    if [[ "${__is_breaking_change}" == "true" ]]; then
                        if [[ -z "${__opt_exclude_types_map["breaking-change"]:-}" ]]; then
                            local __bc_desc=""
                            # Format: **type(scope)**: subject OR **type**: subject
                            if [[ -n "${__scope}" ]]; then
                                __bc_desc="**${__type}(${__scope})**: ${__subject_text}"
                            else
                                __bc_desc="**${__type}**: ${__subject_text}"
                            fi
                            printf "breaking-change|%s|%s|%s\n" "${__commit_hash}" "" "${__bc_desc}"
                        fi
                    fi

                # ---------------------------------------------------------
                # Rule 2: Non-Conventional but has Breaking Footer
                # ---------------------------------------------------------
                elif [[ "${__commit_rest}" == *"BREAKING CHANGE:"* || "${__commit_rest}" == *"BREAKING CHANGES:"* ]]; then
                    if [[ -z "${__opt_exclude_types_map["breaking-change"]:-}" ]]; then
                        printf "breaking-change|%s|%s|%s\n" "${__commit_hash}" "" "${__subject}"
                    fi

                # ---------------------------------------------------------
                # Rule 3: Non-Conventional (Other)
                # ---------------------------------------------------------
                else
                    local __type="other"

                    if [[ "${__opt_exclude_invalid_commits}" == "true" ]] || [[ -n "${__opt_exclude_types_map[${__type}]:-}" ]]; then
                        __commit_block=""
                        continue
                    fi

                    printf "%s|%s|%s|%s\n" "${__type}" "${__commit_hash}" "" "${__subject}"
                fi
            fi
            __commit_block=""
        else
            __commit_block+="${__line}"$'\n'
        fi
    done < <(git log --pretty=format:"${__git_format}" "${__arg_from_ref}..${__arg_to_ref}")
}

#
# Consumes the structured stream and formats it into Markdown.
#
__show_release_notes() {
    local -A __grouped_commits
    local -i __line_count=0
    local __type __hash __scope __desc

    for __type in "${!__SECTION_TITLES[@]}"; do
        __grouped_commits["${__type}"]=""
    done

    # Read piped data from __generate_commit_data
    while IFS='|' read -r __type __hash __scope __desc || [[ -n "${__type}" ]]; do
        if [[ -n "${__type}" ]]; then
            __grouped_commits["${__type}"]+="${__hash}|${__scope}|${__desc}"$'\n'
            __line_count=$((__line_count + 1))
        fi
    done

    # If no data flowed through the pipe, inform the user (to stderr).
    if [[ ${__line_count} -eq 0 ]]; then
        __info_log "no matching commits found between '${__arg_from_ref}' and '${__arg_to_ref}'"
        return 0
    fi

    # ---------------------------------------------------------
    # Render Output
    # ---------------------------------------------------------

    # 1. Render Header
    if [[ -n "${__opt_repo_url}" ]]; then
        printf "# [%s](%s/compare/%s...%s)\n\n" "${__opt_version:-Unreleased}" "${__opt_repo_url}" "${__arg_from_ref}" "${__arg_to_ref}"
    else
        printf "# %s\n\n" "${__opt_version:-Unreleased}"
    fi

    # 2. Render Sections (in specific priority order)
    for __type in "${__SECTION_ORDER[@]}"; do
        if [[ -n "${__grouped_commits[${__type}]:-}" ]]; then
            printf "## %s\n\n" "${__SECTION_TITLES[${__type}]}"

            # Iterate through the lines collected for this specific type
            while IFS='|' read -r __hash __scope __desc; do
                if [[ -n "${__hash}" ]]; then
                    local __link="${__hash:0:7}"
                    [[ -n "${__opt_repo_url}" ]] && __link="[${__link}](${__opt_repo_url}/commit/${__hash})"

                    printf "* %s - %s\n" "${__link}" "${__desc}"
                fi
            done <<<"${__grouped_commits[${__type}]}"

            printf "\n"
        fi
    done
}

#=============================================================================
# Main Function

main() {
    # Parse command-line options
    __command_line_parse "${@}"

    # Validate the parsed options and arguments
    __command_line_validate

    # Pipeline: Generate Data -> Format Release Notes
    __generate_commit_data | __show_release_notes
}

# Execute the main function with provided arguments
main "${@}"

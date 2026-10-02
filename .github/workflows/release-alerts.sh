#!/usr/bin/env bash
#
# Discovery and state helpers for .github/workflows/detect-releases.yaml.
#
# The "already announced" ledger lives on a dedicated bot branch
# (release-alerts by default) rather than on the default branch. This makes
# a recorded version durable the moment it is written, independently of
# whether - or when - the distribution actually adopts it, and without
# depending on branch protection or a pull request being merged.
#
# Commands:
#   upstream                 stable upstream tags, oldest first
#   tracked-minors           minor lines this repository tracks
#   repo-version <minor>     newest version pinned in this repo for a minor
#   detect-minor             new minor lines as "<minor>\t<latest tag>"
#   detect-patch             new patch tags on tracked minor lines
#   state-read <key>         JSON array of already announced values for key
#   state-write <key> <v>..  merge values into key and push the ledger
#
# Environment:
#   GITHUB_REPOSITORY  owner/repo to hold the ledger (set by Actions)
#   GH_TOKEN           token with contents:write (set by Actions)
#   UPSTREAM_REPO      upstream project, default openbao/openbao
#   STATE_BRANCH       ledger branch, default release-alerts
#   STATE_FILE         ledger path on the branch, default notified-releases.json

set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-openbao/openbao}"
STATE_BRANCH="${STATE_BRANCH:-release-alerts}"
STATE_FILE="${STATE_FILE:-notified-releases.json}"

# Print every stable upstream release tag, oldest first. GitHub's prerelease
# flag is not always set on prerelease tags (e.g. v2.2.0-beta20250213), so
# the tag shape is enforced as well.
upstream() {
  gh api --paginate "repos/${UPSTREAM_REPO}/releases?per_page=100" \
    --jq '.[] | select(.draft == false) | select(.prerelease == false) | .tag_name' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -uV
}

# Print the minor lines this repository tracks, oldest first. A minor counts
# as tracked when it appears in releases/, images/ or vex/.
tracked_minors() {
  {
    for f in releases/release-v*.trivyignore; do
      [ -e "$f" ] && basename "$f" .trivyignore | sed 's/^release-//'
    done
    for d in images/v*; do
      [ -d "$d" ] && basename "$d" | sed -E 's/^(v[0-9]+\.[0-9]+)\..*/\1/'
    done
    for f in vex/v*.json; do
      [ -e "$f" ] && basename "$f" .json
    done
  } | grep -E '^v[0-9]+\.[0-9]+$' | sort -uV
}

# Print the newest version pinned in this repository for one minor line,
# e.g. v2.6.2. Falls back to <minor>.0 when the minor has no image pins yet.
repo_version() {
  local minor="$1" dir best=""
  for dir in images/"${minor}".*; do
    [ -d "$dir" ] || continue
    best="$(printf '%s\n%s\n' "${best}" "$(basename "$dir")" \
      | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n 1)"
  done
  printf '%s\n' "${best:-${minor}.0}"
}

# True when a newline separated list contains an exact value.
list_contains() {
  local needle="$1" list="$2"
  [ -n "$list" ] || return 1
  printf '%s\n' "$list" | grep -Fqx -- "$needle"
}

# Print minor lines that upstream has and this repository does not track yet,
# as "<minor>\t<latest tag on that minor>". Only lines strictly newer than
# the highest tracked minor are considered; older untracked lines (which a
# fresh repository simply never adopted) are ignored.
detect_minor() {
  local tags tracked highest notified minor latest
  tags="$(upstream)"
  tracked="$(tracked_minors)"
  highest="$(printf '%s\n' "$tracked" | sort -V | tail -n 1)"
  notified="$(state_read minor | jq -r '.[]')"
  printf '%s\n' "$tags" \
    | sed -E 's/^(v[0-9]+\.[0-9]+)\..*/\1/' | sort -uV \
    | while read -r minor; do
        [ -n "$minor" ] || continue
        [ "$(printf '%s\n%s\n' "$highest" "$minor" | sort -V | tail -n 1)" = "$minor" ] || continue
        [ "$minor" != "$highest" ] || continue
        list_contains "$minor" "$notified" && continue
        latest="$(printf '%s\n' "$tags" | grep -E "^${minor//./\\.}\." | sort -V | tail -n 1)"
        printf '%s\t%s\n' "$minor" "$latest"
      done
}

# Print patch tags that upstream has on tracked minor lines above the version
# pinned in this repository, oldest first.
detect_patch() {
  local tags tracked notified minor known tag
  tags="$(upstream)"
  tracked="$(tracked_minors)"
  notified="$(state_read patch | jq -r '.[]')"
  while read -r minor; do
    [ -n "$minor" ] || continue
    known="$(repo_version "$minor")"
    printf '%s\n' "$tags" | grep -E "^${minor//./\\.}\." | sort -V | while read -r tag; do
      [ "$(printf '%s\n%s\n' "$known" "$tag" | sort -V | tail -n 1)" = "$tag" ] || continue
      [ "$tag" != "$known" ] || continue
      list_contains "$tag" "$notified" && continue
      printf '%s\n' "$tag"
    done
  done <<<"$tracked"
}

# Read the JSON array of already announced values for one key.
state_read() {
  local key="$1" content
  if content="$(gh api "repos/${GITHUB_REPOSITORY}/contents/${STATE_FILE}?ref=${STATE_BRANCH}" --jq '.content' 2>/dev/null)"; then
    printf '%s' "$content" | base64 -d | jq -c --arg k "$key" '.[$k] // []'
  else
    echo '[]'
  fi
}

# Merge values into one key of the ledger, creating the branch and file on
# first use. Retries a few times to absorb concurrent updates.
state_write() {
  local key="$1"; shift
  [ "$#" -gt 0 ] || return 0
  local add_json attempt args sha state resp b64
  add_json="$(jq -cn --args '$ARGS.positional' -- "$@")"
  for attempt in 1 2 3; do
    if resp="$(gh api "repos/${GITHUB_REPOSITORY}/contents/${STATE_FILE}?ref=${STATE_BRANCH}" 2>/dev/null)"; then
      sha="$(jq -r '.sha' <<<"$resp")"
      state="$(jq -r '.content' <<<"$resp" | base64 -d)"
    else
      sha=""
      state='{}'
    fi
    state="$(printf '%s' "$state" | jq -c --arg k "$key" --argjson add "$add_json" \
      '.[$k] = ((.[$k] // []) + $add | unique)')"
    if [ -z "$sha" ] && ! gh api "repos/${GITHUB_REPOSITORY}/branches/${STATE_BRANCH}" >/dev/null 2>&1; then
      local base base_sha
      base="$(gh api "repos/${GITHUB_REPOSITORY}" --jq '.default_branch')"
      base_sha="$(gh api "repos/${GITHUB_REPOSITORY}/git/ref/heads/${base}" --jq '.object.sha')"
      gh api --method POST "repos/${GITHUB_REPOSITORY}/git/refs" \
        -f ref="refs/heads/${STATE_BRANCH}" -f sha="$base_sha" >/dev/null
    fi
    b64="$(printf '%s' "$state" | base64 -w0)"
    args=(--method PUT "repos/${GITHUB_REPOSITORY}/contents/${STATE_FILE}"
      -f "message=chore: record notified OpenBao releases"
      -f "content=${b64}"
      -f "branch=${STATE_BRANCH}")
    [ -n "$sha" ] && args+=(-f "sha=${sha}")
    if gh api "${args[@]}" >/dev/null; then
      echo "recorded ${key}: $*"
      return 0
    fi
    echo "state write attempt ${attempt} failed; retrying" >&2
    sleep 2
  done
  echo "could not update ${STATE_FILE} on ${STATE_BRANCH}" >&2
  return 1
}

main() {
  local cmd="${1:-}"
  [ "$#" -gt 0 ] && shift || true
  case "$cmd" in
    upstream) upstream ;;
    tracked-minors) tracked_minors ;;
    repo-version) repo_version "$@" ;;
    detect-minor) detect_minor ;;
    detect-patch) detect_patch ;;
    state-read) state_read "$@" ;;
    state-write) state_write "$@" ;;
    *)
      echo "usage: $0 {upstream|tracked-minors|repo-version|detect-minor|detect-patch|state-read|state-write} ..." >&2
      exit 2
      ;;
  esac
}

main "$@"

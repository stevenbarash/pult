#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-Pult.xcodeproj}"
SCHEME="${SCHEME:-Pult Release Direct}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=iOS}"
XCODE_DEVELOPER_DIR="${XCODE_DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
EXPORT_OPTIONS="${EXPORT_OPTIONS:-Config/TestFlightInternalExportOptions.plist}"
EXPECTED_POSTHOG_HOST="${EXPECTED_POSTHOG_HOST:-https://f.barash.me}"
STAMP="${STAMP:-$(date +%Y%m%d-%H%M%S)}"
ARCHIVE_PATH="${ARCHIVE_PATH:-.build/Archives/Pult-Internal-${STAMP}.xcarchive}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-.build/TestFlightDerivedData}"
EXPORT_PATH="${EXPORT_PATH:-.build/TestFlightExport-${STAMP}}"
MESSAGE="${MESSAGE:-}"
DRY_RUN="${DRY_RUN:-0}"
ALLOW_MAIN="${ALLOW_MAIN:-0}"

usage() {
  cat <<'EOF'
Usage: Scripts/ship-testflight.sh [options]

Options:
  --message MESSAGE   Commit message to use when the worktree has changes.
  --dry-run           Print the ship plan without committing, pushing, archiving, or uploading.
  --allow-main        Allow running from main/master.
  --archive-path PATH Override the archive path.
  --export-path PATH  Override the export path.
  --export-options PATH
                      Override the export options plist.
  --help              Show this help.

Environment overrides:
  MESSAGE, DRY_RUN, ALLOW_MAIN, PROJECT, SCHEME, CONFIGURATION, DESTINATION,
  XCODE_DEVELOPER_DIR, EXPORT_OPTIONS, EXPECTED_POSTHOG_HOST, ARCHIVE_PATH,
  DERIVED_DATA_PATH, EXPORT_PATH, STAMP.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --message)
      MESSAGE="${2:-}"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --allow-main)
      ALLOW_MAIN=1
      shift
      ;;
    --archive-path)
      ARCHIVE_PATH="${2:-}"
      shift 2
      ;;
    --export-path)
      EXPORT_PATH="${2:-}"
      shift 2
      ;;
    --export-options)
      EXPORT_OPTIONS="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$DRY_RUN" in
  1|true|TRUE|yes|YES) DRY_RUN=1 ;;
  *) DRY_RUN=0 ;;
esac

case "$ALLOW_MAIN" in
  1|true|TRUE|yes|YES) ALLOW_MAIN=1 ;;
  *) ALLOW_MAIN=0 ;;
esac

run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

read_plist() {
  local key_path="$1"
  local plist="$2"
  /usr/libexec/PlistBuddy -c "Print ${key_path}" "$plist"
}

has_worktree_changes() {
  ! git diff --quiet ||
    ! git diff --cached --quiet ||
    [[ -n "$(git ls-files --others --exclude-standard)" ]]
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 66
  fi
}

branch="$(git branch --show-current)"
if [[ -z "$branch" ]]; then
  echo "Cannot ship from a detached HEAD." >&2
  exit 1
fi

if [[ "$ALLOW_MAIN" != 1 && ( "$branch" == "main" || "$branch" == "master" ) ]]; then
  echo "Refusing to ship directly from $branch. Use a release branch or pass --allow-main." >&2
  exit 1
fi

if has_worktree_changes && [[ -z "$MESSAGE" ]]; then
  echo "Worktree has changes; provide --message or MESSAGE=... for the commit." >&2
  exit 64
fi

require_file "$EXPORT_OPTIONS"
export DEVELOPER_DIR="$XCODE_DEVELOPER_DIR"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "DRY RUN: no commit, push, archive, or upload will be performed"
  echo "Branch: $branch"
  echo "Archive path: $ARCHIVE_PATH"
  echo "Export options: $EXPORT_OPTIONS"
  if has_worktree_changes; then
    echo "Would commit dirty worktree:"
    echo "git commit -m $MESSAGE"
  else
    echo "Would skip commit because worktree is clean"
  fi
  echo "Would push current branch:"
  echo "git push -u origin $branch"
  echo "Would run xcodebuild archive for scheme '$SCHEME'"
  echo "Would verify PultPostHogHost equals '$EXPECTED_POSTHOG_HOST'"
  echo "Would verify PultCore.framework CFBundleShortVersionString and CFBundleVersion"
  echo "Would upload with xcodebuild -exportArchive"
fi

run make metadata-check
run make xcode-project-check

run xcodebuild \
  -quiet \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -allowProvisioningUpdates \
  archive

app_info="$ARCHIVE_PATH/Products/Applications/Pult.app/Info.plist"
core_info="$ARCHIVE_PATH/Products/Applications/Pult.app/Frameworks/PultCore.framework/Info.plist"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "+ verify built artifact: $app_info"
  echo "+ verify built artifact: $core_info"
else
  posthog_host="$(read_plist :PultPostHogHost "$app_info")"
  if [[ "$posthog_host" != "$EXPECTED_POSTHOG_HOST" ]]; then
    echo "Unexpected PultPostHogHost: $posthog_host" >&2
    exit 1
  fi

  app_version="$(read_plist :CFBundleShortVersionString "$app_info")"
  app_build="$(read_plist :CFBundleVersion "$app_info")"
  core_version="$(read_plist :CFBundleShortVersionString "$core_info")"
  core_build="$(read_plist :CFBundleVersion "$core_info")"

  if [[ -z "$app_version" || -z "$app_build" || -z "$core_version" || -z "$core_build" ]]; then
    echo "Archive is missing app or PultCore version metadata." >&2
    exit 1
  fi

  echo "Verified archive: app ${app_version} (${app_build}), PultCore ${core_version} (${core_build}), PostHog host ${posthog_host}"
fi

if has_worktree_changes; then
  run git add -A
  run git commit -m "$MESSAGE"
else
  echo "No worktree changes to commit."
fi

run git push -u origin "$branch"

run xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates

if [[ "$DRY_RUN" == 1 ]]; then
  echo "Dry run completed."
else
  upload_state="$(read_plist :Distributions:0:uploadEvent:state "$ARCHIVE_PATH/Info.plist")"
  uploaded_build="$(read_plist :Distributions:0:uploadedBuildNumber "$ARCHIVE_PATH/Info.plist")"
  upload_date="$(read_plist :Distributions:0:uploadEvent:date "$ARCHIVE_PATH/Info.plist")"
  echo "Uploaded TestFlight build ${uploaded_build}; state=${upload_state}; date=${upload_date}; archive=${ARCHIVE_PATH}"
fi

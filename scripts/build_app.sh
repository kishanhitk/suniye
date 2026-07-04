#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="${ROOT_DIR}"
PROJECT_FILE="${PROJECT_DIR}/Suniye.xcodeproj"
CONFIGURATION="Release"
INSTALL_TARGET=""
SHOULD_OPEN="0"
DERIVED_DATA_PATH="${PROJECT_DIR}/.derivedData"
OUTPUT_DIR=""
BUILD_DESTINATION=""
BUILD_ARCH=""
VERSION=""
BUILD_NUMBER=""
BUILD_CHANNEL="${SUNIYE_BUILD_CHANNEL:-stable}"
BUILD_CHANNEL_EXPLICIT="0"
LOCAL_CODESIGN_IDENTITY=""
SHOULD_RELEASE_SIGN="0"
APP_VARIANT="stable"

usage() {
  cat <<'USAGE'
Usage: scripts/build_app.sh [Debug|Release] [--install-user] [--install-system] [--open]

Options:
  --preview         Build as Suniye Preview for side-by-side local development
  --variant <stable|preview>
                    Select app identity variant (default: stable)
  --install-user    Copy app to ~/Applications/<app-name>.app
  --install-system  Copy app to /Applications/<app-name>.app
  --derived-data-path <path>  Override derived data path
  --output-dir <dir>          Copy built app to a deterministic output directory
  --version <vX.Y.Z>          Override MARKETING_VERSION in the build
  --build-number <number>     Override CURRENT_PROJECT_VERSION in the build
  --build-channel <stable|tip> Embed the installed build channel
  --codesign-identity <name>  Use a specific signing identity
  --release-sign              Re-sign release bundle inside-out after build
  --open            Open the resulting app after build/install
USAGE
}

channel_rank() {
  case "$1" in
    tip)
      echo "1"
      ;;
    stable)
      echo "8"
      ;;
    *)
      echo "Unknown build channel: $1" >&2
      return 1
      ;;
  esac
}

configure_app_variant() {
  case "$1" in
    stable)
      APP_PRODUCT_NAME="Suniye"
      APP_DISPLAY_NAME="Suniye"
      APP_BUNDLE_IDENTIFIER="dev.suniye.app"
      UPDATES_ENABLED="YES"
      STABLE_APPCAST_URL="https://suniye.kishans.in/appcast.xml"
      ;;
    preview)
      APP_PRODUCT_NAME="Suniye Preview"
      APP_DISPLAY_NAME="Suniye Preview"
      APP_BUNDLE_IDENTIFIER="dev.suniye.app.preview"
      UPDATES_ENABLED="NO"
      STABLE_APPCAST_URL=""
      if [[ "${BUILD_CHANNEL_EXPLICIT}" != "1" ]]; then
        BUILD_CHANNEL="tip"
      fi
      ;;
    *)
      echo "Unknown app variant: $1" >&2
      usage >&2
      exit 1
      ;;
  esac

  APP_BUNDLE_NAME="${APP_PRODUCT_NAME}.app"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    Debug|Release)
      CONFIGURATION="$1"
      ;;
    --install-user)
      INSTALL_TARGET="${HOME}/Applications"
      ;;
    --install-system)
      INSTALL_TARGET="/Applications"
      ;;
    --derived-data-path)
      DERIVED_DATA_PATH="$2"
      shift
      ;;
    --output-dir)
      OUTPUT_DIR="$2"
      shift
      ;;
    --version)
      VERSION="$2"
      shift
      ;;
    --build-number)
      BUILD_NUMBER="$2"
      shift
      ;;
    --build-channel)
      BUILD_CHANNEL="$2"
      BUILD_CHANNEL_EXPLICIT="1"
      shift
      ;;
    --preview)
      APP_VARIANT="preview"
      ;;
    --variant)
      APP_VARIANT="$2"
      shift
      ;;
    --codesign-identity)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "--codesign-identity requires a value." >&2
        usage >&2
        exit 1
      fi
      LOCAL_CODESIGN_IDENTITY="$2"
      shift
      ;;
    --release-sign)
      SHOULD_RELEASE_SIGN="1"
      ;;
    --open)
      SHOULD_OPEN="1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

configure_app_variant "${APP_VARIANT}"

if [[ -z "${BUILD_DESTINATION}" ]]; then
  case "$(uname -m)" in
    arm64)
      BUILD_DESTINATION="platform=macOS,arch=arm64"
      BUILD_ARCH="arm64"
      ;;
    x86_64)
      BUILD_DESTINATION="platform=macOS,arch=x86_64"
      BUILD_ARCH="x86_64"
      ;;
    *)
      BUILD_DESTINATION="platform=macOS"
      ;;
  esac
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required. Install full Xcode and run xcode-select --switch /Applications/Xcode.app" >&2
  exit 1
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is not active. Run: sudo xcode-select --switch /Applications/Xcode.app" >&2
  exit 1
fi

CHANNEL_RANK="$(channel_rank "${BUILD_CHANNEL}")"

if [[ -z "${BUILD_NUMBER}" ]]; then
  BUILD_NUMBER="${SUNIYE_BUILD_NUMBER:-}"
fi

if [[ -z "${BUILD_NUMBER}" ]] && git -C "${ROOT_DIR}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  COMMIT_COUNT="$(git -C "${ROOT_DIR}" rev-list --count HEAD)"
  BUILD_NUMBER="$((COMMIT_COUNT * 10 + CHANNEL_RANK))"
fi

if [[ -n "${BUILD_NUMBER}" ]] && [[ ! "${BUILD_NUMBER}" =~ ^[0-9]+$ ]]; then
  echo "Build number must be numeric, got: ${BUILD_NUMBER}" >&2
  exit 1
fi

if [[ -z "${LOCAL_CODESIGN_IDENTITY}" ]]; then
  LOCAL_CODESIGN_IDENTITY="${SUNIYE_CODESIGN_IDENTITY:-}"
fi

if [[ "${SHOULD_RELEASE_SIGN}" == "1" && -z "${LOCAL_CODESIGN_IDENTITY}" ]]; then
  echo "--release-sign requires --codesign-identity or SUNIYE_CODESIGN_IDENTITY." >&2
  exit 1
fi

if [[ "${SHOULD_RELEASE_SIGN}" != "1" && -z "${LOCAL_CODESIGN_IDENTITY}" ]] && command -v security >/dev/null 2>&1; then
  LOCAL_CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"Suniye Local Dev"/ { print $2; exit }')"
fi

xcodegen generate --spec "${PROJECT_DIR}/project.yml"

xcodebuild_args=(
  -project "${PROJECT_FILE}"
  -scheme "Suniye"
  -configuration "${CONFIGURATION}"
  -derivedDataPath "${DERIVED_DATA_PATH}"
  -destination "${BUILD_DESTINATION}"
  build
)

if [[ -n "${BUILD_ARCH}" ]]; then
  xcodebuild_args+=(ARCHS="${BUILD_ARCH}" ONLY_ACTIVE_ARCH=YES)
fi

if [[ -n "${VERSION}" ]]; then
  # Strip leading 'v' prefix (v0.0.5 -> 0.0.5)
  MARKETING="${VERSION#v}"
  xcodebuild_args+=(MARKETING_VERSION="${MARKETING}")
fi

if [[ -n "${BUILD_NUMBER}" ]]; then
  xcodebuild_args+=(CURRENT_PROJECT_VERSION="${BUILD_NUMBER}")
fi

xcodebuild_args+=(SUNIYE_BUILD_CHANNEL="${BUILD_CHANNEL}")
xcodebuild_args+=(
  SUNIYE_PRODUCT_NAME="${APP_PRODUCT_NAME}"
  SUNIYE_DISPLAY_NAME="${APP_DISPLAY_NAME}"
  SUNIYE_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER}"
  SUNIYE_UPDATES_ENABLED="${UPDATES_ENABLED}"
  SUNIYE_STABLE_APPCAST_URL="${STABLE_APPCAST_URL}"
)

if [[ -n "${LOCAL_CODESIGN_IDENTITY}" ]]; then
  echo "Using local signing identity: ${LOCAL_CODESIGN_IDENTITY}"
  xcodebuild_args+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="${LOCAL_CODESIGN_IDENTITY}"
  )

  if [[ -n "${SUNIYE_CODESIGN_KEYCHAIN_PATH:-}" ]]; then
    xcodebuild_args+=(OTHER_CODE_SIGN_FLAGS="--timestamp=none --keychain ${SUNIYE_CODESIGN_KEYCHAIN_PATH}")
  elif [[ "${SHOULD_RELEASE_SIGN}" == "1" ]]; then
    xcodebuild_args+=(OTHER_CODE_SIGN_FLAGS="--timestamp=none")
  fi
fi

if [[ "${SHOULD_RELEASE_SIGN}" == "1" ]]; then
  xcodebuild_args+=(
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
    ENABLE_HARDENED_RUNTIME=NO
  )
fi

xcodebuild "${xcodebuild_args[@]}"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/${APP_BUNDLE_NAME}"
SPARKLE_FRAMEWORK_PATH="${APP_PATH}/Contents/Frameworks/Sparkle.framework"
if [[ -d "${SPARKLE_FRAMEWORK_PATH}" ]]; then
  SPARKLE_FRAMEWORK_VERSION="$(readlink "${SPARKLE_FRAMEWORK_PATH}/Versions/Current" 2>/dev/null || true)"
  if [[ -z "${SPARKLE_FRAMEWORK_VERSION}" || "${SPARKLE_FRAMEWORK_VERSION}" == /* || "${SPARKLE_FRAMEWORK_VERSION}" == *".."* ]]; then
    SPARKLE_FRAMEWORK_VERSION="B"
  fi

  SPARKLE_UPDATER_DEST="${SPARKLE_FRAMEWORK_PATH}/Versions/${SPARKLE_FRAMEWORK_VERSION}/Updater.app"
  SPARKLE_UPDATER_SOURCE="${DERIVED_DATA_PATH}/Build/Products/${CONFIGURATION}/Sparkle.framework/Versions/${SPARKLE_FRAMEWORK_VERSION}/Updater.app"
  if [[ ! -d "${SPARKLE_UPDATER_DEST}" ]]; then
    if [[ ! -d "${SPARKLE_UPDATER_SOURCE}" ]]; then
      echo "Sparkle Updater.app is missing from the embedded framework and the built framework product." >&2
      exit 1
    fi
    /usr/bin/ditto "${SPARKLE_UPDATER_SOURCE}" "${SPARKLE_UPDATER_DEST}"
    echo "Restored Sparkle Updater.app in embedded framework."
  fi
fi

if [[ "${SHOULD_RELEASE_SIGN}" == "1" ]]; then
  "${ROOT_DIR}/scripts/sign_release_app.sh" "${APP_PATH}" "${LOCAL_CODESIGN_IDENTITY}"
fi

FINAL_APP_PATH="${APP_PATH}"
SHOULD_CLEAN_DERIVED_APP="0"

if [[ -n "${INSTALL_TARGET}" ]]; then
  mkdir -p "${INSTALL_TARGET}"
  DEST_APP_PATH="${INSTALL_TARGET}/${APP_BUNDLE_NAME}"
  rm -rf "${DEST_APP_PATH}"
  ditto "${APP_PATH}" "${DEST_APP_PATH}"
  LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
  if [[ -x "${LSREGISTER}" ]]; then
    "${LSREGISTER}" -u "${APP_PATH}" >/dev/null 2>&1 || true
    "${LSREGISTER}" -f -R -trusted "${DEST_APP_PATH}" >/dev/null 2>&1 || true
  fi
  SHOULD_CLEAN_DERIVED_APP="1"
  FINAL_APP_PATH="${DEST_APP_PATH}"
  echo "Installed app to: ${DEST_APP_PATH}"
fi

if [[ -n "${OUTPUT_DIR}" ]]; then
  mkdir -p "${OUTPUT_DIR}"
  OUTPUT_APP_PATH="${OUTPUT_DIR}/${APP_BUNDLE_NAME}"
  rm -rf "${OUTPUT_APP_PATH}"
  ditto "${APP_PATH}" "${OUTPUT_APP_PATH}"
  FINAL_APP_PATH="${OUTPUT_APP_PATH}"
  echo "Copied app to output directory: ${OUTPUT_APP_PATH}"
fi

if [[ "${SHOULD_CLEAN_DERIVED_APP}" == "1" ]]; then
  rm -rf "${APP_PATH}"
fi

if [[ "${SHOULD_OPEN}" == "1" ]]; then
  open "${FINAL_APP_PATH}"
fi

echo "Build complete: ${FINAL_APP_PATH}"

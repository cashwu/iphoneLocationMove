#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_NAME="iPhoneLocationMove"
SCHEME_NAME="iPhoneLocationMove"
PROJECT_FILE="$PROJECT_DIR/iPhoneLocationMove.xcodeproj"
PROJECT_MARKER="$PROJECT_FILE/project.pbxproj"
SCHEME_MARKER="$PROJECT_FILE/xcshareddata/xcschemes/iPhoneLocationMove.xcscheme"
BUILD_DIR="$PROJECT_DIR/build"
LOG_DIR="$BUILD_DIR/Logs"
DERIVED_DATA_DIR="$BUILD_DIR/DerivedData"
EXPORT_PATH="$BUILD_DIR/Export"
APP_PATH="$EXPORT_PATH/iPhoneLocationMove.app"
APP_INFO_PATH="$APP_PATH/Contents/Info.plist"
HELPER_PATH="$APP_PATH/Contents/Library/LaunchServices/com.cash.iPhoneLocationMoveTunnelHelper"
EXPECTED_APP_IDENTIFIER="com.cash.iPhoneLocationMove"
EXPECTED_HELPER_IDENTIFIER="com.cash.iPhoneLocationMoveTunnelHelper"
EXPECTED_TEAM="2LRM76M575"
EXPECTED_APP_REQUIREMENT='identifier "com.cash.iPhoneLocationMove" and anchor apple generic and certificate leaf[subject.OU] = "2LRM76M575"'
EXPECTED_HELPER_REQUIREMENT='identifier "com.cash.iPhoneLocationMoveTunnelHelper" and anchor apple generic and certificate leaf[subject.OU] = "2LRM76M575"'

CLEAN_BUILD=true
SKIP_TESTS=false
CREATE_DMG=true
VERSION=""
EXPECTED_VERSION="1.0"
DMG_PATH="$BUILD_DIR/iPhoneLocationMove.dmg"
VERIFY_DIR=""
DMG_STAGING=""

print_step() {
    printf '==> %s\n' "$1"
}

print_success() {
    printf '[OK] %s\n' "$1"
}

print_warning() {
    printf '[!] %s\n' "$1"
}

print_error() {
    printf '[X] %s\n' "$1" >&2
}

run_logged_step() {
    step_name="$1"
    log_name="$2"
    shift 2

    log_path="$LOG_DIR/$log_name"
    mkdir -p "$LOG_DIR"
    print_step "$step_name"

    if "$@" > "$log_path" 2>&1; then
        print_success "$step_name"
        return 0
    else
        status=$?
    fi

    relative_log="${log_path#"$PROJECT_DIR"/}"
    print_error "${step_name}失敗；完整記錄：${relative_log}"
    tail -n 40 "$log_path" >&2
    return "$status"
}

run_python_protocol_tests() {
    (
        cd "$PROJECT_DIR"
        python3 -m unittest discover -s iPhoneLocationMoveHelper/tests
    )
}

show_help() {
    printf '用法: %s [選項]\n' "$0"
    printf '\n'
    printf '預設執行 Xcode 與 Python tests、Release build、簽署驗證及 DMG 包裝。\n'
    printf '\n'
    printf '選項:\n'
    printf '  -h, --help          顯示此幫助訊息\n'
    printf '  -v, --version VER   覆寫 App 版本並建立版本化 DMG，例如 1.2.3\n'
    printf '  --no-clean          保留 build 目錄並跳過 xcodebuild clean\n'
    printf '  --skip-tests        跳過 Xcode 與 Python tests\n'
    printf '  --no-dmg            只產生並驗證 .app，不建立 DMG\n'
    printf '\n'
    printf '產物:\n'
    printf '  build/Export/iPhoneLocationMove.app\n'
    printf '  build/iPhoneLocationMove[-VER].dmg\n'
}

cleanup() {
    status=$?
    trap - EXIT

    if [ -n "$VERIFY_DIR" ] && [ -d "$VERIFY_DIR" ]; then
        rm -rf "$VERIFY_DIR"
    fi
    if [ -n "$DMG_STAGING" ] && [ -d "$DMG_STAGING" ]; then
        rm -rf "$DMG_STAGING"
    fi

    exit "$status"
}

require_tool() {
    tool_name="$1"
    if ! command -v "$tool_name" >/dev/null 2>&1; then
        print_error "找不到必要工具: $tool_name"
        exit 1
    fi
}

read_signing_field() {
    artifact_path="$1"
    field_name="$2"
    signing_output="$(codesign -dv --verbose=4 "$artifact_path" 2>&1)"
    field_value="$(printf '%s\n' "$signing_output" | sed -n "s/^${field_name}=//p" | head -n 1)"

    if [ -z "$field_value" ]; then
        print_error "無法讀取簽署欄位 ${field_name}: $artifact_path"
        exit 1
    fi

    printf '%s\n' "$field_value"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        --no-clean)
            CLEAN_BUILD=false
            shift
            ;;
        --skip-tests)
            SKIP_TESTS=true
            shift
            ;;
        --no-dmg)
            CREATE_DMG=false
            shift
            ;;
        -v|--version)
            if [ "$#" -lt 2 ] || [ -z "$2" ]; then
                print_error "-v/--version 需要版本值"
                exit 1
            fi
            VERSION="$2"
            shift 2
            ;;
        *)
            print_error "未知選項: $1"
            show_help >&2
            exit 1
            ;;
    esac
done

if [ -n "$VERSION" ]; then
    if ! [[ "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]]; then
        print_error "版本格式無效: ${VERSION}（僅接受以點分隔的數字段）"
        exit 1
    fi
    EXPECTED_VERSION="$VERSION"
    DMG_PATH="$BUILD_DIR/iPhoneLocationMove-$VERSION.dmg"
fi

if [ ! -f "$PROJECT_MARKER" ]; then
    print_error "找不到 Xcode project marker: $PROJECT_MARKER"
    exit 1
fi
if [ ! -f "$SCHEME_MARKER" ]; then
    print_error "找不到 shared scheme: $SCHEME_MARKER"
    exit 1
fi

require_tool xcodebuild
require_tool python3
require_tool codesign
require_tool lipo
require_tool otool
require_tool awk
require_tool xxd
require_tool plutil
if [ "$CREATE_DMG" = true ]; then
    require_tool hdiutil
fi

trap cleanup EXIT

if [ "$CLEAN_BUILD" = true ]; then
    rm -rf "$BUILD_DIR"
    run_logged_step "清理建置輸出" "xcode-clean.log" xcodebuild clean \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME_NAME" \
        -configuration Release
else
    print_warning "保留既有 build 目錄"
fi

mkdir -p "$EXPORT_PATH"

if [ "$SKIP_TESTS" = false ]; then
    run_logged_step "執行 macOS Xcode tests" "xcode-tests.log" xcodebuild test \
        -project "$PROJECT_FILE" \
        -scheme "$SCHEME_NAME" \
        -configuration Debug \
        -destination 'platform=macOS'

    run_logged_step \
        "執行 Python protocol tests" \
        "python-tests.log" \
        run_python_protocol_tests
else
    print_warning "跳過測試（Xcode 與 Python）"
fi

BUILD_ARGUMENTS=(
    build
    -project "$PROJECT_FILE"
    -scheme "$SCHEME_NAME"
    -configuration Release
    -derivedDataPath "$DERIVED_DATA_DIR"
    "CONFIGURATION_BUILD_DIR=$EXPORT_PATH"
)
if [ -n "$VERSION" ]; then
    BUILD_ARGUMENTS+=("MARKETING_VERSION=$VERSION")
fi
run_logged_step \
    "建置 Release App" \
    "xcode-build.log" \
    xcodebuild "${BUILD_ARGUMENTS[@]}"

if [ ! -d "$APP_PATH" ]; then
    print_error "Release build 未產生 App: $APP_PATH"
    exit 1
fi
if [ ! -f "$APP_INFO_PATH" ]; then
    print_error "App 缺少 Info.plist: $APP_INFO_PATH"
    exit 1
fi
if [ ! -f "$HELPER_PATH" ]; then
    print_error "App 缺少 embedded helper: $HELPER_PATH"
    exit 1
fi

actual_version="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_INFO_PATH")"
if [ "$actual_version" != "$EXPECTED_VERSION" ]; then
    print_error "App 版本不符：預期 ${EXPECTED_VERSION}，實際 $actual_version"
    exit 1
fi

print_step "驗證 App 與 privileged helper 簽署"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign --verify --strict --verbose=2 "$HELPER_PATH"

app_identifier="$(read_signing_field "$APP_PATH" Identifier)"
helper_identifier="$(read_signing_field "$HELPER_PATH" Identifier)"
app_team="$(read_signing_field "$APP_PATH" TeamIdentifier)"
helper_team="$(read_signing_field "$HELPER_PATH" TeamIdentifier)"

if [ "$app_identifier" != "$EXPECTED_APP_IDENTIFIER" ]; then
    print_error "App identifier 不符：$app_identifier"
    exit 1
fi
if [ "$helper_identifier" != "$EXPECTED_HELPER_IDENTIFIER" ]; then
    print_error "Helper identifier 不符：$helper_identifier"
    exit 1
fi
if [ "$app_team" != "$EXPECTED_TEAM" ] || [ "$helper_team" != "$EXPECTED_TEAM" ]; then
    print_error "App 與 Helper 必須同屬 Team $EXPECTED_TEAM"
    exit 1
fi

VERIFY_DIR="$(mktemp -d "$BUILD_DIR/package-verify.XXXXXX")"
HELPER_SLICE_PATH="$VERIFY_DIR/helper-slice"
HELPER_INFO_PATH="$VERIFY_DIR/helper-info.plist"
if ! lipo "$HELPER_PATH" -thin "$(uname -m)" -output "$HELPER_SLICE_PATH"; then
    print_error "無法擷取 embedded helper 的目前 architecture slice"
    exit 1
fi
if ! otool -X -s __TEXT __info_plist "$HELPER_SLICE_PATH" |
    awk '{
        for (field = 2; field <= NF; field++) {
            printf "%s%s%s%s", substr($field, 7, 2), substr($field, 5, 2), substr($field, 3, 2), substr($field, 1, 2)
        }
        printf "\n"
    }' |
    xxd -r -p > "$HELPER_INFO_PATH"; then
    print_error "無法擷取 embedded helper 的 __TEXT,__info_plist"
    exit 1
fi
if ! plutil -lint "$HELPER_INFO_PATH" >/dev/null; then
    print_error "Embedded helper metadata 不是有效 plist"
    exit 1
fi

app_requirement="$(plutil -extract 'SMPrivilegedExecutables.com\.cash\.iPhoneLocationMoveTunnelHelper' raw -o - "$APP_INFO_PATH")"
helper_requirement="$(plutil -extract 'SMAuthorizedClients.0' raw -o - "$HELPER_INFO_PATH")"

if [ "$app_requirement" != "$EXPECTED_HELPER_REQUIREMENT" ]; then
    print_error "App 的 SMPrivilegedExecutables requirement 不符"
    exit 1
fi
if [ "$helper_requirement" != "$EXPECTED_APP_REQUIREMENT" ]; then
    print_error "Helper 的 SMAuthorizedClients requirement 不符"
    exit 1
fi

rm -rf "$VERIFY_DIR"
VERIFY_DIR=""
print_success "App、Helper 與雙向 SMJobBless trust contract 驗證通過"

if [ "$CREATE_DMG" = true ]; then
    print_step "建立 DMG"
    DMG_STAGING="$(mktemp -d "$BUILD_DIR/dmg-staging.XXXXXX")"
    cp -R "$APP_PATH" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"
    rm -f "$DMG_PATH"
    hdiutil create \
        -volname "$PROJECT_NAME" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        "$DMG_PATH"
    rm -rf "$DMG_STAGING"
    DMG_STAGING=""
fi

printf '\n'
printf '============================================================\n'
printf '                         打包完成\n'
printf '============================================================\n'
printf '[APP] %s\n' "$APP_PATH"
if [ "$CREATE_DMG" = true ]; then
    printf '[DMG] %s\n' "$DMG_PATH"
fi

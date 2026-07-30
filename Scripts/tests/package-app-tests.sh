#!/bin/bash
set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIR="$(cd "$TESTS_DIR/../.." && pwd)"
PACKAGE_SCRIPT="$REPOSITORY_DIR/Scripts/package-app.sh"
EXPECTED_TEAM="2LRM76M575"
EXPECTED_APP_IDENTIFIER="com.cash.iPhoneLocationMove"
EXPECTED_HELPER_IDENTIFIER="com.cash.iPhoneLocationMoveTunnelHelper"
EXPECTED_APP_REQUIREMENT="identifier \"com.cash.iPhoneLocationMove\" and anchor apple generic and certificate leaf[subject.OU] = \"2LRM76M575\""
EXPECTED_HELPER_REQUIREMENT="identifier \"com.cash.iPhoneLocationMoveTunnelHelper\" and anchor apple generic and certificate leaf[subject.OU] = \"2LRM76M575\""

PASS_COUNT=0
FAIL_COUNT=0
CASE_ROOT=""
FIXTURE_PROJECT=""
COMMAND_LOG=""
LAST_OUTPUT=""
LAST_STATUS=0
REPOSITORY_BUILD_STATE=""

record_pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
}

record_failure() {
    echo "FAIL: $1" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_status() {
    expected="$1"
    if [ "$LAST_STATUS" -eq "$expected" ]; then
        record_pass
    else
        record_failure "expected status $expected, got $LAST_STATUS; output: $LAST_OUTPUT"
    fi
}

assert_success() {
    if [ "$LAST_STATUS" -eq 0 ]; then
        record_pass
    else
        record_failure "expected success, got $LAST_STATUS; output: $LAST_OUTPUT"
    fi
}

assert_failure() {
    if [ "$LAST_STATUS" -ne 0 ]; then
        record_pass
    else
        record_failure "expected failure; output: $LAST_OUTPUT"
    fi
}

assert_output_contains() {
    expected="$1"
    if printf '%s\n' "$LAST_OUTPUT" | grep -Fq -- "$expected"; then
        record_pass
    else
        record_failure "output missing '$expected': $LAST_OUTPUT"
    fi
}

assert_output_excludes() {
    unexpected="$1"
    if printf '%s\n' "$LAST_OUTPUT" | grep -Fq -- "$unexpected"; then
        record_failure "output unexpectedly contains '$unexpected': $LAST_OUTPUT"
    else
        record_pass
    fi
}

assert_log_contains() {
    expected="$1"
    if grep -Fq -- "$expected" "$COMMAND_LOG"; then
        record_pass
    else
        record_failure "command log missing '$expected': $(tr '\n' '|' < "$COMMAND_LOG")"
    fi
}

assert_log_excludes() {
    unexpected="$1"
    if grep -Fq -- "$unexpected" "$COMMAND_LOG"; then
        record_failure "command log unexpectedly contains '$unexpected': $(tr '\n' '|' < "$COMMAND_LOG")"
    else
        record_pass
    fi
}

assert_log_empty() {
    if [ ! -s "$COMMAND_LOG" ]; then
        record_pass
    else
        record_failure "expected empty command log: $(tr '\n' '|' < "$COMMAND_LOG")"
    fi
}

assert_file_exists() {
    path="$1"
    if [ -e "$path" ]; then
        record_pass
    else
        record_failure "expected path to exist: $path"
    fi
}

assert_file_absent() {
    path="$1"
    if [ ! -e "$path" ]; then
        record_pass
    else
        record_failure "expected path to be absent: $path"
    fi
}

assert_file_contains() {
    path="$1"
    expected="$2"
    if [ -f "$path" ] && grep -Fq -- "$expected" "$path"; then
        record_pass
    else
        record_failure "file '$path' missing '$expected'"
    fi
}

assert_no_temporary_directories() {
    leftovers="$(find "$FIXTURE_PROJECT/build" -maxdepth 1 -type d \( -name 'package-verify.*' -o -name 'dmg-staging.*' \) -print 2>/dev/null)"
    if [ -z "$leftovers" ]; then
        record_pass
    else
        record_failure "temporary directories remain: $leftovers"
    fi
}

repository_build_state() {
    if [ -e "$REPOSITORY_DIR/build" ]; then
        find "$REPOSITORY_DIR/build" -type f -exec shasum -a 256 {} \; | LC_ALL=C sort
    else
        printf 'absent\n'
    fi
}

write_shims() {
    shim_dir="$FIXTURE_PROJECT/test-bin"

    mkdir -p "$shim_dir"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "xcodebuild" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        'printf "XCODEBUILD_VERBOSE_DETAIL action=%s\n" "${1:-unknown}"' \
        'action=""' \
        'export_path=""' \
        'version="1.0"' \
        'for argument in "$@"; do' \
        '  case "$argument" in' \
        '    clean|test|build) action="$argument" ;;' \
        '    CONFIGURATION_BUILD_DIR=*) export_path="${argument#CONFIGURATION_BUILD_DIR=}" ;;' \
        '    MARKETING_VERSION=*) version="${argument#MARKETING_VERSION=}" ;;' \
        '  esac' \
        'done' \
        'case "$action" in' \
        '  clean) exit "${FAKE_XCODE_CLEAN_STATUS:-0}" ;;' \
        '  test) exit "${FAKE_XCODE_TEST_STATUS:-0}" ;;' \
        '  build)' \
        '    status="${FAKE_XCODE_BUILD_STATUS:-0}"' \
        '    [ "$status" -eq 0 ] || exit "$status"' \
        '    [ "${FAKE_OMIT_APP:-0}" = "1" ] && exit 0' \
        '    app_path="$export_path/iPhoneLocationMove.app"' \
        '    helper_path="$app_path/Contents/Library/LaunchServices/com.cash.iPhoneLocationMoveTunnelHelper"' \
        '    mkdir -p "$(dirname "$helper_path")"' \
        '    printf "fake helper\n" > "$helper_path"' \
        '    [ "${FAKE_OMIT_HELPER:-0}" = "1" ] && rm -f "$helper_path"' \
        '    bundle_version="${FAKE_BUNDLE_VERSION:-$version}"' \
        '    app_requirement="${FAKE_APP_REQUIREMENT:-identifier \"com.cash.iPhoneLocationMoveTunnelHelper\" and anchor apple generic and certificate leaf[subject.OU] = \"2LRM76M575\"}"' \
        '    printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" "<plist version=\"1.0\"><dict>" "<key>CFBundleShortVersionString</key><string>$bundle_version</string>" "<key>SMPrivilegedExecutables</key><dict><key>com.cash.iPhoneLocationMoveTunnelHelper</key><string>$app_requirement</string></dict>" "</dict></plist>" > "$app_path/Contents/Info.plist"' \
        '    ;;' \
        'esac' \
        'exit 0' \
        > "$shim_dir/xcodebuild"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "python3" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        'printf "PYTHON_VERBOSE_DETAIL\n" >&2' \
        'exit "${FAKE_PYTHON_STATUS:-0}"' \
        > "$shim_dir/python3"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "codesign" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        'target=""' \
        'for argument in "$@"; do target="$argument"; done' \
        'case " $* " in' \
        '  *" --verify "*)' \
        '    if printf "%s" "$target" | grep -q "iPhoneLocationMove.app$"; then exit "${FAKE_APP_VERIFY_STATUS:-0}"; fi' \
        '    exit "${FAKE_HELPER_VERIFY_STATUS:-0}"' \
        '    ;;' \
        '  *" -dv "*)' \
        '    if printf "%s" "$target" | grep -q "iPhoneLocationMove.app$"; then' \
        '      printf "Identifier=%s\nTeamIdentifier=%s\n" "${FAKE_APP_IDENTIFIER:-com.cash.iPhoneLocationMove}" "${FAKE_APP_TEAM:-2LRM76M575}" >&2' \
        '    else' \
        '      printf "Identifier=%s\nTeamIdentifier=%s\n" "${FAKE_HELPER_IDENTIFIER:-com.cash.iPhoneLocationMoveTunnelHelper}" "${FAKE_HELPER_TEAM:-2LRM76M575}" >&2' \
        '    fi' \
        '    ;;' \
        'esac' \
        > "$shim_dir/codesign"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "lipo" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        'status="${FAKE_LIPO_STATUS:-0}"' \
        '[ "$status" -eq 0 ] || exit "$status"' \
        'input="$1"' \
        'output=""' \
        'previous=""' \
        'for argument in "$@"; do' \
        '  if [ "$previous" = "-output" ]; then output="$argument"; fi' \
        '  previous="$argument"' \
        'done' \
        'cp "$input" "$output"' \
        > "$shim_dir/lipo"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "otool" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        'status="${FAKE_OTOOL_STATUS:-0}"' \
        '[ "$status" -eq 0 ] || exit "$status"' \
        'helper_requirement="${FAKE_HELPER_REQUIREMENT:-identifier \"com.cash.iPhoneLocationMove\" and anchor apple generic and certificate leaf[subject.OU] = \"2LRM76M575\"}"' \
        'printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" "<plist version=\"1.0\"><dict><key>SMAuthorizedClients</key><array><string>$helper_requirement</string></array></dict></plist>" |' \
        '  /usr/bin/xxd -p -c 4 |' \
        '  while IFS= read -r word; do' \
        '    printf "0000000000000000\\t%s%s%s%s\\n" "${word:6:2}" "${word:4:2}" "${word:2:2}" "${word:0:2}"' \
        '  done' \
        > "$shim_dir/otool"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "xxd" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        '/usr/bin/xxd "$@"' \
        > "$shim_dir/xxd"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "plutil" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        '/usr/bin/plutil "$@"' \
        > "$shim_dir/plutil"

    printf '%s\n' \
        '#!/bin/bash' \
        'printf "hdiutil" >> "$COMMAND_LOG"' \
        'for argument in "$@"; do printf " <%s>" "$argument" >> "$COMMAND_LOG"; done' \
        'printf "\n" >> "$COMMAND_LOG"' \
        'status="${FAKE_HDIUTIL_STATUS:-0}"' \
        '[ "$status" -eq 0 ] || exit "$status"' \
        'source_folder=""' \
        'output=""' \
        'previous=""' \
        'for argument in "$@"; do' \
        '  if [ "$previous" = "-srcfolder" ]; then source_folder="$argument"; fi' \
        '  previous="$argument"' \
        '  output="$argument"' \
        'done' \
        '[ -d "$source_folder/iPhoneLocationMove.app" ] || exit 51' \
        '[ -L "$source_folder/Applications" ] || exit 52' \
        '[ "$(readlink "$source_folder/Applications")" = "/Applications" ] || exit 53' \
        'mkdir -p "$(dirname "$output")"' \
        'printf "fake dmg\n" > "$output"' \
        > "$shim_dir/hdiutil"

    chmod +x "$shim_dir"/*
}

setup_case() {
    case_name="$1"
    cleanup_case

    CASE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/package app tests.${case_name}.XXXXXX")"
    FIXTURE_PROJECT="$CASE_ROOT/project with spaces"
    COMMAND_LOG="$CASE_ROOT/commands.log"

    mkdir -p "$FIXTURE_PROJECT/Scripts" \
        "$FIXTURE_PROJECT/iPhoneLocationMoveTunnelHelper" \
        "$FIXTURE_PROJECT/iPhoneLocationMove.xcodeproj/xcshareddata/xcschemes" \
        "$FIXTURE_PROJECT/invocation"
    : > "$FIXTURE_PROJECT/iPhoneLocationMove.xcodeproj/project.pbxproj"
    : > "$FIXTURE_PROJECT/iPhoneLocationMove.xcodeproj/xcshareddata/xcschemes/iPhoneLocationMove.xcscheme"
    : > "$COMMAND_LOG"
    printf '%s\n' \
        '<?xml version="1.0" encoding="UTF-8"?>' \
        '<plist version="1.0"><dict><key>SMAuthorizedClients</key><array>' \
        "<string>$EXPECTED_APP_REQUIREMENT</string>" \
        '</array></dict></plist>' \
        > "$FIXTURE_PROJECT/iPhoneLocationMoveTunnelHelper/HelperInfo.plist"

    if [ -f "$PACKAGE_SCRIPT" ]; then
        cp "$PACKAGE_SCRIPT" "$FIXTURE_PROJECT/Scripts/package-app.sh"
        chmod +x "$FIXTURE_PROJECT/Scripts/package-app.sh"
    fi

    unset FAKE_XCODE_CLEAN_STATUS FAKE_XCODE_TEST_STATUS FAKE_XCODE_BUILD_STATUS
    unset FAKE_PYTHON_STATUS FAKE_OMIT_APP FAKE_OMIT_HELPER FAKE_BUNDLE_VERSION
    unset FAKE_APP_VERIFY_STATUS FAKE_HELPER_VERIFY_STATUS FAKE_APP_IDENTIFIER
    unset FAKE_HELPER_IDENTIFIER FAKE_APP_TEAM FAKE_HELPER_TEAM FAKE_LIPO_STATUS
    unset FAKE_OTOOL_STATUS
    unset FAKE_APP_REQUIREMENT FAKE_HELPER_REQUIREMENT FAKE_HDIUTIL_STATUS

    export COMMAND_LOG
    PATH="$FIXTURE_PROJECT/test-bin:/usr/bin:/bin:/usr/sbin:/sbin"
    export PATH
    write_shims
}

cleanup_case() {
    if [ -n "$CASE_ROOT" ] && [ -d "$CASE_ROOT" ]; then
        rm -rf "$CASE_ROOT"
    fi
    CASE_ROOT=""
    FIXTURE_PROJECT=""
    COMMAND_LOG=""
}

run_package() {
    LAST_OUTPUT=""
    LAST_STATUS=0
    if [ ! -x "$FIXTURE_PROJECT/Scripts/package-app.sh" ]; then
        LAST_OUTPUT="package script is missing"
        LAST_STATUS=127
        return
    fi

    LAST_OUTPUT="$(
        cd "$FIXTURE_PROJECT/invocation" &&
        "$FIXTURE_PROJECT/Scripts/package-app.sh" "$@" 2>&1
    )"
    LAST_STATUS=$?
}

assert_pipeline_order() {
    clean_line="$(grep -n '^xcodebuild <clean>' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
    xcode_test_line="$(grep -n '^xcodebuild <test>' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
    python_line="$(grep -n '^python3' "$COMMAND_LOG" | head -1 | cut -d: -f1)"
    build_line="$(grep -n '^xcodebuild <build>' "$COMMAND_LOG" | head -1 | cut -d: -f1)"

    if [ -n "$clean_line" ] && [ -n "$xcode_test_line" ] && [ -n "$python_line" ] && [ -n "$build_line" ] &&
       [ "$clean_line" -lt "$xcode_test_line" ] &&
       [ "$xcode_test_line" -lt "$python_line" ] &&
       [ "$python_line" -lt "$build_line" ]; then
        record_pass
    else
        record_failure "pipeline order is incorrect: $(tr '\n' '|' < "$COMMAND_LOG")"
    fi
}

test_help_and_invalid_arguments() {
    setup_case help
    run_package --help
    assert_success
    assert_output_contains "--skip-tests"
    assert_output_contains "build/Export/iPhoneLocationMove.app"
    assert_log_empty

    : > "$COMMAND_LOG"
    run_package -h
    assert_success
    assert_output_contains "--no-dmg"
    assert_log_empty

    for invalid_arguments in "--version" "--version 1..2" "--version 1.beta" "--unknown"; do
        : > "$COMMAND_LOG"
        set -- $invalid_arguments
        run_package "$@"
        assert_failure
        assert_log_empty
    done
}

test_marker_fail_before_clean() {
    setup_case missing_project
    mkdir -p "$FIXTURE_PROJECT/build"
    printf 'keep\n' > "$FIXTURE_PROJECT/build/sentinel"
    rm -f "$FIXTURE_PROJECT/iPhoneLocationMove.xcodeproj/project.pbxproj"
    run_package
    assert_failure
    assert_file_exists "$FIXTURE_PROJECT/build/sentinel"
    assert_log_empty

    setup_case missing_scheme
    mkdir -p "$FIXTURE_PROJECT/build"
    printf 'keep\n' > "$FIXTURE_PROJECT/build/sentinel"
    rm -f "$FIXTURE_PROJECT/iPhoneLocationMove.xcodeproj/xcshareddata/xcschemes/iPhoneLocationMove.xcscheme"
    run_package
    assert_failure
    assert_file_exists "$FIXTURE_PROJECT/build/sentinel"
    assert_log_empty
}

test_default_pipeline() {
    setup_case default
    run_package
    assert_success
    assert_pipeline_order
    assert_file_exists "$FIXTURE_PROJECT/build/Export/iPhoneLocationMove.app"
    assert_file_exists "$FIXTURE_PROJECT/build/iPhoneLocationMove.dmg"
    assert_log_contains "codesign <--verify>"
    assert_log_contains "lipo"
    assert_log_contains "otool <-X> <-s> <__TEXT> <__info_plist>"
    assert_log_contains "hdiutil <create>"
    assert_output_contains "打包完成"
    assert_output_excludes "XCODEBUILD_VERBOSE_DETAIL"
    assert_output_excludes "PYTHON_VERBOSE_DETAIL"
    assert_file_contains "$FIXTURE_PROJECT/build/Logs/xcode-clean.log" "XCODEBUILD_VERBOSE_DETAIL"
    assert_file_contains "$FIXTURE_PROJECT/build/Logs/xcode-tests.log" "XCODEBUILD_VERBOSE_DETAIL"
    assert_file_contains "$FIXTURE_PROJECT/build/Logs/python-tests.log" "PYTHON_VERBOSE_DETAIL"
    assert_file_contains "$FIXTURE_PROJECT/build/Logs/xcode-build.log" "XCODEBUILD_VERBOSE_DETAIL"
    assert_no_temporary_directories
}

test_flags_and_version() {
    setup_case no_clean
    mkdir -p "$FIXTURE_PROJECT/build"
    printf 'keep\n' > "$FIXTURE_PROJECT/build/sentinel"
    run_package --no-clean --skip-tests --no-dmg
    assert_success
    assert_file_exists "$FIXTURE_PROJECT/build/sentinel"
    assert_log_excludes "xcodebuild <clean>"
    assert_log_excludes "xcodebuild <test>"
    assert_log_excludes "python3"
    assert_log_excludes "hdiutil"
    assert_output_contains "跳過測試"
    assert_output_excludes "[DMG]"

    setup_case version
    run_package -v 1.2.3
    assert_success
    assert_log_contains "MARKETING_VERSION=1.2.3"
    assert_file_exists "$FIXTURE_PROJECT/build/iPhoneLocationMove-1.2.3.dmg"
    assert_output_contains "1.2.3"

    setup_case long_version
    run_package --version 1.2.3
    assert_success
    assert_log_contains "MARKETING_VERSION=1.2.3"
    assert_file_exists "$FIXTURE_PROJECT/build/iPhoneLocationMove-1.2.3.dmg"
    assert_output_contains "1.2.3"

    setup_case exact_dmg_replacement
    mkdir -p "$FIXTURE_PROJECT/build"
    printf 'keep adjacent dmg\n' > "$FIXTURE_PROJECT/build/iPhoneLocationMove-other.dmg"
    printf 'replace target\n' > "$FIXTURE_PROJECT/build/iPhoneLocationMove.dmg"
    run_package --no-clean --skip-tests
    assert_success
    assert_file_exists "$FIXTURE_PROJECT/build/iPhoneLocationMove-other.dmg"
    if grep -Fq 'keep adjacent dmg' "$FIXTURE_PROJECT/build/iPhoneLocationMove-other.dmg"; then
        record_pass
    else
        record_failure "adjacent DMG was modified"
    fi
    if grep -Fq 'fake dmg' "$FIXTURE_PROJECT/build/iPhoneLocationMove.dmg"; then
        record_pass
    else
        record_failure "target DMG was not replaced"
    fi
}

assert_failure_before_build() {
    assert_failure
    assert_log_excludes "xcodebuild <build>"
    assert_log_excludes "hdiutil"
    assert_output_excludes "打包完成"
}

assert_failure_before_dmg() {
    assert_failure
    assert_log_excludes "hdiutil"
    assert_output_excludes "打包完成"
    assert_no_temporary_directories
}

test_test_and_build_failures() {
    setup_case xcode_test_failure
    export FAKE_XCODE_TEST_STATUS=42
    run_package
    assert_failure_before_build
    assert_output_contains "build/Logs/xcode-tests.log"
    assert_output_contains "XCODEBUILD_VERBOSE_DETAIL"

    setup_case python_test_failure
    export FAKE_PYTHON_STATUS=43
    run_package
    assert_failure_before_build
    assert_output_contains "build/Logs/python-tests.log"
    assert_output_contains "PYTHON_VERBOSE_DETAIL"

    setup_case build_failure
    export FAKE_XCODE_BUILD_STATUS=44
    run_package
    assert_failure
    assert_log_excludes "codesign"
    assert_log_excludes "hdiutil"
    assert_output_excludes "打包完成"
}

test_artifact_and_signature_failures() {
    setup_case missing_app
    export FAKE_OMIT_APP=1
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case missing_helper
    export FAKE_OMIT_HELPER=1
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case metadata_extraction
    export FAKE_OTOOL_STATUS=45
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case architecture_extraction
    export FAKE_LIPO_STATUS=49
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case app_signature
    export FAKE_APP_VERIFY_STATUS=46
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case helper_signature
    export FAKE_HELPER_VERIFY_STATUS=47
    run_package --skip-tests
    assert_failure_before_dmg
}

test_identity_and_requirement_failures() {
    setup_case wrong_team
    export FAKE_APP_TEAM="WRONGTEAM"
    export FAKE_HELPER_TEAM="WRONGTEAM"
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case app_identifier
    export FAKE_APP_IDENTIFIER="com.example.WrongApp"
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case helper_identifier
    export FAKE_HELPER_IDENTIFIER="com.example.WrongHelper"
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case app_requirement
    export FAKE_APP_REQUIREMENT="identifier \"wrong.helper\" and anchor apple generic and certificate leaf[subject.OU] = \"2LRM76M575\""
    run_package --skip-tests
    assert_failure_before_dmg

    setup_case embedded_requirement
    assert_file_exists "$FIXTURE_PROJECT/iPhoneLocationMoveTunnelHelper/HelperInfo.plist"
    export FAKE_HELPER_REQUIREMENT="identifier \"wrong.app\" and anchor apple generic and certificate leaf[subject.OU] = \"2LRM76M575\""
    run_package --skip-tests
    assert_failure_before_dmg
}

test_version_and_dmg_failures() {
    setup_case version_metadata
    export FAKE_BUNDLE_VERSION="9.9.9"
    run_package --skip-tests --version 1.2.3
    assert_failure_before_dmg

    setup_case dmg_failure
    export FAKE_HDIUTIL_STATUS=48
    run_package --skip-tests
    assert_failure
    assert_log_contains "hdiutil <create>"
    assert_output_excludes "打包完成"
    assert_no_temporary_directories
}

REPOSITORY_BUILD_STATE="$(repository_build_state)"

test_help_and_invalid_arguments
test_marker_fail_before_clean
test_default_pipeline
test_flags_and_version
test_test_and_build_failures
test_artifact_and_signature_failures
test_identity_and_requirement_failures
test_version_and_dmg_failures

cleanup_case

if [ "$(repository_build_state)" = "$REPOSITORY_BUILD_STATE" ]; then
    record_pass
else
    record_failure "repository build directory changed during fixture tests"
fi

echo "package-app tests: $PASS_COUNT passed, $FAIL_COUNT failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
    exit 1
fi

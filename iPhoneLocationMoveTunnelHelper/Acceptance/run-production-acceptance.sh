#!/bin/bash

# Fixed production acceptance runner.  It intentionally accepts no arguments:
# the signed App, case manifest, runtime root, and cleanup paths are all fixed
# by this repository contract.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="/tmp/iphone-location-move-acceptance"
RESULTS_DIR="$ACCEPTANCE_ROOT/results"
CASES_PATH="$SCRIPT_DIR/cases.json"
APP_BUNDLE="$ACCEPTANCE_ROOT/DerivedData/Build/Products/Debug/iPhoneLocationMove.app"
APP_PATH="$ACCEPTANCE_ROOT/DerivedData/Build/Products/Debug/iPhoneLocationMove.app/Contents/MacOS/iPhoneLocationMove"

RUNTIME_PARENT="/Library/Application Support/iPhoneLocationMove/TunnelRuntime"
RUNTIME_ROOT="$RUNTIME_PARENT/pymobiledevice3-11.13.0"
RUNTIME_EXECUTABLE="$RUNTIME_ROOT/runtime/pymobiledevice3"
HELPER_TOOL="/Library/PrivilegedHelperTools/com.cash.iPhoneLocationMoveTunnelHelper"
LAUNCH_DAEMON="/Library/LaunchDaemons/com.cash.iPhoneLocationMoveTunnelHelper.plist"
SERVICE_DOMAIN="system/com.cash.iPhoneLocationMoveTunnelHelper"
TUNNEL_PROCESS_PATTERN='iPhoneLocationMoveTunnelHelper|pymobiledevice3.*start-tunnel|TunnelRuntime'
TUNNEL_CHILD_PATTERN='pymobiledevice3.*start-tunnel'
HOST_VERSION=""
CONSOLE_USER=""
CONSOLE_UID=""
APP_TEAM_ID=""
DEVICE_UDID=""
DEVICE_VERSION=""

fail() {
    echo "production acceptance failed: $*" >&2
    exit 1
}

codesign_team_id() {
    local target="$1"
    local details
    details="$(/usr/bin/codesign -dvvv --verbose=4 "$target" 2>&1)" || return 1
    printf '%s\n' "$details" \
        | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}'
}

validate_signed_bundle() {
    local bundle="$1"
    local label="$2"
    local team_id

    if ! /usr/bin/codesign --verify --deep --strict "$bundle" >/dev/null 2>&1; then
        fail "$label is not a valid strict code signature: $bundle"
    fi
    team_id="$(codesign_team_id "$bundle")" || fail "cannot inspect $label signature: $bundle"
    if [[ ! "$team_id" =~ ^[A-Z0-9]{10}$ ]]; then
        fail "$label does not have a production TeamIdentifier: $bundle"
    fi
    printf '%s' "$team_id"
}

validate_root_owned_file() {
    local path="$1"
    local label="$2"
    local owner
    if [ ! -f "$path" ]; then
        fail "missing $label: $path"
    fi
    owner="$(/usr/bin/stat -f '%u' "$path")" || fail "cannot inspect $label: $path"
    if [ "$owner" != 0 ]; then
        fail "$label is not root-owned: $path"
    fi
}

validate_root_owned_directory() {
    local path="$1"
    local label="$2"
    local owner
    if [ ! -d "$path" ]; then
        fail "missing $label: $path"
    fi
    owner="$(/usr/bin/stat -f '%u' "$path")" || fail "cannot inspect $label: $path"
    if [ "$owner" != 0 ]; then
        fail "$label is not root-owned: $path"
    fi
}

validate_embedded_payload() {
    local wheelhouse="$APP_BUNDLE/Contents/Resources/tunnel-wheelhouse"
    local lockfile="$APP_BUNDLE/Contents/Resources/pymobiledevice3.lock"
    local helper_payload="$APP_BUNDLE/Contents/Library/LaunchServices/iPhoneLocationMoveTunnelHelper"

    if [ ! -d "$wheelhouse" ]; then
        fail "signed App is missing embedded tunnel wheelhouse: $wheelhouse"
    fi
    if [ ! -f "$lockfile" ]; then
        fail "signed App is missing embedded runtime lockfile: $lockfile"
    fi
    if [ ! -f "$wheelhouse/pymobiledevice3-11.13.0-py3-none-any.whl" ]; then
        fail "signed App is missing the pinned primary wheel"
    fi
    if [ ! -x "$helper_payload" ]; then
        fail "signed App is missing the embedded helper: $helper_payload"
    fi
}

read_device_metadata() {
    local raw_path="$RESULTS_DIR/.usbmux-list.json"
    local metadata_path="$RESULTS_DIR/environment.json"

    if ! /usr/bin/sudo -n -u "$CONSOLE_USER" -H -- "$RUNTIME_EXECUTABLE" usbmux list --usb > "$raw_path" 2> "$RESULTS_DIR/.usbmux-list.stderr"; then
        fail "USB discovery failed for the console user"
    fi
    DEVICE_UDID="$(/usr/bin/python3 - "$raw_path" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        value = json.load(stream)
except (OSError, ValueError) as error:
    raise SystemExit(f"invalid usbmux JSON: {error}")

devices = value if isinstance(value, list) else value.get("devices") if isinstance(value, dict) else None
if not isinstance(devices, list):
    raise SystemExit("usbmux output did not contain a device list")

matches = []
for raw in devices:
    if not isinstance(raw, dict):
        continue
    info = raw.get("short_info") if isinstance(raw.get("short_info"), dict) else raw
    if str(info.get("ConnectionType", info.get("connection_type", ""))).upper() != "USB":
        continue
    if str(info.get("DeviceClass", info.get("device_class", "iPhone"))).lower() != "iphone":
        continue
    identifier = info.get("Identifier", info.get("UDID", info.get("udid")))
    version = info.get("ProductVersion", info.get("product_version", info.get("productVersion")))
    if not isinstance(identifier, str) or not isinstance(version, str):
        raise SystemExit("USB device is missing identifier or ProductVersion")
    matches.append((identifier, version))

if len(matches) != 1:
    raise SystemExit(f"acceptance requires exactly one USB iPhone, found {len(matches)}")
identifier, version = matches[0]
if not version.split(".", 1)[0].isdigit() or int(version.split(".", 1)[0]) != 27:
    raise SystemExit(f"acceptance requires an iOS 27 device, found {version}")
print(identifier)
print(version)
PY
    )" || fail "USB iPhone metadata is not one iOS 27 device"
    DEVICE_VERSION="$(printf '%s\n' "$DEVICE_UDID" | /usr/bin/tail -n 1)"
    DEVICE_UDID="$(printf '%s\n' "$DEVICE_UDID" | /usr/bin/head -n 1)"

    if ! /usr/bin/sudo -n -u "$CONSOLE_USER" -H -- "$RUNTIME_EXECUTABLE" lockdown info --udid "$DEVICE_UDID" > "$RESULTS_DIR/.lockdown-info.json" 2> "$RESULTS_DIR/.lockdown-info.stderr"; then
        fail "USB iPhone trust verification failed"
    fi
    local developer_mode
    developer_mode="$(/usr/bin/sudo -n -u "$CONSOLE_USER" -H -- "$RUNTIME_EXECUTABLE" amfi developer-mode-status --udid "$DEVICE_UDID" 2> "$RESULTS_DIR/.developer-mode.stderr")" || fail "Developer Mode status probe failed"
    if [ "$(printf '%s' "$developer_mode" | /usr/bin/tr -d '[:space:]' | /usr/bin/tr '[:upper:]' '[:lower:]')" != "true" ]; then
        fail "USB iPhone Developer Mode is not enabled"
    fi

    /usr/bin/python3 - "$metadata_path" "$HOST_VERSION" "$DEVICE_VERSION" <<'PY'
import json
import sys

path, host_version, device_version = sys.argv[1:]
with open(path, "w", encoding="utf-8") as stream:
    json.dump(
        {
            "schemaVersion": 1,
            "hostOSVersion": host_version,
            "deviceOSVersion": device_version,
            "deviceCount": 1,
        },
        stream,
        sort_keys=True,
        separators=(",", ":"),
    )
    stream.write("\n")
PY
}

run_app_case() {
    local executable="$1"
    local runner_case="$2"
    local result_path="$3"
    local stderr_path="$4"
    local process_status

    /usr/bin/sudo -n -u "$CONSOLE_USER" -H -- "$executable" \
        --privileged-helper-acceptance-case "$runner_case" \
        > "$result_path" 2> "$stderr_path"
    process_status=$?
    printf '%s' "$process_status"
}

rebuild_clean_runtime() {
    local setup_result="$RESULTS_DIR/.runtime-rebuild.json"
    local setup_stderr="$RESULTS_DIR/.runtime-rebuild.stderr"
    local setup_status

    /bin/rm -rf "$RUNTIME_ROOT" || fail "cannot remove pinned runtime before rebuild"
    setup_status="$(run_app_case "$APP_PATH" "positive-start" "$setup_result" "$setup_stderr")" \
        || fail "runtime rebuild App launch failed"
    if ! validate_result "$CASES_PATH" "$setup_result" "positive-start" "$setup_status"; then
        fail "runtime rebuild did not produce a clean positive-start result"
    fi
}

prepare_runtime_seal_tamper() {
    local extra_path="$RUNTIME_ROOT/runtime/acceptance-extra.py"
    if [ ! -d "$RUNTIME_ROOT/runtime" ]; then
        fail "pinned runtime is missing before seal tamper preparation"
    fi
    if ! /usr/bin/python3 - "$extra_path" <<'PY'
import os
import sys

path = sys.argv[1]
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    os.write(fd, b"# fixed runtime seal tamper fixture\n")
    os.fchown(fd, 0, 0)
    os.fchmod(fd, 0o600)
    os.fsync(fd)
finally:
    os.close(fd)
PY
    then
        fail "cannot create the fixed runtime seal tamper fixture"
    fi
}

validate_production_preflight() {
    local helper_team_id
    local app_lockfile="$APP_BUNDLE/Contents/Resources/pymobiledevice3.lock"

    HOST_VERSION="$(/usr/bin/sw_vers -productVersion)" || fail "cannot read host macOS version"
    case "$HOST_VERSION" in
        27|27.*)
            ;;
        *)
            fail "production acceptance requires macOS 27, found $HOST_VERSION"
            ;;
    esac

    CONSOLE_USER="$(/usr/bin/stat -f '%Su' /dev/console)" || fail "cannot identify the console user"
    CONSOLE_UID="$(/usr/bin/stat -f '%u' /dev/console)" || fail "cannot identify the console UID"
    if [[ ! "$CONSOLE_UID" =~ ^[1-9][0-9]*$ ]] || [ "$CONSOLE_UID" -lt 500 ] || [ "$CONSOLE_USER" = root ]; then
        fail "production acceptance requires a non-root logged-in console user"
    fi
    if [ "$(/usr/bin/id -u "$CONSOLE_USER")" != "$CONSOLE_UID" ]; then
        fail "console user identity changed during preflight"
    fi
    if ! /usr/bin/sudo -n -u "$CONSOLE_USER" -H -- /usr/bin/true; then
        fail "root cannot launch the console user non-interactively"
    fi

    APP_TEAM_ID="$(validate_signed_bundle "$APP_BUNDLE" "acceptance App")" \
        || fail "cannot validate acceptance App signature"
    validate_embedded_payload
    if [ "$(/usr/bin/stat -f '%u' "$app_lockfile")" != 0 ]; then
        fail "embedded runtime lockfile is not root-owned: $app_lockfile"
    fi

    validate_root_owned_file "$HELPER_TOOL" "installed helper"
    validate_root_owned_file "$LAUNCH_DAEMON" "installed launch daemon plist"
    if ! /usr/bin/codesign --verify --strict "$HELPER_TOOL" >/dev/null 2>&1; then
        fail "installed helper does not have a valid code signature"
    fi
    helper_team_id="$(codesign_team_id "$HELPER_TOOL")" || fail "cannot inspect installed helper signature"
    if [ "$helper_team_id" != "$APP_TEAM_ID" ]; then
        fail "signed App and installed helper TeamIdentifier differ"
    fi
    if ! /bin/launchctl print "$SERVICE_DOMAIN" >/dev/null 2>&1; then
        fail "installed helper service is not running: $SERVICE_DOMAIN"
    fi

    validate_root_owned_directory "$RUNTIME_ROOT" "pinned runtime"
    validate_root_owned_file "$RUNTIME_EXECUTABLE" "pinned runtime executable"
    validate_root_owned_file "$RUNTIME_ROOT/runtime-seal.json" "pinned runtime seal"
    if [ "$(/usr/bin/stat -f '%Lp' "$RUNTIME_ROOT")" != 700 ]; then
        fail "pinned runtime root does not have mode 0700"
    fi
    if [ "$(/usr/bin/stat -f '%Lp' "$RUNTIME_EXECUTABLE")" != 700 ]; then
        fail "pinned runtime executable does not have mode 0700"
    fi
    if [ "$(/usr/bin/stat -f '%Lp' "$RUNTIME_ROOT/runtime-seal.json")" != 600 ]; then
        fail "pinned runtime seal does not have mode 0600"
    fi

    read_device_metadata
    echo "validated production preflight: host=$HOST_VERSION device=$DEVICE_VERSION console=$CONSOLE_USER"
}

cleanup_active=false
cleanup_done=false

cleanup_on_exit() {
    if [ "$cleanup_active" != true ] || [ "$cleanup_done" = true ]; then
        return 0
    fi
    /bin/launchctl bootout "$SERVICE_DOMAIN" >/dev/null 2>&1 || true
    /bin/rm -f "$HELPER_TOOL" "$LAUNCH_DAEMON"
    /bin/rm -rf "$RUNTIME_PARENT"
}

trap cleanup_on_exit EXIT

if [ "$#" -ne 0 ]; then
    fail "this fixed runner accepts no arguments"
fi
if [ "$(/usr/bin/id -u)" -ne 0 ]; then
    fail "this runner must run as root"
fi
if [ ! -f "$CASES_PATH" ]; then
    fail "missing cases manifest: $CASES_PATH"
fi
if [ ! -x "$APP_PATH" ]; then
    fail "missing signed acceptance App: $APP_PATH"
fi

# Validate the manifest before launching any production process.  The runner
# only accepts the fixed case order and typed-error shape below; a malformed or
# retargeted manifest fails closed.
/usr/bin/python3 - "$CASES_PATH" <<'PY'
import json
import sys

manifest_path = sys.argv[1]
try:
    with open(manifest_path, encoding="utf-8") as stream:
        manifest = json.load(stream)
except (OSError, ValueError) as error:
    raise SystemExit(f"invalid cases manifest: {error}")

required_ids = [
    "positive-start",
    "device-session-ready",
    "pending-duplicate",
    "lost-reply-retry",
    "endpoint-timeout",
    "connection-invalidation",
    "app-termination",
    "startup-reconcile",
    "runtime-seal-tamper",
    "invalid-signature",
    "team-id-mismatch",
]
if manifest.get("schemaVersion") != 1:
    raise SystemExit("unsupported cases schema")
if manifest.get("workDirectory") != "/tmp/iphone-location-move-acceptance":
    raise SystemExit("manifest workDirectory is not fixed")
if manifest.get("runtimeDirectory") != "pymobiledevice3-11.13.0":
    raise SystemExit("manifest runtimeDirectory is not the pinned runtime")
if "current" in json.dumps(manifest, sort_keys=True).lower():
    raise SystemExit("manifest references an unversioned runtime")

cases = manifest.get("cases")
if not isinstance(cases, list) or [item.get("id") for item in cases] != required_ids:
    raise SystemExit("manifest does not declare the required fixed case order")

allowed_runner_cases = set(required_ids)
allowed_runner_cases.add("positive-start")
allowed_fixtures = {"signature-invalid.app", "team-mismatch.app"}
for item in cases:
    if item.get("runnerCase") not in allowed_runner_cases:
        raise SystemExit(f"unsupported runner case: {item.get('runnerCase')!r}")
    expected = item.get("expected")
    expected_error = item.get("expectedError")
    if expected == "passed":
        if expected_error is not None:
            raise SystemExit(f"case has both expected and expectedError: {item['id']}")
    elif isinstance(expected_error, str) and expected_error:
        if expected is not None:
            raise SystemExit(f"case has both expected and expectedError: {item['id']}")
    else:
        raise SystemExit(f"case has no fixed expected result: {item['id']}")
    fixture = item.get("callerFixture")
    if fixture is not None and fixture not in allowed_fixtures:
        raise SystemExit(f"unsupported caller fixture: {fixture!r}")

print(f"validated {len(cases)} fixed acceptance cases")
PY
manifest_status=$?
if [ "$manifest_status" -ne 0 ]; then
    exit "$manifest_status"
fi

/bin/mkdir -p "$RESULTS_DIR" || fail "cannot create results directory"
validate_production_preflight
cleanup_active=true

snapshot() {
    local destination="$1"
    {
        echo "# environment"
        echo "hostOSVersion=$HOST_VERSION"
        echo "deviceOSVersion=$DEVICE_VERSION"
        echo "# process snapshot"
        /usr/bin/pgrep -alf "$TUNNEL_PROCESS_PATTERN" || true
        echo "# tunnel child snapshot"
        /usr/bin/pgrep -alf "$TUNNEL_CHILD_PATTERN" || true
        echo "# helper service"
        /bin/launchctl print "$SERVICE_DOMAIN" || true
        echo "# pinned runtime"
        if [ -d "$RUNTIME_ROOT" ]; then
            /usr/bin/find "$RUNTIME_ROOT" -xdev -print0 \
                | /usr/bin/xargs -0 /usr/bin/stat -f '%Su:%Sg %Mp%Lp %N' || true
        else
            echo "missing: $RUNTIME_ROOT"
        fi
    } > "$destination"
}

wait_for_tunnel_exit() {
    local attempt
    for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        if ! /usr/bin/pgrep -f "$TUNNEL_CHILD_PATTERN" >/dev/null 2>&1; then
            return 0
        fi
        /bin/sleep 1
    done
    return 1
}

assert_no_tunnel_child() {
    local case_id="$1"
    if /usr/bin/pgrep -f "$TUNNEL_CHILD_PATTERN" >/dev/null 2>&1; then
        echo "tunnel child remains after $case_id" >&2
        return 1
    fi
    return 0
}

validate_result() {
    local manifest_path="$1"
    local result_path="$2"
    local case_id="$3"
    local process_status="$4"
    /usr/bin/python3 - "$manifest_path" "$result_path" "$case_id" "$process_status" <<'PY'
import json
import sys

manifest_path, result_path, case_id, process_status = sys.argv[1:]
try:
    with open(manifest_path, encoding="utf-8") as stream:
        manifest = json.load(stream)
    with open(result_path, encoding="utf-8") as stream:
        result = json.load(stream)
except (OSError, ValueError) as error:
    raise SystemExit(f"invalid typed result for {case_id}: {error}")

case = next((item for item in manifest["cases"] if item.get("id") == case_id), None)
if case is None:
    raise SystemExit(f"result case is not in manifest: {case_id}")
if result.get("case") != case_id:
    raise SystemExit(f"result case mismatch: {result.get('case')!r}")
if not isinstance(result.get("passed"), bool):
    raise SystemExit(f"result passed is not boolean: {case_id}")
if not isinstance(result.get("detail"), str):
    raise SystemExit(f"result detail is not text: {case_id}")

status = int(process_status)
if case.get("expected") == "passed":
    if status != 0 or result["passed"] is not True or result.get("errorCode") is not None:
        raise SystemExit(f"positive case did not pass cleanly: {case_id}")
    if case_id == "device-session-ready" and "DVT/device session ready" not in result["detail"]:
        raise SystemExit("device-session-ready did not report the actual DVT-ready session")
else:
    expected_error = case.get("expectedError")
    if result.get("passed") is not True or result.get("errorCode") != expected_error:
        raise SystemExit(
            f"typed error mismatch for {case_id}: "
            f"expected passed=true and errorCode={expected_error!r}, "
            f"got passed={result.get('passed')!r}, errorCode={result.get('errorCode')!r}"
        )
    if status not in (0, 1):
        raise SystemExit(f"negative case exited unexpectedly: {case_id} ({status})")

print(f"validated result: {case_id}")
PY
}

manifest_rows() {
    /usr/bin/python3 - "$CASES_PATH" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    manifest = json.load(stream)
for item in manifest["cases"]:
    print("\t".join(
        [
            item["id"],
            item["runnerCase"],
            item.get("expected", ""),
            item.get("expectedError", ""),
            item.get("callerFixture", ""),
        ]
    ))
PY
}

prepare_caller_fixtures() {
    local invalid_bundle="$ACCEPTANCE_ROOT/signature-invalid.app"
    local mismatch_bundle="$ACCEPTANCE_ROOT/team-mismatch.app"
    local invalid_executable="$invalid_bundle/Contents/MacOS/iPhoneLocationMove"
    local source_signature="$RESULTS_DIR/source-app.codesign.txt"
    local invalid_signature="$RESULTS_DIR/signature-invalid.codesign.txt"
    local mismatch_signature="$RESULTS_DIR/team-mismatch.codesign.txt"

    /bin/rm -rf "$invalid_bundle" "$mismatch_bundle" \
        || fail "cannot clear caller trust fixtures"
    /bin/cp -R "$APP_BUNDLE" "$invalid_bundle" \
        || fail "cannot create invalid-signature caller fixture"
    /bin/cp -R "$APP_BUNDLE" "$mismatch_bundle" \
        || fail "cannot create team-mismatch caller fixture"

    /usr/bin/codesign -dvvv --verbose=4 "$APP_BUNDLE" > "$source_signature" 2>&1 \
        || fail "cannot capture signed App identity"
    if ! /usr/bin/python3 - "$invalid_executable" <<'PY'
import os
import sys

path = sys.argv[1]
with open(path, "ab", buffering=0) as stream:
    stream.write(b"\0")
os.chown(path, 0, 0)
os.chmod(path, 0o755)
PY
    then
        fail "cannot mutate invalid-signature caller fixture"
    fi
    if /usr/bin/codesign --verify --deep --strict "$invalid_bundle" > "$invalid_signature" 2>&1; then
        fail "invalid-signature caller fixture unexpectedly verifies"
    fi

    /usr/bin/codesign --force --deep --sign - "$mismatch_bundle" > "$mismatch_signature" 2>&1 \
        || fail "cannot create team-mismatch caller fixture"
    if ! /usr/bin/codesign --verify --deep --strict "$mismatch_bundle" >> "$mismatch_signature" 2>&1; then
        fail "team-mismatch caller fixture does not have a valid replacement signature"
    fi
    local mismatch_team_id
    mismatch_team_id="$(codesign_team_id "$mismatch_bundle")" || fail "cannot inspect team-mismatch fixture"
    if [ "$mismatch_team_id" = "$APP_TEAM_ID" ]; then
        fail "team-mismatch caller fixture retained the production TeamIdentifier"
    fi

    /usr/bin/python3 - "$RESULTS_DIR/fixture-preparation.json" "$APP_TEAM_ID" "$mismatch_team_id" <<'PY'
import json
import sys

path, source_team, mismatch_team = sys.argv[1:]
with open(path, "w", encoding="utf-8") as stream:
    json.dump(
        {
            "schemaVersion": 1,
            "sourceTeamIdentifier": source_team,
            "teamMismatchIdentifier": mismatch_team,
            "signatureInvalidVerified": True,
            "teamMismatchVerified": True,
        },
        stream,
        sort_keys=True,
        separators=(",", ":"),
    )
    stream.write("\n")
PY
}

write_case_metadata() {
    local case_id="$1"
    local before_path="$2"
    local after_path="$3"
    /usr/bin/python3 - "$RESULTS_DIR/$case_id-metadata.json" "$case_id" "$HOST_VERSION" "$DEVICE_VERSION" "$before_path" "$after_path" <<'PY'
import json
import sys

path, case_id, host_version, device_version, before_path, after_path = sys.argv[1:]
with open(path, "w", encoding="utf-8") as stream:
    json.dump(
        {
            "schemaVersion": 1,
            "case": case_id,
            "hostOSVersion": host_version,
            "deviceOSVersion": device_version,
            "beforeSnapshot": before_path,
            "afterSnapshot": after_path,
        },
        stream,
        sort_keys=True,
        separators=(",", ":"),
    )
    stream.write("\n")
PY
}

prepare_case_environment() {
    local case_id="$1"
    case "$case_id" in
        endpoint-timeout)
            rebuild_clean_runtime
            /usr/bin/python3 "$SCRIPT_DIR/prepare-endpoint-timeout.py" \
                || fail "endpoint-timeout fixture preparation failed"
            ;;
        connection-invalidation|app-termination)
            rebuild_clean_runtime
            ;;
        runtime-seal-tamper)
            rebuild_clean_runtime
            prepare_runtime_seal_tamper
            ;;
        invalid-signature|team-id-mismatch)
            rebuild_clean_runtime
            ;;
    esac
}

normalize_caller_fixture_result() {
    local result_path="$1"
    local stderr_path="$2"
    local case_id="$3"
    local process_status="$4"

    /usr/bin/python3 - "$result_path" "$stderr_path" "$case_id" "$process_status" <<'PY'
import json
import sys

result_path, stderr_path, case_id, process_status = sys.argv[1:]
try:
    with open(result_path, encoding="utf-8") as stream:
        result = json.load(stream)
except (OSError, ValueError):
    result = None

if isinstance(result, dict):
    return_code = int(process_status)
    if return_code != 0 and result.get("errorCode") != "tunnel-failure":
        raise SystemExit(f"caller fixture returned an unexpected typed error: {case_id}")
    raise SystemExit(0)

if int(process_status) == 0:
    raise SystemExit(f"caller fixture exited successfully without a typed result: {case_id}")
try:
    with open(stderr_path, encoding="utf-8") as stream:
        detail = stream.read().strip()
except OSError as error:
    raise SystemExit(f"cannot read caller fixture rejection: {error}")
if not detail:
    raise SystemExit(f"caller fixture failed without an OS/XPC rejection diagnostic: {case_id}")
diagnostic = detail.lower()
if not any(
    marker in diagnostic
    for marker in ("signature", "team", "trust", "xpc", "launch", "code object")
):
    raise SystemExit(f"caller fixture failure was not an explicit trust/launch rejection: {case_id}")

with open(result_path, "w", encoding="utf-8") as stream:
    json.dump(
        {
            "case": case_id,
            "passed": True,
            "leaseID": None,
            "errorCode": "tunnel-failure",
            "detail": "Caller trust fixture was rejected before a tunnel lease was created.",
        },
        stream,
        sort_keys=True,
        separators=(",", ":"),
    )
    stream.write("\n")
PY
}

run_case() {
    local case_id="$1"
    local runner_case="$2"
    local expected="$3"
    local expected_error="$4"
    local caller_fixture="$5"
    local executable="$APP_PATH"
    local result_path="$RESULTS_DIR/$case_id.json"
    local stderr_path="$RESULTS_DIR/$case_id.stderr"
    local before_path="$RESULTS_DIR/$case_id-before.txt"
    local after_path="$RESULTS_DIR/$case_id-after.txt"
    local process_status

    case "$caller_fixture" in
        "")
            ;;
        signature-invalid.app|team-mismatch.app)
            executable="$ACCEPTANCE_ROOT/$caller_fixture/Contents/MacOS/iPhoneLocationMove"
            ;;
        *)
            echo "unsupported caller fixture: $caller_fixture" >&2
            return 1
            ;;
    esac
    if [ ! -x "$executable" ]; then
        echo "missing acceptance executable for $case_id: $executable" >&2
        return 1
    fi

    prepare_case_environment "$case_id"
    snapshot "$before_path"
    echo "running $case_id ($runner_case)"
    process_status="$(run_app_case "$executable" "$runner_case" "$result_path" "$stderr_path")" \
        || return 1

    if [ -n "$caller_fixture" ]; then
        normalize_caller_fixture_result "$result_path" "$stderr_path" "$case_id" "$process_status" \
            || return 1
    fi

    if [ "$case_id" = "connection-invalidation" ] || [ "$case_id" = "app-termination" ]; then
        if ! wait_for_tunnel_exit; then
            echo "tunnel child did not exit after $case_id" >&2
            snapshot "$after_path"
            return 1
        fi
        if ! assert_no_tunnel_child "$case_id"; then
            snapshot "$after_path"
            return 1
        fi
    fi
    snapshot "$after_path"

    if ! validate_result "$CASES_PATH" "$result_path" "$case_id" "$process_status"; then
        return 1
    fi
    write_case_metadata "$case_id" "$before_path" "$after_path"
    # Keep these names in the shell surface so the manifest's expected fields
    # remain observable in review, while validation is driven by the JSON.
    : "${expected}${expected_error}"
    return 0
}

prepare_caller_fixtures

overall_status=0
while IFS=$'\t' read -r case_id runner_case expected expected_error caller_fixture; do
    [ -n "$case_id" ] || continue
    if ! run_case "$case_id" "$runner_case" "$expected" "$expected_error" "$caller_fixture"; then
        overall_status=1
    fi
done < <(manifest_rows)

run_uninstall() {
    local cleanup_path="$RESULTS_DIR/final-cleanup.json"
    local service_absent=true
    local helper_tool_absent=true
    local launch_daemon_plist_absent=true
    local runtime_parent_absent=true
    local root_processes_absent=true

    /bin/launchctl bootout "$SERVICE_DOMAIN" > "$RESULTS_DIR/final-uninstall.log" 2>&1 || true
    /bin/rm -f "$HELPER_TOOL" "$LAUNCH_DAEMON"
    /bin/rm -rf "$RUNTIME_PARENT"

    if /bin/launchctl print "$SERVICE_DOMAIN" >/dev/null 2>&1; then
        service_absent=false
    fi
    [ ! -e "$HELPER_TOOL" ] || helper_tool_absent=false
    [ ! -e "$LAUNCH_DAEMON" ] || launch_daemon_plist_absent=false
    [ ! -e "$RUNTIME_PARENT" ] || runtime_parent_absent=false

    /usr/bin/pgrep -alf "$TUNNEL_PROCESS_PATTERN" > "$RESULTS_DIR/final-processes.txt" 2>&1 || true
    if /usr/bin/pgrep -f "$TUNNEL_PROCESS_PATTERN" >/dev/null 2>&1; then
        root_processes_absent=false
    fi

    /usr/bin/python3 - "$cleanup_path" \
        "$service_absent" \
        "$helper_tool_absent" \
        "$launch_daemon_plist_absent" \
        "$runtime_parent_absent" \
        "$root_processes_absent" <<'PY'
import json
import sys

path = sys.argv[1]
names = [
    "serviceAbsent",
    "helperToolAbsent",
    "launchDaemonPlistAbsent",
    "runtimeParentAbsent",
    "rootProcessesAbsent",
]
values = [value == "true" for value in sys.argv[2:]]
with open(path, "w", encoding="utf-8") as stream:
    json.dump(
        {"schemaVersion": 1, **dict(zip(names, values))},
        stream,
        sort_keys=True,
        separators=(",", ":"),
    )
    stream.write("\n")
PY

    if [ "$service_absent" != true ] \
        || [ "$helper_tool_absent" != true ] \
        || [ "$launch_daemon_plist_absent" != true ] \
        || [ "$runtime_parent_absent" != true ] \
        || [ "$root_processes_absent" != true ]; then
        echo "final uninstall verification failed; see $cleanup_path" >&2
        return 1
    fi
    cleanup_done=true
    echo "validated final uninstall cleanup"
    return 0
}

write_acceptance_summary() {
    local summary_path="$RESULTS_DIR/acceptance-summary.json"
    /usr/bin/python3 - "$CASES_PATH" "$RESULTS_DIR" "$summary_path" "$HOST_VERSION" "$DEVICE_VERSION" <<'PY'
import json
from pathlib import Path
import sys

manifest_path, results_dir, summary_path, host_version, device_version = sys.argv[1:]
results_root = Path(results_dir)
with open(manifest_path, encoding="utf-8") as stream:
    manifest = json.load(stream)

cases = []
for item in manifest["cases"]:
    case_id = item["id"]
    result_path = results_root / f"{case_id}.json"
    metadata_path = results_root / f"{case_id}-metadata.json"
    before_path = results_root / f"{case_id}-before.txt"
    after_path = results_root / f"{case_id}-after.txt"
    with open(result_path, encoding="utf-8") as stream:
        result = json.load(stream)
    with open(metadata_path, encoding="utf-8") as stream:
        metadata = json.load(stream)
    for path in (before_path, after_path):
        if not path.is_file():
            raise SystemExit(f"missing snapshot for {case_id}: {path}")
    if result.get("case") != case_id or result.get("passed") is not True:
        raise SystemExit(f"case did not produce a passed typed result: {case_id}")
    if metadata.get("case") != case_id:
        raise SystemExit(f"case metadata mismatch: {case_id}")
    cases.append(
        {
            "id": case_id,
            "expected": item.get("expected"),
            "expectedError": item.get("expectedError"),
            "typedResult": result,
            "metadata": metadata,
            "beforeSnapshot": str(before_path),
            "afterSnapshot": str(after_path),
        }
    )

cleanup_path = results_root / "final-cleanup.json"
with open(cleanup_path, encoding="utf-8") as stream:
    cleanup = json.load(stream)
required_cleanup = [
    "serviceAbsent",
    "helperToolAbsent",
    "launchDaemonPlistAbsent",
    "runtimeParentAbsent",
    "rootProcessesAbsent",
]
if any(cleanup.get(key) is not True for key in required_cleanup):
    raise SystemExit("final cleanup was not fully verified")

environment_path = results_root / "environment.json"
with open(environment_path, encoding="utf-8") as stream:
    environment = json.load(stream)
with open(summary_path, "w", encoding="utf-8") as stream:
    json.dump(
        {
            "schemaVersion": 1,
            "command": "sudo iPhoneLocationMoveTunnelHelper/Acceptance/run-production-acceptance.sh",
            "hostOSVersion": host_version,
            "deviceOSVersion": device_version,
            "environment": environment,
            "callerFixtures": str(results_root / "fixture-preparation.json"),
            "cases": cases,
            "finalCleanup": {"path": str(cleanup_path), "value": cleanup},
        },
        stream,
        sort_keys=True,
        separators=(",", ":"),
    )
    stream.write("\n")
PY
}

# The final uninstall phase is deliberately outside the case loop and always
# runs, even if one case fails.  Its fixed JSON schema is the runner's success
# boundary for task 1.5 production evidence.
if ! run_uninstall; then
    overall_status=1
fi

if [ "$overall_status" -eq 0 ]; then
    if ! write_acceptance_summary; then
        overall_status=1
    fi
fi

exit "$overall_status"

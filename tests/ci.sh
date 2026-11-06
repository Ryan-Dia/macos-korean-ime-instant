#!/bin/bash
# GitHub Actions의 일회용 macOS VM에서 설치 → 재설치 → 제거를 실제로 수행하는 테스트.
# 시스템 설정을 바꾸므로 CI가 아닌 곳에서는 실행을 거부한다.
set -euo pipefail
[[ ${CI:-} == true && ${GITHUB_ACTIONS:-} == true ]] || { echo "CI 전용 테스트입니다. 로컬에서 실행하지 마세요." >&2; exit 1; }

cd "$(dirname "$0")/.."
T=${RUNNER_TEMP:-$(mktemp -d)}/hangul-fix-test
rm -rf "$T"; mkdir -p "$T/Karabiner-Elements.app"
export HANGUL_FIX_KARABINER_APP="$T/Karabiner-Elements.app"   # Karabiner 설치된 것처럼
export HANGUL_FIX_KARABINER_JSON="$T/karabiner.json"
export HANGUL_FIX_STATE_DIR="$T/state"

PB=/usr/libexec/PlistBuddy
fail() { echo "::error::$*"; exit 1; }
pass() { echo "  PASS: $*"; }
ime_id() { eval "$(sed -n '/^ime_bundle_id()/,/^}/p' install.sh)"; PB=$PB ime_bundle_id; }
pref() { defaults read "$1" "$2" 2>/dev/null || echo unset; }
hotkey() {
  local f="$T/hk.plist"; defaults export com.apple.symbolichotkeys "$f" 2>/dev/null || { echo unset; return; }
  $PB -c "Print :AppleSymbolicHotKeys:60" "$f" >/dev/null 2>&1 || { echo unset; return; }
  echo "$($PB -c "Print :AppleSymbolicHotKeys:60:enabled" "$f") $($PB -c "Print :AppleSymbolicHotKeys:60:value:parameters" "$f" | tr -d ' \n')"
}
snapshot() {
  echo "appnap=$(pref "$ID" NSAppSleepDisabled)"
  echo "indicator=$(pref -g TSMLanguageIndicatorEnabled)"
  echo "hotkey=$(hotkey)"
  jq -S . "$HANGUL_FIX_KARABINER_JSON"
}

ID=$(ime_id)
echo "macOS $(sw_vers -productVersion), 한글 입력기 ID: $ID"
[[ -n $ID ]] || fail "입력기 ID 감지 실패"

run_cycle() {  # $1 = 시나리오 이름
  echo "::group::$1"
  cat > "$HANGUL_FIX_KARABINER_JSON" <<'EOF'
{"profiles":[{"name":"Default profile","selected":true,
  "simple_modifications":[{"from":{"key_code":"caps_lock"},"to":[{"key_code":"f19"}]}],
  "complex_modifications":{"rules":[{"description":"other","manipulators":[{"type":"basic","from":{"key_code":"a"},"to":[{"key_code":"b"}]}]}]}}]}
EOF
  local before; before=$(snapshot)
  echo "$before" | head -3

  ./install.sh --dry-run
  [[ $(snapshot) == "$before" ]] || fail "dry-run이 설정을 바꿈"
  [[ ! -d $HANGUL_FIX_STATE_DIR ]] || fail "dry-run이 상태 파일을 만듦"
  pass "dry-run은 아무것도 바꾸지 않음"

  ./install.sh
  [[ $(pref "$ID" NSAppSleepDisabled) == 1 ]] || fail "App Nap 예외 미적용"
  [[ $(pref -g TSMLanguageIndicatorEnabled) == 0 ]] || fail "팝업 설정 미적용"
  [[ $(hotkey) == "true Array{65535808388608}" ]] || fail "단축키 미적용: $(hotkey)"
  jq -e '.profiles[0].complex_modifications.rules[0].description | startswith("Caps Lock:")' "$HANGUL_FIX_KARABINER_JSON" >/dev/null || fail "규칙이 1순위가 아님"
  jq -e '.profiles[0].complex_modifications.rules[1].description == "other"' "$HANGUL_FIX_KARABINER_JSON" >/dev/null || fail "기존 규칙 유실"
  jq -e '.profiles[0].simple_modifications == []' "$HANGUL_FIX_KARABINER_JSON" >/dev/null || fail "충돌 매핑 미제거"
  pass "설치"

  local after; after=$(snapshot)
  out=$(./install.sh)
  [[ $(snapshot) == "$after" ]] || fail "재설치 시 설정이 바뀜"
  ! grep -q "→" <<<"$out" || fail "재설치 시 변경 작업이 발생: $out"
  pass "재설치 (변경 없음)"

  ./install.sh --check || true   # Karabiner 미실행이므로 실패가 정상

  ./install.sh --uninstall
  [[ $(snapshot) == "$before" ]] || { diff <(echo "$before") <(snapshot) || true; fail "제거 후 원상복구 안 됨"; }
  pass "제거 (원상복구)"
  echo "::endgroup::"
}

# 시나리오 1: 단축키가 기본값(키 없음)인 새 맥
run_cycle "기본 상태에서 설치/제거"

# 시나리오 2: 사용자가 단축키를 직접 바꿔 둔 맥 (Control+Option+Space)
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 60 \
  "<dict><key>enabled</key><true/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>786432</integer></array><key>type</key><string>standard</string></dict></dict>"
run_cycle "사용자 단축키가 있을 때 설치/제거"

echo "모든 테스트 통과"

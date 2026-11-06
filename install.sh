#!/bin/bash
# macos-korean-ime-instant — 맥 한영 전환 딜레이 제거
#
#   install.sh              설치 (여러 번 실행해도 안전)
#   install.sh --uninstall  설치 전 상태로 되돌리기
#   install.sh --check      현재 상태 점검 (아무것도 바꾸지 않음)
#   install.sh --dry-run    무엇을 바꿀지 출력만 함 (--uninstall과 함께 써도 됨)
#
# 한 줄 설치:
#   curl -fsSL https://raw.githubusercontent.com/Ryan-Dia/macos-korean-ime-instant/main/install.sh | bash
set -euo pipefail

VERSION="1.0.0"
RULE_DESC="Caps Lock: 누르는 순간 F19 탭 (한영 전환 즉시)"
RULE_JSON='{"description":"'"$RULE_DESC"'","manipulators":[{"type":"basic","from":{"key_code":"caps_lock","modifiers":{"optional":["any"]}},"to":[{"key_code":"f19"},{"key_code":"vk_none"}]}]}'

# 시스템 단축키 60 = "이전 입력 소스 선택". F19 = keycode 80, 8388608 = 기능키 플래그
HOTKEY_ID=60
HOTKEY_WANT="1 65535 80 8388608"
ACTIVATE_SETTINGS=/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings
PB=/usr/libexec/PlistBuddy
KARABINER_APP="${HANGUL_FIX_KARABINER_APP:-/Applications/Karabiner-Elements.app}"

# 테스트용으로 경로를 바꿀 수 있음 (실제 설정을 건드리지 않고 Karabiner 로직만 시험할 때)
KARABINER_JSON="${HANGUL_FIX_KARABINER_JSON:-$HOME/.config/karabiner/karabiner.json}"
STATE_DIR="${HANGUL_FIX_STATE_DIR:-$HOME/Library/Application Support/macos-korean-ime-instant}"
ONLY_KARABINER="${HANGUL_FIX_ONLY_KARABINER:-0}"

MODE=install
DRY_RUN=0
NEED_LOGOUT=0
NEED_IME_RESTART=0
WARNINGS=0

# ───────────────────────── 출력 ─────────────────────────
if [[ -t 1 ]]; then B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; D=$'\e[2m'; N=$'\e[0m'
else B=; G=; Y=; R=; D=; N=; fi
say()  { printf '%s\n' "$*"; }
step() { printf '\n%s▸ %s%s\n' "$B" "$*" "$N"; }
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$*"; }
todo() { printf '  %s→%s %s\n' "$Y" "$N" "$*"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$*"; WARNINGS=$((WARNINGS + 1)); }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$*"; }
die()  { printf '%s오류:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

run() {
  if (( DRY_RUN )); then printf '    %s[dry-run] %s%s\n' "$D" "$*" "$N"
  else "$@"; fi
}

usage() { sed -n '2,11p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//' || true; }

# ───────────────────────── 상태 저장 (되돌리기용) ─────────────────────────
# 설치 전 원래 값을 처음 한 번만 기록한다. 재설치해도 덮어쓰지 않음.
save_state() {
  local f="$STATE_DIR/$1.prev"
  [[ -e $f ]] && return 0
  (( DRY_RUN )) && return 0
  mkdir -p "$STATE_DIR"
  printf '%s\n' "$2" > "$f"
}
load_state() { cat "$STATE_DIR/$1.prev" 2>/dev/null || echo "__nostate__"; }

pref_get() { defaults read "$1" "$2" 2>/dev/null || echo "__unset__"; }

# ───────────────────────── 한글 입력기 ─────────────────────────
# Sequoia/Tahoe: KoreanIM.app 안의 KIM_Extension.appex가 실제 입력기 프로세스.
# 바깥 컨테이너(com.apple.KIM-Container)가 아니라 appex의 Bundle ID에 설정해야 한다.
ime_bundle_id() {
  local appex plist id
  for appex in "/System/Library/Input Methods/KoreanIM.app/Contents/PlugIns/"*.appex; do
    plist="$appex/Contents/Info.plist"
    [[ -f $plist ]] || continue
    if id=$($PB -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null); then echo "$id"; return; fi
  done
  plist="/System/Library/Input Methods/Korean.app/Contents/Info.plist"
  if [[ -f $plist ]] && id=$($PB -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null); then echo "$id"; return; fi
  echo "com.apple.inputmethod.Korean"
}
ime_pid() { pgrep -f "/System/Library/Input Methods/Korean" | head -1 || true; }

# ───────────────────────── 시스템 단축키 ─────────────────────────
hotkey_get() {  # "enabled p0 p1 p2" 또는 __unset__
  local tmp k="AppleSymbolicHotKeys:$HOTKEY_ID" en p0 p1 p2
  tmp=$(mktemp)
  if ! defaults export com.apple.symbolichotkeys "$tmp" 2>/dev/null \
     || ! $PB -c "Print :$k" "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; echo "__unset__"; return
  fi
  en=$($PB -c "Print :$k:enabled" "$tmp" 2>/dev/null || echo 0)
  [[ $en == true || $en == 1 ]] && en=1 || en=0
  p0=$($PB -c "Print :$k:value:parameters:0" "$tmp" 2>/dev/null || echo 0)
  p1=$($PB -c "Print :$k:value:parameters:1" "$tmp" 2>/dev/null || echo 0)
  p2=$($PB -c "Print :$k:value:parameters:2" "$tmp" 2>/dev/null || echo 0)
  rm -f "$tmp"
  echo "$en $p0 $p1 $p2"
}
hotkey_set() {  # enabled p0 p1 p2
  local b='<false/>'; [[ $1 == 1 ]] && b='<true/>'
  run defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add "$HOTKEY_ID" \
    "<dict><key>enabled</key>$b<key>value</key><dict><key>parameters</key><array><integer>$2</integer><integer>$3</integer><integer>$4</integer></array><key>type</key><string>standard</string></dict></dict>"
}
hotkey_delete() {
  local tmp; tmp=$(mktemp)
  run defaults export com.apple.symbolichotkeys "$tmp"
  run "$PB" -c "Delete :AppleSymbolicHotKeys:$HOTKEY_ID" "$tmp"
  run defaults import com.apple.symbolichotkeys "$tmp"
  rm -f "$tmp"
}
hotkey_apply() { [[ -x $ACTIVATE_SETTINGS ]] && run "$ACTIVATE_SETTINGS" -u || NEED_LOGOUT=1; }
hotkey_describe() {
  case "$1" in
    "$HOTKEY_WANT") echo "F19" ;;
    "__unset__")    echo "기본값(Control+Space)" ;;
    "0 "*)          echo "꺼짐" ;;
    *)              echo "다른 키 (${1#* })" ;;
  esac
}

# ───────────────────────── Karabiner 설정 (JXA로 JSON 편집) ─────────────────────────
# python3가 없는 새 맥에서도 돌도록 macOS 내장 JavaScript(osascript)를 사용한다.
karabiner_js() {  # action [restore_file]
  local js; js=$(mktemp -t hangulfix)
  cat > "$js" <<'JS'
ObjC.import('Foundation');
function readFile(p) {
  if (!p) return null;
  const s = $.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null);
  return s.isNil() ? null : ObjC.unwrap(s);
}
function run(argv) {
  const [action, path, desc, ruleJson, restorePath, dry] = argv;
  const rule = JSON.parse(ruleJson);
  const text = readFile(path);
  const d = text ? JSON.parse(text) : { profiles: [] };
  d.profiles = d.profiles || [];
  if (!d.profiles.length) d.profiles.push({ name: 'Default profile', selected: true });
  const prof = d.profiles.find(p => p.selected) || d.profiles[0];
  const isCaps = m => !!(m && m.from && m.from.key_code === 'caps_lock');
  const out = [];

  if (action === 'status') {
    const rules = (prof.complex_modifications || {}).rules || [];
    const idx = rules.findIndex(r => r.description === desc);
    let earlier = 0, devCaps = 0;
    rules.slice(0, idx < 0 ? rules.length : idx)
      .forEach(r => (r.manipulators || []).forEach(m => { if (isCaps(m)) earlier++; }));
    (prof.devices || []).forEach(dv => (dv.simple_modifications || [])
      .forEach(m => { if (isCaps(m)) devCaps++; }));
    out.push('exists=' + (text ? 1 : 0));
    out.push('rule_index=' + idx);
    out.push('rule_same=' + (idx >= 0 && JSON.stringify(rules[idx]) === JSON.stringify(rule) ? 1 : 0));
    out.push('simple_caps=' + (prof.simple_modifications || []).filter(isCaps).length);
    out.push('device_caps=' + devCaps);
    out.push('earlier_caps=' + earlier);
    return out.join('\n');
  }

  const before = text ? JSON.stringify(JSON.parse(text)) : '';
  prof.complex_modifications = prof.complex_modifications || {};
  let rules = (prof.complex_modifications.rules || []).filter(r => r.description !== desc);
  const simple = prof.simple_modifications || [];

  if (action === 'install') {
    out.push('removed_simple=' + JSON.stringify(simple.filter(isCaps)));
    prof.simple_modifications = simple.filter(m => !isCaps(m));
    rules.unshift(rule);
  } else if (action === 'uninstall') {
    const restore = JSON.parse(readFile(restorePath) || '[]');
    restore.forEach(m => {
      if (!simple.some(s => JSON.stringify(s) === JSON.stringify(m))) simple.push(m);
    });
    prof.simple_modifications = simple;
  }
  prof.complex_modifications.rules = rules;

  const after = JSON.stringify(d);
  const changed = after !== before;
  out.push('changed=' + (changed ? 1 : 0));
  if (changed && dry !== '1') {
    const dir = $(path).stringByDeletingLastPathComponent;
    $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(dir, true, $(), null);
    const ok = $(JSON.stringify(d, null, 4) + '\n')
      .writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, null);
    if (!ok) throw new Error('쓰기 실패: ' + path);
  }
  return out.join('\n');
}
JS
  local rc=0
  osascript -l JavaScript "$js" "$1" "$KARABINER_JSON" "$RULE_DESC" "$RULE_JSON" "${2:-}" "$DRY_RUN" || rc=$?
  rm -f "$js"
  return $rc
}
kv() { sed -n "s/^$1=//p" <<<"$2"; }

karabiner_backup() {
  [[ -f $KARABINER_JSON ]] || return 0
  (( DRY_RUN )) && return 0
  mkdir -p "$STATE_DIR/backups"
  cp "$KARABINER_JSON" "$STATE_DIR/backups/karabiner.json.$(date +%Y%m%d-%H%M%S)"
}

# ───────────────────────── 설치 ─────────────────────────
do_install() {
  local id cur prev

  if [[ $ONLY_KARABINER != 1 ]]; then
    step "1/4 한글 입력기 App Nap 예외"
    id=$(ime_bundle_id)
    cur=$(pref_get "$id" NSAppSleepDisabled)
    if [[ $cur == 1 ]]; then ok "이미 적용됨 ($id)"
    else
      save_state appnap_domain "$id"
      save_state appnap "$cur"
      run defaults write "$id" NSAppSleepDisabled -bool true
      todo "적용: $id"
      NEED_IME_RESTART=1
    fi

    step "2/4 입력 소스 전환 팝업 끄기"
    cur=$(pref_get -g TSMLanguageIndicatorEnabled)
    if [[ $cur == 0 ]]; then ok "이미 꺼져 있음"
    else
      save_state indicator "$cur"
      run defaults write -g TSMLanguageIndicatorEnabled -bool false
      todo "꺼짐 (로그아웃 후 적용)"
      NEED_LOGOUT=1
    fi

    step "3/4 시스템 단축키 '이전 입력 소스 선택' = F19"
    cur=$(hotkey_get)
    if [[ $cur == "$HOTKEY_WANT" ]]; then ok "이미 F19로 설정됨"
    else
      save_state hotkey "$cur"
      # shellcheck disable=SC2086
      hotkey_set $HOTKEY_WANT
      hotkey_apply
      todo "$(hotkey_describe "$cur") → F19"
    fi
  fi

  step "4/4 Karabiner: Caps Lock을 누르는 순간 F19 탭"
  if [[ $ONLY_KARABINER != 1 && ! -d $KARABINER_APP ]]; then
    warn "Karabiner-Elements가 설치되어 있지 않습니다. 설치 후 이 스크립트를 다시 실행하세요:"
    say  "      brew install --cask karabiner-elements"
    say  "      또는 https://karabiner-elements.pqrs.org"
  else
    local res removed
    (( DRY_RUN )) || karabiner_backup
    res=$(karabiner_js install)
    removed=$(kv removed_simple "$res")
    [[ $removed != "[]" && -n $removed ]] && save_state karabiner_simple "$removed"
    [[ $removed == "[]" || -z $removed ]] || todo "기존 Caps Lock 단순 매핑 제거: $removed"
    if [[ $(kv changed "$res") == 1 ]]; then
      todo "규칙 추가 (1순위): $KARABINER_JSON"
      (( DRY_RUN )) && say "    ${D}[dry-run] karabiner.json 수정 생략${N}"
    else ok "이미 적용됨"; fi
  fi

  if (( NEED_IME_RESTART )) && [[ -n $(ime_pid) ]]; then
    step "한글 입력기 재시작 (다음 키 입력 때 자동으로 다시 뜸)"
    run pkill -9 -f "/System/Library/Input Methods/Korean" || true
  fi
}

# ───────────────────────── 제거 ─────────────────────────
do_uninstall() {
  local prev id

  if [[ $ONLY_KARABINER != 1 ]]; then
    step "1/4 App Nap 예외 해제"
    id=$(load_state appnap_domain); [[ $id == __nostate__ ]] && id=$(ime_bundle_id)
    prev=$(load_state appnap)
    if [[ $(pref_get "$id" NSAppSleepDisabled) == __unset__ && $prev != 1 ]]; then ok "설정 없음"
    elif [[ $prev == __unset__ || $prev == __nostate__ ]]; then run defaults delete "$id" NSAppSleepDisabled; todo "삭제: $id"
    else run defaults write "$id" NSAppSleepDisabled -bool "$prev"; todo "원래 값($prev)으로 복원"; fi
    NEED_IME_RESTART=1

    step "2/4 입력 소스 팝업 복원"
    prev=$(load_state indicator)
    if [[ $prev == __unset__ || $prev == __nostate__ ]]; then
      if [[ $(pref_get -g TSMLanguageIndicatorEnabled) == __unset__ ]]; then ok "설정 없음"
      else run defaults delete -g TSMLanguageIndicatorEnabled; todo "삭제 (로그아웃 후 팝업 다시 표시)"; NEED_LOGOUT=1; fi
    else run defaults write -g TSMLanguageIndicatorEnabled -bool "$prev"; todo "원래 값($prev)으로 복원"; NEED_LOGOUT=1; fi

    step "3/4 시스템 단축키 복원"
    prev=$(load_state hotkey)
    if [[ $prev == __nostate__ ]]; then
      ok "설치 전 기록이 없어 그대로 둡니다 (현재: $(hotkey_describe "$(hotkey_get)"))"
    elif [[ $prev == __unset__ ]]; then hotkey_delete; hotkey_apply; todo "기본값(Control+Space)으로 복원"
    else
      # shellcheck disable=SC2086
      hotkey_set $prev; hotkey_apply; todo "$(hotkey_describe "$prev")(으)로 복원"
    fi
  fi

  step "4/4 Karabiner 규칙 제거"
  if [[ -f $KARABINER_JSON ]]; then
    local res restore="$STATE_DIR/karabiner_simple.prev"
    karabiner_backup
    res=$(karabiner_js uninstall "$( [[ -f $restore ]] && echo "$restore")")
    if [[ $(kv changed "$res") == 1 ]]; then
      todo "규칙 제거$( [[ -f $restore ]] && echo " + 기존 Caps Lock 매핑 복원")"
    else ok "규칙 없음"; fi
  else ok "karabiner.json 없음"; fi

  if (( NEED_IME_RESTART )) && [[ -n $(ime_pid) ]]; then
    run pkill -9 -f "/System/Library/Input Methods/Korean" || true
  fi
  if (( ! DRY_RUN )); then
    rm -f "$STATE_DIR"/*.prev
  fi
}

# ───────────────────────── 점검 ─────────────────────────
do_check() {
  local fails=0 id v pid pri res

  step "환경"
  say "  macOS $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
  id=$(ime_bundle_id); say "  한글 입력기 Bundle ID: $id"

  step "설정"
  if [[ $(pref_get "$id" NSAppSleepDisabled) == 1 ]]; then ok "한글 입력기 App Nap 예외"
  else bad "한글 입력기 App Nap 예외 없음"; fails=$((fails + 1)); fi

  if [[ $(pref_get -g TSMLanguageIndicatorEnabled) == 0 ]]; then ok "입력 소스 팝업 꺼짐"
  else bad "입력 소스 팝업 켜짐"; fails=$((fails + 1)); fi

  v=$(hotkey_get)
  if [[ $v == "$HOTKEY_WANT" ]]; then ok "단축키 '이전 입력 소스 선택' = F19"
  else bad "단축키 '이전 입력 소스 선택' = $(hotkey_describe "$v")"; fails=$((fails + 1)); fi

  step "Karabiner"
  if [[ -d $KARABINER_APP ]]; then ok "Karabiner-Elements 설치됨"
  else bad "Karabiner-Elements 미설치"; fails=$((fails + 1)); fi
  if pgrep -qf "Karabiner-Core-Service"; then ok "Karabiner 실행 중"
  else bad "Karabiner가 실행 중이 아님 (앱을 열고 권한을 허용하세요)"; fails=$((fails + 1)); fi

  res=$(karabiner_js status)
  if [[ $(kv rule_index "$res") == -1 ]]; then bad "Caps Lock 규칙 없음"; fails=$((fails + 1))
  elif [[ $(kv rule_same "$res") != 1 ]]; then warn "Caps Lock 규칙이 있지만 내용이 다름 (재설치 권장)"
  else ok "Caps Lock 규칙 적용됨"; fi
  [[ $(kv earlier_caps "$res") == 0 ]] || warn "이 규칙보다 앞에 Caps Lock을 쓰는 다른 규칙이 있습니다"
  [[ $(kv simple_caps "$res") == 0 ]] || warn "Simple Modifications에 Caps Lock 매핑이 남아 있습니다"
  [[ $(kv device_caps "$res") == 0 ]] || warn "기기별 Simple Modifications에 Caps Lock 매핑이 있어 규칙보다 먼저 적용됩니다"

  step "한글 입력기 프로세스"
  pid=$(ime_pid)
  if [[ -z $pid ]]; then say "  실행 중 아님 (한글로 전환하면 뜹니다)"
  else
    pri=$(ps -o pri= -p "$pid" | tr -d ' ')
    if (( pri >= 31 )); then ok "스케줄링 우선순위 $pri (정상, 31 이상)"
    else warn "스케줄링 우선순위 $pri — App Nap에 걸린 상태. 로그아웃 후 다시 확인하세요"; fi
  fi

  say ""
  if (( fails == 0 )); then say "${G}${B}모두 정상${N}"; return 0
  else say "${R}${B}${fails}개 항목 미적용${N} — install.sh로 설치하세요"; return 1; fi
}

# ───────────────────────── main ─────────────────────────
for a in "$@"; do
  case $a in
    --uninstall|uninstall) MODE=uninstall ;;
    --check|check)         MODE=check ;;
    --dry-run|-n)          DRY_RUN=1 ;;
    -h|--help)             usage; exit 0 ;;
    --version)             echo "$VERSION"; exit 0 ;;
    *) die "알 수 없는 옵션: $a (--help 참고)" ;;
  esac
done

[[ $(uname -s) == Darwin ]] || die "macOS 전용입니다."

case $MODE in
  check) do_check; exit $? ;;
  install)
    say "${B}macos-korean-ime-instant $VERSION — 설치${N}$( (( DRY_RUN )) && echo " ${Y}(dry-run: 아무것도 바꾸지 않음)${N}")"
    do_install ;;
  uninstall)
    say "${B}macos-korean-ime-instant $VERSION — 제거${N}$( (( DRY_RUN )) && echo " ${Y}(dry-run: 아무것도 바꾸지 않음)${N}")"
    do_uninstall ;;
esac

say ""
if (( DRY_RUN )); then say "dry-run 완료. 실제로 적용하려면 --dry-run 없이 실행하세요."; exit 0; fi
say "${G}${B}완료${N}"
(( NEED_LOGOUT )) && say "  • 로그아웃 후 다시 로그인해야 일부 설정이 적용됩니다 ( 메뉴 → 로그아웃)."
if [[ $MODE == install ]]; then
  say "  • Karabiner를 처음 설치했다면 앱을 열어 '입력 모니터링'과 드라이버 권한을 허용하세요."
  say "  • 상태 점검: install.sh --check"
fi
(( WARNINGS == 0 )) || exit 2

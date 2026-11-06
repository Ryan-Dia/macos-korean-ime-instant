# CLAUDE.md — 한영 전환 딜레이 제거를 대신 설치할 때

사용자가 이 저장소를 주며 "한영 전환 딜레이 없애줘"라고 하면 아래 순서대로 진행한다.
배경 설명과 원인 분석은 README.md에 있다.

## 목표

Caps Lock을 **누르는 순간** 한/영이 바뀌게 한다. 구성 요소는 네 가지이고 `install.sh`가 모두 처리한다.

1. Karabiner 규칙: `caps_lock` → `[f19, vk_none]` (F19를 즉시 눌렀다 뗌)
2. 시스템 단축키 60 "이전 입력 소스 선택" = F19
3. 한글 입력기만 App Nap 예외 (`NSAppSleepDisabled`)
4. 입력 소스 팝업 끄기 (`TSMLanguageIndicatorEnabled`)

## 절차

1. **사전 점검 (읽기 전용)**
   ```bash
   ./install.sh --check
   ```
   - 한글 입력 소스(두벌식 등)가 켜져 있는지 확인한다: `defaults read com.apple.HIToolbox AppleEnabledInputSources`
   - 세벌식 등 다른 한글 자판을 쓰는 사용자라도 그대로 동작한다(단축키가 "이전 입력 소스"로 토글하므로).

2. **Karabiner-Elements 설치 확인**
   - 없으면 사용자에게 알리고 `brew install --cask karabiner-elements`를 실행한다(brew가 없으면 https://karabiner-elements.pqrs.org 안내).
   - 설치 직후에는 **사용자가 직접** 앱을 열어 권한을 허용해야 한다. 자동화 불가. 안내 문구:
     - 시스템 설정 → 개인정보 보호 및 보안 → 입력 모니터링: `karabiner_grabber`, `karabiner_observer` 허용
     - 시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → 드라이버 확장 프로그램: Karabiner 켜기
   - `pgrep -f Karabiner-Core-Service`로 실행 여부를 확인한 뒤 다음 단계로 간다.

3. **미리 보기 → 설치**
   ```bash
   ./install.sh --dry-run    # 바뀔 내용을 사용자에게 요약해서 보여준다
   ./install.sh
   ```
   - 기존 Karabiner 설정은 `~/Library/Application Support/macos-korean-ime-instant/backups/`에 자동 백업된다.
   - 설치 전 원래 값은 같은 폴더의 `*.prev`에 기록되고 `--uninstall`이 이걸로 복원한다.

4. **로그아웃 안내** — 팝업 설정은 재로그인 후 적용된다. 로그아웃은 사용자에게 맡긴다(작업 중인 앱이 닫히고 Claude 세션도 끝나므로 직접 실행하지 말 것).

5. **검증** — 재로그인 후 `./install.sh --check`가 "모두 정상"인지 확인하고,
   사용자에게 Caps Lock을 **누른 채로** 메뉴바 입력기 아이콘이 바로 바뀌는지 봐 달라고 한다.

## 함정 (실제로 겪은 것)

- **`select_input_source`를 쓰지 말 것.** Karabiner에서 입력 소스를 직접 선택하는 방식은 macOS 15에서 한영 전환이 아예 멈췄다. 반드시 F19 → 시스템 단축키 경로를 쓴다.
- **Simple Modifications의 `caps_lock → f19`는 원인 그 자체다.** F19가 눌린 채 유지되어 macOS가 키를 뗄 때 전환한다. `install.sh`가 자동으로 제거한다. 기기별(devices) Simple Modifications에 caps_lock 매핑이 있으면 `--check`가 경고하니, 그건 사용자와 상의해서 지운다.
- **Bundle ID**: `KoreanIM.app`의 ID(`com.apple.KIM-Container`)가 아니라 그 안 `KIM_Extension.appex`의 ID(`com.apple.inputmethod.Korean`)에 App Nap 예외를 걸어야 한다. `install.sh`가 자동 감지한다.
- **입력기 재시작은 `kill -9`가 필요하다.** SIGTERM(`killall KIM_Extension`)은 무시된다. 재시작하면 다음 키 입력 때 자동으로 다시 뜬다.
- 입력기 프로세스 우선순위 확인: `ps -o pri= -p $(pgrep KIM_Extension)` — macOS에선 **클수록 높다**. 4면 App Nap에 걸린 상태, 46이면 정상.
- zsh에서 `log`는 내장 명령이다. 시스템 로그는 `/usr/bin/log show ...`로 호출한다.

## 그래도 늦다고 하면

1. **블루투스 키보드 절전**을 먼저 의심한다: `system_profiler SPBluetoothDataType`로 외장 키보드 연결 방식을 확인하고, 맥북 내장 키보드에서도 같은지 비교해 달라고 한다. 내장 키보드에서 빠르면 입력기 문제가 아니다.
2. 다른 Karabiner 규칙이 Caps Lock을 먼저 가져가는지: `./install.sh --check`의 경고.
3. 시스템 단축키 61("다음 입력 소스")이나 다른 앱(Raycast, Alfred 등)이 F19를 쓰는지 확인한다.

## 되돌리기

```bash
./install.sh --uninstall --dry-run
./install.sh --uninstall
```

## 개발 메모

- `install.sh`는 python3에 의존하지 않는다(새 맥에는 없음). JSON 편집은 `osascript -l JavaScript`로 한다.
- 실제 설정을 건드리지 않고 Karabiner 로직만 시험하려면 환경변수로 경로를 바꾼다:
  ```bash
  HANGUL_FIX_ONLY_KARABINER=1 HANGUL_FIX_KARABINER_JSON=/tmp/k.json HANGUL_FIX_STATE_DIR=/tmp/state ./install.sh
  ```
- 규칙을 바꾸면 `install.sh`의 `RULE_JSON`과 `karabiner/hangul-caps-lock.json`을 함께 고친다.

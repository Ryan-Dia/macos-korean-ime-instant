# macos-korean-ime-instant

맥에서 **Caps Lock 한영 전환을 누르는 순간 바로** 되게 만드는 설정 스크립트입니다.
"한영 전환하고 바로 치면 첫 글자가 영어로 나온다", "잠깐 쉬었다 전환하면 1초쯤 늦다"는 증상을 없앱니다.

```bash
curl -fsSL https://raw.githubusercontent.com/Ryan-Dia/macos-korean-ime-instant/main/install.sh | bash
```

- [Karabiner-Elements](https://karabiner-elements.pqrs.org)가 필요합니다. 없으면 `brew install --cask karabiner-elements`로 먼저 설치하고 앱을 열어 권한을 허용하세요.
- 여러 번 실행해도 안전합니다. 이미 적용된 항목은 건너뜁니다.
- 바꾸기 전 원래 값을 기록해 두므로 `--uninstall`로 그대로 되돌릴 수 있습니다.

## 무엇을 바꾸나

| # | 설정 | 효과 |
|---|---|---|
| 1 | **Karabiner: Caps Lock → F19 *탭*** | 키를 **누르는 순간** 전환 (핵심) |
| 2 | 시스템 단축키 "이전 입력 소스 선택" = F19 | 1번의 F19를 한영 전환으로 연결 |
| 3 | 한글 입력기만 App Nap 예외 | 쉬는 동안 입력기가 잠들지 않음 |
| 4 | 입력 소스 전환 팝업 끄기 | 전환 시 커서 옆 "한/A" 팝업 제거 |

시스템 전체 App Nap은 건드리지 않습니다. 배터리 영향은 한글 입력기 프로세스 하나 분량입니다.

## 왜 늦었나

### 1. 키를 *뗄 때* 전환되고 있었다 (가장 큰 원인)

흔히 쓰는 Karabiner 설정 `caps_lock → f19` (Simple Modifications)는 Caps Lock을 누르고 있는 동안 F19도 **눌린 상태로 유지**합니다.
macOS의 "이전 입력 소스 선택" 단축키는 키를 계속 누르면 입력 소스 선택창을 띄우도록 되어 있어서, 짧게 눌렀는지 판단하려고 **키를 뗄 때까지 전환을 미룹니다.**
누르고 떼는 데 걸리는 100~200ms가 고스란히 지연이 되고, 빨리 치면 첫 글자가 이전 언어로 나옵니다.

해결: Karabiner에서 F19 뒤에 `vk_none`을 붙이면, Caps Lock을 누르는 순간 F19 *눌렀다 떼기*가 한 번에 전달됩니다.

```json
"to": [{ "key_code": "f19" }, { "key_code": "vk_none" }]
```

### 2. 한글 입력기가 App Nap에 걸려 있었다

Sequoia 이후 한글 입력기는 `KoreanIM.app` 안의 `KIM_Extension`이라는 별도 프로세스로 돕니다.
`runningboardd` 로그를 보면 이 프로세스에 App Nap이 전부 켜져 있었습니다.

```
[xpcservice<com.apple.inputmethod.Korean>] Set AppNap state: enabled:Y active:Y ... priority:Y cpu:Y timer:Tier5
```

이 때문에 스케줄링 우선순위가 **4**까지 내려가 있었습니다(일반 프로세스 31, 화면 앞 UI 46).
`NSAppSleepDisabled`를 설정한 뒤에는 **46**을 유지합니다.

```bash
ps -o pri= -p $(pgrep KIM_Extension)    # 46이면 정상
```

> **Bundle ID 주의:** `KoreanIM.app`의 Bundle ID는 `com.apple.KIM-Container`(바깥 컨테이너)이고,
> 실제로 도는 입력기(`KIM_Extension.appex`)는 `com.apple.inputmethod.Korean`입니다. 설정은 후자에 해야 합니다.
> `install.sh`는 설치된 입력기에서 이 값을 자동으로 읽습니다.

## 시도했지만 안 된 것

- **Karabiner `select_input_source`로 직접 전환:** macOS 15.8에서 전환 자체가 동작하지 않았습니다. 시스템 단축키(F19)를 거치는 방식을 쓰는 이유입니다.
- **App Nap만 끄기:** 우선순위는 정상이 됐지만 체감 지연은 남았습니다. 원인 1(키를 뗄 때 전환)이 더 컸습니다.

## 사용법

```bash
git clone https://github.com/Ryan-Dia/macos-korean-ime-instant.git
cd macos-korean-ime-instant

./install.sh --dry-run   # 무엇이 바뀔지 미리 보기 (아무것도 바꾸지 않음)
./install.sh             # 설치
./check.sh               # 상태 점검
./uninstall.sh           # 원상복구
```

clone 없이:

```bash
curl -fsSL https://raw.githubusercontent.com/Ryan-Dia/macos-korean-ime-instant/main/install.sh | bash -s -- --check
curl -fsSL https://raw.githubusercontent.com/Ryan-Dia/macos-korean-ime-instant/main/install.sh | bash -s -- --uninstall
```

설치 후 **로그아웃 → 다시 로그인**해야 팝업 설정이 적용됩니다.

### 새 맥 처음 세팅 순서

1. `brew install --cask karabiner-elements`
2. Karabiner-Elements를 열고 안내에 따라 허용
   - 시스템 설정 → 개인정보 보호 및 보안 → **입력 모니터링**: `karabiner_grabber`, `karabiner_observer`
   - 시스템 설정 → 일반 → 로그인 항목 및 확장 프로그램 → **드라이버 확장 프로그램**: Karabiner 켜기
3. 위의 `curl ... | bash` 실행
4. 로그아웃 → 로그인
5. `./check.sh` 또는 `curl ... | bash -s -- --check`로 모두 ✓인지 확인

### Karabiner 규칙만 수동으로 넣고 싶다면

[`karabiner/hangul-caps-lock.json`](karabiner/hangul-caps-lock.json)을 `~/.config/karabiner/assets/complex_modifications/`에 복사한 뒤
Karabiner → Complex Modifications → Add predefined rule에서 켜세요.
기존 Simple Modifications의 `caps_lock → f19`는 지워야 합니다(남아 있으면 이 규칙보다 먼저 적용됩니다).
시스템 설정 → 키보드 → 키보드 단축키 → 입력 소스 → "이전 입력 소스 선택"을 F19로 지정하세요.

## 그래도 늦다면

- **블루투스 키보드:** 오래 쉬면 키보드가 절전에 들어가 첫 키가 늦거나 씹힐 수 있습니다. 맥북 내장 키보드와 비교해 보세요. 내장 키보드에서만 빠르다면 키보드 쪽 문제입니다(동글/유선 연결, 키보드 절전 설정).
- **자모 분리(ㅎㅏㄴ):** Spotlight를 한 번 열었다 닫으면 풀린다는 보고가 있습니다.
- `./check.sh`의 경고 항목을 확인하세요. 다른 Karabiner 규칙이 Caps Lock을 먼저 가져가는 경우도 잡아 줍니다.

## 변경되는 파일과 되돌리기

| 대상 | 위치 |
|---|---|
| App Nap 예외 | `defaults` 도메인 `com.apple.inputmethod.Korean` → `NSAppSleepDisabled` |
| 팝업 | 전역 도메인 → `TSMLanguageIndicatorEnabled` |
| 단축키 | `com.apple.symbolichotkeys` → `AppleSymbolicHotKeys` 60번 |
| Karabiner | `~/.config/karabiner/karabiner.json` (선택된 프로필) |
| 원래 값 기록·백업 | `~/Library/Application Support/macos-korean-ime-instant/` |

`--uninstall`은 기록해 둔 원래 값으로 되돌리고 Karabiner 규칙을 지운 뒤, 제거했던 기존 Caps Lock 매핑을 복원합니다.
수정 전 `karabiner.json`은 매번 `backups/`에 복사됩니다.

## 테스트

GitHub Actions의 macOS 14 / 15 / 26 가상머신에서 매 커밋마다 `dry-run → 설치 → 재설치 → 제거`를 실제로 돌려 원상복구까지 확인합니다([`tests/ci.sh`](tests/ci.sh)).

## 출처

- 클리앙 [맥 한영 전환 딜레이 개선팁](https://www.clien.net/service/board/lecture/19179255) 및 댓글
  (App Nap 원인 분석, 입력기별 Bundle ID 예외 아이디어)

## 라이선스

MIT

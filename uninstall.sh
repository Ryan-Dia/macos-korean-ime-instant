#!/bin/bash
# 설치 전 상태로 되돌린다. (--dry-run 지원)
exec "$(dirname "$0")/install.sh" --uninstall "$@"

#!/bin/bash
# 현재 상태 점검. 아무것도 바꾸지 않는다.
exec "$(dirname "$0")/install.sh" --check "$@"

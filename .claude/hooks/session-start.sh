#!/bin/sh
# SessionStart: 세션 캐시를 비우고 협업 현황(digest)을 주입한다. 실패해도 세션은 계속된다.
. "$(dirname "$0")/lib.sh"
rm -f "$CACHE/edits" "$CACHE/warned" "$CACHE/overlaps.prev" "$CACHE/allow" "$CACHE/asked"
exec sh "$ROOT/scripts/collab.sh" digest --fetch

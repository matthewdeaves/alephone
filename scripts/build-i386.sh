#!/usr/bin/env bash
# build-i386.sh - guarded driver for the declared legacy Intel slice.
#
# The compiler/runtime proof is owned by buildhost.  Keep this selection and
# preflight separate from the eventual remote build so an unproven compiler,
# SDK, or x86_64 dependency can never be mistaken for i386 coverage.
set -euo pipefail

HOST="${ALEPHONE_I386_HOST:-imac-2019}"
if [ "$HOST" != "imac-2019" ]; then
	echo "build-i386.sh: i386 is routed only to imac-2019; got $HOST" >&2
	exit 2
fi

required='ALEPHONE_I386_CC ALEPHONE_I386_CXX ALEPHONE_I386_SDK ALEPHONE_I386_RUNTIME_FLAGS ALEPHONE_I386_DEPS ALEPHONE_I386_SDL_DIR'
missing=''
for name in $required; do
	eval "value=\${$name:-}"
	[ -n "$value" ] || missing="$missing $name"
done
if [ -n "$missing" ]; then
	echo "build-i386.sh: i386 toolchain proof is not installed; missing:$missing" >&2
	echo "build-i386.sh: buildhost must provide proven imac-2019 compiler, SDK, redistributable runtime flags, deps, and SDL prefix" >&2
	exit 2
fi

echo "build-i386.sh: selected $HOST with buildhost-provided i386 toolchain inputs"
echo "build-i386.sh: remote build is intentionally disabled until the recorded proof is attached to #30"
exit 2

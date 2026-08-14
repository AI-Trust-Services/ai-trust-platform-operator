#!/bin/bash
cd /mnt/c/claude/projects/eu-ai-trust-platform/ai-trust-platform-git
git config user.name "mircea" 2>/dev/null; git config user.email "mircea.craciun@sap.com" 2>/dev/null
git add -A
git commit -F - <<'MSG'
AC4: make the tenancy resolver pluggable (register_resolver / TENANCY_RESOLVER)

A re-audit rated issue #16 AC4 (modular/replaceable tenancy module) PARTIAL because
the resolver was a hardcoded 3-mode if/else — an enterprise could pick a mode but not
supply a CUSTOM resolver without forking. Added an extension point:
- register_resolver(fn): programmatic hook, fn(request) -> str | None.
- TENANCY_RESOLVER="pkg.mod:callable": config-based hook, imported on first use.
A registered resolver takes precedence over the built-in single/jwt/header modes;
returning None falls through to them (augment, not only replace). Built-ins remain the
defaults. Exported from the package; documented in ADR-001; 2 tests added (custom wins;
None falls through). Moves AC4 from PARTIAL to a defensible PASS.
MSG
git log --oneline -3
echo DONE

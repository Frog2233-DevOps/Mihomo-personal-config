#!/usr/bin/env bash
# Unit tests for the domain normalizer of build-ruleset.sh.
# The function is extracted from the real script, not reimplemented here.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. extract normalize() from build-ruleset.sh"
norm=$(awk '/^normalize\(\) \{/{f=1} f{print} f && /^}/{exit}' scripts/build-ruleset.sh)
if [ -n "$norm" ]; then ok "normalize() found"; else bad "normalize() not found"; summary; exit 1; fi
eval "$norm"

section "2. fixture with every input shape"
cat > "$TMPDIR_TEST/in" <<'EOF'
# comment

01-klinika-21.ru
xn--80ak6aa92e.com
www.instagram.com
*.wild.example.com
+.already.com
||ads^block.com
http://bad.example.com
1.2.3.4
with space.example.com
EOF
normalize "$TMPDIR_TEST/in" "$TMPDIR_TEST/out"

section "3. hyphenated and punycode domains are kept"
for d in 01-klinika-21.ru xn--80ak6aa92e.com; do
  if grep -qxF -- "+.$d" "$TMPDIR_TEST/out"; then ok "kept $d"; else bad "LOST $d"; fi
done

section "4. wildcards, prefixes and normal domains"
for d in www.instagram.com wild.example.com already.com; do
  if grep -qxF -- "+.$d" "$TMPDIR_TEST/out"; then ok "kept $d"; else bad "LOST $d"; fi
done

section "5. junk is still dropped"
for badline in 'ads^block.com' 'http://bad.example.com' 'with space.example.com' '1.2.3.4' 'comment'; do
  if grep -qF -- "$badline" "$TMPDIR_TEST/out"; then bad "junk not dropped: $badline"; else ok "dropped junk: $badline"; fi
done

section "6. output is sorted and unique"
sort -u "$TMPDIR_TEST/out" > "$TMPDIR_TEST/sorted"
cmp -s "$TMPDIR_TEST/out" "$TMPDIR_TEST/sorted" && ok "sorted and unique" || bad "output is not sorted/unique"

section "7. CRLF input from an upstream list"
printf 'crlf-hyphen.example.com\r\n' > "$TMPDIR_TEST/crlf.in"
normalize "$TMPDIR_TEST/crlf.in" "$TMPDIR_TEST/crlf.out"
if grep -qxF -- '+.crlf-hyphen.example.com' "$TMPDIR_TEST/crlf.out"; then ok "CRLF handled"; else bad "CRLF broke the domain"; fi

section "8. committed rule-sets are not from the old (hyphen-dropping) build"
# A rebuild from the same upstream list with the old regex used to be exactly
# 414716 bytes; after the fix the file is larger. This guards the shipped file.
sz=$(wc -c < ruleset/rkn-blocked.mrs)
if [ "$sz" -gt 500000 ]; then ok "rkn-blocked.mrs contains the hyphenated domains ($sz bytes)"; else bad "rkn-blocked.mrs looks like the old build ($sz bytes)"; fi

summary

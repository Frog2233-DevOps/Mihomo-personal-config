#!/usr/bin/env bash
# Documentation completeness: EN/RU pairs, full lifecycle, AI-agent notes.
set -u
. "$(dirname "$0")/lib.sh"
cd "$ROOT"

section "1. every English doc has a full Russian twin"
for en in docs/DESIGN.md docs/GROUPS.md docs/INSTALL.md docs/RULESETS.md docs/TEST-REPORT.md docs/MIXOMO.md; do
  ru="${en%.md}-RU.md"
  [ -f "$ru" ] || { bad "$ru missing"; continue; }
  # Compare the number of top-level sections: a stub translation is not enough.
  a=$(grep -c '^## ' "$en"); b=$(grep -c '^## ' "$ru")
  if [ "$a" -gt 0 ] && [ "$b" -ge "$((a - 1))" ]; then ok "$ru has $b/$a sections"; else bad "$ru has only $b/$a sections"; fi
done

section "2. README pair"
has README.md "## The three variants"
has README-RU.md "## Три варианта"
has README.md "## The placeholders"
has README-RU.md "## Плейсхолдеры"

section "3. full lifecycle is documented in both languages"
for f in docs/INSTALL.md docs/INSTALL-RU.md; do
  for kw in deploy apply update-rulesets crontab troubleshoot; do
    # Russian docs use the script names verbatim; section words differ.
    case "$kw:$f" in
      troubleshoot:*RU*) continue ;;
    esac
    if grep -qi -- "$kw" "$f"; then ok "$f covers $kw"; else bad "$f misses $kw"; fi
  done
done

section "4. installation guide and common problems"
for f in docs/INSTALL.md docs/INSTALL-RU.md; do
  if grep -q '^## .*Troubleshoot\|^## .*Проблемы\|^## .*не так\|^## .*типичн' "$f"; then ok "$f has a troubleshooting section"; else bad "$f has no troubleshooting section"; fi
done

section "4a. the one-command installer is documented"
has README.md "scripts/install.sh"
has README-RU.md "scripts/install.sh"
if grep -q '^## Quick install' docs/INSTALL.md; then ok "EN install guide has the quick install"; else bad "EN install guide misses the quick install"; fi
if grep -q '^## Быстрая установка' docs/INSTALL-RU.md; then ok "RU install guide has the quick install"; else bad "RU install guide misses the quick install"; fi
has AGENTS.md "is the one-command installer"

section "5. information for AI agents"
has AGENTS.md "Rules that must not be broken"
has AGENTS.md "The DNS scheme"
has AGENTS.md "The node filters"
has AGENTS.md "Before you commit"
has AGENTS.md "The domain normalizer must accept hyphens"
if grep -q '^12\.' AGENTS.md; then ok "AGENTS.md has the hyphen rule"; else bad "AGENTS.md missing rule 12"; fi

section "6. the new apply step is documented"
for f in docs/INSTALL.md docs/INSTALL-RU.md AGENTS.md; do
  if grep -qi 'apply-rulesets' "$f"; then ok "$f mentions apply-rulesets"; else bad "$f misses apply-rulesets"; fi
done

summary

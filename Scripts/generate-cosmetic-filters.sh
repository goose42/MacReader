#!/bin/sh
# Usage: Scripts/generate-cosmetic-filters.sh
# Downloads the Fanboy Annoyance and EasyList Cookie lists (both CC BY 3.0, https://easylist.to/pages/licence.html) and
# keeps their generic element-hiding rules, which the HTML extraction hides before it looks for the article.
# GPL lists (uBlock Origin, AdGuard) are deliberately not used.
set -e
root="$(cd "$(dirname "$0")/.." && pwd)"
kit="$root/MacReaderKit/Sources/MacReaderKit"
work="$(mktemp -d)"

curl -sfL https://secure.fanboy.co.nz/fanboy-annoyance.txt -o "$work/fanboy-annoyance.txt"
curl -sfL https://secure.fanboy.co.nz/fanboy-cookiemonster.txt -o "$work/fanboy-cookiemonster.txt"

swiftc -swift-version 6 "$kit/HTML/CosmeticFilterParser.swift" "$root/Scripts/GenerateCosmeticFilters/main.swift" -o "$work/generate"
"$work/generate" "$kit/Resources/HTML/cosmetic-filters.json" "$work/fanboy-annoyance.txt" "$work/fanboy-cookiemonster.txt"

cat > "$kit/Resources/HTML/COSMETIC-FILTERS-NOTICE.txt" <<NOTICE
cosmetic-filters.json is derived from:
  Fanboy's Annoyance List      https://secure.fanboy.co.nz/fanboy-annoyance.txt     (CC BY 3.0)
  Fanboy's Cookie Monster List https://secure.fanboy.co.nz/fanboy-cookiemonster.txt (CC BY 3.0)
Only generic element-hiding rules were kept. Downloaded $(date -u +%Y-%m-%d). Regenerate with Scripts/generate-cosmetic-filters.sh.
NOTICE

#!/bin/bash
# Token-Router Pricing Refresh Script
# ======================================
# Checks freshness of pricing data and validates source URLs.
# Provides actionable report when prices may be outdated.
#
# Usage:
#   bash scripts/refresh-pricing.sh          # Normal check
#   bash scripts/refresh-pricing.sh --warn    # Exit 1 if outdated
#   bash scripts/refresh-pricing.sh --update  # Generate updated JSON (stub)
#
# Depends on: curl, python3

set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$SKILL_DIR/version.json"
REPORT_FILE="$SKILL_DIR/evals/pricing-report.json"
EXIT_CODE=0
STALE_DAYS=30

echo "============================================"
echo " Token-Router Pricing Refresh Check"
echo "============================================"
echo ""

# ---- Step 1: Read version.json ----
if [ ! -f "$VERSION_FILE" ]; then
    echo "FAIL: version.json not found at $VERSION_FILE"
    exit 1
fi

LAST_UPDATED=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['last_updated'])" 2>/dev/null)
echo "[1/4] Last pricing update: $LAST_UPDATED"

# Calculate age in days (macOS compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
    UPDATED_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_UPDATED" "+%s" 2>/dev/null || echo "0")
else
    UPDATED_EPOCH=$(date -d "$LAST_UPDATED" "+%s" 2>/dev/null || echo "0")
fi
NOW_EPOCH=$(date "+%s")
DAYS_OLD=$(( (NOW_EPOCH - UPDATED_EPOCH) / 86400 ))

if [ "$DAYS_OLD" -gt "$STALE_DAYS" ]; then
    echo "  WARN: Pricing data is $DAYS_OLD days old (threshold: $STALE_DAYS days)"
    echo "  Recommendation: Update model pricing before relying on cost estimates."
    EXIT_CODE=1
else
    echo "  OK: Pricing data is $DAYS_OLD days old (within $STALE_DAYS day threshold)"
fi
echo ""

# ---- Step 2: Check pricing source URLs ----
echo "[2/4] Checking pricing source URLs..."
URLS=$(python3 -c "
import json
with open('$VERSION_FILE') as f:
    data = json.load(f)
sources = data.get('pricing_sources', {})
for name, url in sources.items():
    print(f'{name}|{url}')
" 2>/dev/null)

URL_RESULTS=()
while IFS='|' read -r name url; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 8 "$url" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
        echo "  OK: $name -> $url ($HTTP_CODE)"
        URL_RESULTS+=("{\"source\":\"$name\",\"url\":\"$url\",\"status\":\"reachable\",\"http_code\":$HTTP_CODE}")
    else
        echo "  WARN: $name -> $url (HTTP $HTTP_CODE — may require manual check)"
        URL_RESULTS+=("{\"source\":\"$name\",\"url\":\"$url\",\"status\":\"unreachable\",\"http_code\":$HTTP_CODE}")
        EXIT_CODE=1
    fi
done <<< "$URLS"
echo ""

# ---- Step 3: Check model-tier data consistency ----
echo "[3/4] Checking reference pricing files for stale data..."
MODEL_TIERS_FILE="$SKILL_DIR/references/model-tiers.md"
if [ -f "$MODEL_TIERS_FILE" ]; then
    # Check for "$/MTok" price references - just verify they exist
    PRICE_LINES=$(grep -c '\$[0-9]\+\.[0-9]\+' "$MODEL_TIERS_FILE" 2>/dev/null || echo "0")
    echo "  Price entries found in model-tiers.md: $PRICE_LINES"
    if [ "$PRICE_LINES" -lt 10 ]; then
        echo "  WARN: model-tiers.md has fewer than 10 price entries, may be incomplete"
        EXIT_CODE=1
    else
        echo "  OK: Sufficient pricing data"
    fi
fi
echo ""

# ---- Step 4: Generate freshness report ----
echo "[4/4] Generating pricing freshness report..."
REPORT=$(python3 -c "
import json, datetime

report = {
    'check_timestamp': datetime.datetime.now().isoformat(),
    'last_updated': '$LAST_UPDATED',
    'age_days': $DAYS_OLD,
    'stale_threshold_days': $STALE_DAYS,
    'is_stale': $DAYS_OLD > $STALE_DAYS,
    'url_checks': [$(IFS=,; echo "${URL_RESULTS[*]}")],
    'recommendations': []
}
if $DAYS_OLD > $STALE_DAYS:
    report['recommendations'].append({
        'action': 'update_pricing',
        'priority': 'high',
        'message': f'Pricing data is {$DAYS_OLD} days old. Visit each pricing source URL to verify current prices.'
    })
if any(u['status'] == 'unreachable' for u in report['url_checks']):
    report['recommendations'].append({
        'action': 'verify_urls',
        'priority': 'medium',
        'message': 'Some pricing source URLs are unreachable. Check if URLs have changed.'
    })
print(json.dumps(report, indent=2))
" 2>/dev/null)

echo "$REPORT" > "$REPORT_FILE"
echo "  Report saved to $REPORT_FILE"
echo ""

# ---- Summary ----
echo "============================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo " RESULT: PRICING IS FRESH"
else
    echo " RESULT: ACTION RECOMMENDED (review above)"
fi
echo "============================================"
exit $EXIT_CODE

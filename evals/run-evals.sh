#!/bin/bash
# Token-Router Eval Runner
# Usage: bash evals/run-evals.sh
# 
# Validates structural integrity of the skill and generates a manual test checklist.
# Actual LLM-based eval requires running the skill in Trae or another agent framework.
#
# Dependencies: jq (optional, for JSON validation), python3
# Pricing check: requires curl (optional, for URL verification)

set -e

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EVALS_FILE="$SKILL_DIR/evals/evals.json"
SKILL_FILE="$SKILL_DIR/SKILL.md"
VERSION_FILE="$SKILL_DIR/version.json"
EXIT_CODE=0

echo "============================================"
echo " Token-Router Eval Runner v3.0"
echo "============================================"
echo ""

# ---- Step 1: Check version.json ----
echo "[1/6] Checking version.json..."
if [ ! -f "$VERSION_FILE" ]; then
    echo "  FAIL: version.json not found"
    EXIT_CODE=1
else
    VERSION=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['version'])" 2>/dev/null || echo "unknown")
    SMM=$(python3 -c "import json; print(json.load(open('$VERSION_FILE'))['smm_level'])" 2>/dev/null || echo "unknown")
    echo "  OK: version=$VERSION smm_level=$SMM"
fi
echo ""

# ---- Step 2: Validate evals.json ----
echo "[2/6] Validating evals.json..."
if ! python3 -c "
import json

with open('$EVALS_FILE') as f:
    data = json.load(f)

evals = data['evals']
print(f'  Total test cases: {len(evals)}')

for e in evals:
    eid = e['id']
    has_prompt = bool(e.get('prompt'))
    has_output = bool(e.get('expected_output'))
    has_expectations = len(e.get('expectations', [])) >= 3
    status = 'OK' if (has_prompt and has_output and has_expectations) else 'SHORT'
    print(f'  [{status}] eval #{eid}: prompt={len(e.get(\"prompt\",\"\"))}chars, {len(e.get(\"expectations\",[]))} expectations')

# Check for duplicate IDs
ids = [e['id'] for e in evals]
dupes = [i for i in ids if ids.count(i) > 1]
if dupes:
    print(f'  FAIL: Duplicate IDs: {set(dupes)}')
    exit(1)
"
then
    echo "  FAIL: evals.json validation error"
    EXIT_CODE=1
fi
echo ""

# ---- Step 3: Check SKILL.md sections ----
echo "[3/6] Checking SKILL.md required sections..."
REQUIRED_SECTIONS=(
    "复杂度评估"
    "安全检查"
    "用户偏好"
    "路由方式选择"
    "输出格式"
    "推荐修正流程"
    "平台集成指引"
    "多 Agent 编排架构"
    "Runtime 主动监控"
    "自修复闭环"
    "进阶成本优化"
)

for section in "${REQUIRED_SECTIONS[@]}"; do
    if grep -q "$section" "$SKILL_FILE" 2>/dev/null; then
        echo "  OK: Section '$section' found"
    else
        echo "  FAIL: Section '$section' missing"
        EXIT_CODE=1
    fi
done
echo ""

# ---- Step 4: Check reference files ----
echo "[4/6] Checking reference files..."
REFS=(
    "references/model-tiers.md"
    "references/routing-strategies.md"
    "references/config-templates.md"
)
for ref in "${REFS[@]}"; do
    if [ -f "$SKILL_DIR/$ref" ]; then
        SIZE=$(wc -c < "$SKILL_DIR/$ref" | tr -d ' ')
        echo "  OK: $ref ($SIZE bytes)"
    else
        echo "  FAIL: $ref missing"
        EXIT_CODE=1
    fi
done
echo ""

# ---- Step 5: Check pricing source URLs (optional) ----
echo "[5/6] Checking pricing source URLs (optional)..."
URLS=$(python3 -c "
import json
with open('$VERSION_FILE') as f:
    data = json.load(f)
sources = data.get('pricing_sources', {})
for name, url in sources.items():
    print(f'{name}|{url}')
" 2>/dev/null)

if command -v curl &>/dev/null; then
    while IFS='|' read -r name url; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 8 "$url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
            echo "  OK: $name -> $url ($HTTP_CODE)"
        else
            echo "  WARN: $name -> $url (HTTP $HTTP_CODE — may require manual check)"
        fi
    done <<< "$URLS"
else
    echo "  SKIP: curl not available, skipping URL checks"
    echo "  Sources to verify manually:"
    while IFS='|' read -r name url; do
        echo "    - $name: $url"
    done <<< "$URLS"
fi
echo ""

# ---- Step 6: Manual test checklist ----
echo "[6/6] Manual test checklist (run in Trae/Agent):"
echo "------------------------------------------------"
echo "| ID | Scenario                          | Expected Tier        |"
echo "------------------------------------------------"
echo "| 1  | Cost reduction request            | L0-L3 breakdown       |"
echo "| 2  | Security code review              | L2+ (force)           |"
echo "| 3  | Hermes Agent config               | L0/L1/L2 split        |"
echo "| 4  | Simple translation                | L0-L1                 |"
echo "| 5  | Batch sentiment analysis          | L0 + Batch API        |"
echo "| 6  | GEO/AI search content strategy    | L2+ quality           |"
echo "| 7  | Repeated translation cost         | Cache strategy        |"
echo "| 8  | Real-time chatbot (EN)            | L0-L1 speed           |"
echo "| 9  | Self-healing: repeated rejection  | L2 + healing report   |"
echo "| 10 | Session monitoring report         | Dashboard + health    |"
echo "| 11 | Recommendation correction         | Tier adjustment + log |"
echo "------------------------------------------------"
echo ""

# ---- Summary ----
echo "============================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo " RESULT: ALL CHECKS PASSED"
else
    echo " RESULT: SOME CHECKS FAILED (review above)"
fi
echo "============================================"
exit $EXIT_CODE

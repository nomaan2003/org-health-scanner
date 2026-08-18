#!/bin/bash
set -e

THRESHOLD=${1:-50}
ORG_ALIAS=${2:-ci}

echo "Running Org Health Scan (threshold: $THRESHOLD)..."

OUTPUT=$(sf apex run --file scripts/apex/qualityGate.apex --target-org "$ORG_ALIAS" --json)

# Unescape the JSON string (turns \" into ", \\n into a literal newline marker we can grep)
UNESCAPED=$(echo "$OUTPUT" | sed 's/\\"/"/g')

RESULT_LINE=$(echo "$UNESCAPED" | grep -o 'QUALITY_GATE_RESULT: {[^}]*}')

if [ -z "$RESULT_LINE" ]; then
    echo "ERROR: Could not find QUALITY_GATE_RESULT in Apex log output"
    echo "$OUTPUT"
    exit 1
fi

echo "Found result: $RESULT_LINE"

HEALTH_SCORE=$(echo "$RESULT_LINE" | grep -o '"healthScore":[0-9.]*' | cut -d':' -f2)

echo "Health Score: $HEALTH_SCORE"
echo "Threshold: $THRESHOLD"

if awk "BEGIN {exit !($HEALTH_SCORE < $THRESHOLD)}"; then
    echo "❌ QUALITY GATE FAILED: Health score $HEALTH_SCORE is below threshold $THRESHOLD"
    exit 1
else
    echo "✅ QUALITY GATE PASSED: Health score $HEALTH_SCORE meets threshold $THRESHOLD"
    exit 0
fi
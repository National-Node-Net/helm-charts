#!/bin/bash
# Test template rendering for all deployment scenarios

CHART_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$CHART_DIR"

echo "========================================"
echo "Helm Chart Render Tests"
echo "========================================"
echo ""

PASSED=0
FAILED=0

# Test scenarios: name:values_files (comma-separated)
SCENARIOS=(
  "local-bcc:values/overrides/local/secrets.yaml,values/overrides/local/bcc.yaml"
  "local-env:values/overrides/local/secrets.yaml,values/overrides/local/env.yaml"
  "local-heg:values/overrides/local/secrets.yaml,values/overrides/local/heg.yaml"
  "local-gcp:values/overrides/local/secrets.yaml,values/overrides/local/gcp.yaml"
  "dev-bcc:values/overrides/dev/bcc.yaml"
  "dev-env:values/overrides/dev/env.yaml"
  "dev-heg:values/overrides/dev/heg.yaml"
  "dev-gcp:values/overrides/dev/gcp.yaml"
)

test_scenario() {
  local name="$1"
  local files="$2"
  
  echo "Testing: $name"
  echo "----------------------------------------"
  
  # Build values args
  local values_args=""
  IFS=',' read -ra FILE_ARRAY <<< "$files"
  for f in "${FILE_ARRAY[@]}"; do
    if [ -f "$f" ]; then
      values_args="$values_args -f $f"
    else
      echo "  ⚠️  File not found: $f"
    fi
  done
  
  # Attempt template render
  local output
  local exit_code=0
  output=$(helm template test . \
    -f values/common-values.yaml \
    -f values/kafka.yaml \
    -f values/valkey.yaml \
    -f values/vault.yaml \
    -f values/certificate-manager.yaml \
    -f values/opa.yaml \
    -f values/federator.yaml \
    -f values/kafka-ui.yaml \
    -f values/valkey-ui.yaml \
    -f values/istio.yaml \
    $values_args \
    2>&1) || exit_code=$?
  
  if [ $exit_code -ne 0 ]; then
    echo "  ❌ FAIL: Template rendering failed"
    echo "     Error: $output" | head -5
    return 1
  fi
  
  echo "  ✅ Template renders successfully"
  
  # Validation checks
  local checks_passed=0
  local checks_total=0
  
  # Check 1: No 'spring.kafka.' properties in ConfigMaps (old Strimzi format)
  ((checks_total++))
  if echo "$output" | grep -q "spring.kafka."; then
    echo "  ❌ Found deprecated 'spring.kafka.' properties"
  else
    echo "  ✅ No deprecated 'spring.kafka.' properties"
    ((checks_passed++))
  fi
  
  # Check 2: Kafka bootstrap servers are set
  ((checks_total++))
  if echo "$output" | grep -q "kafka.bootstrapServers="; then
    echo "  ✅ Kafka bootstrap servers configured"
    ((checks_passed++))
  else
    echo "  ❌ Kafka bootstrap servers not found"
  fi
  
  # Check 3: Redis/Valkey host is set
  ((checks_total++))
  if echo "$output" | grep -q "redis.host="; then
    echo "  ✅ Redis/Valkey host configured"
    ((checks_passed++))
  else
    echo "  ❌ Redis/Valkey host not found"
  fi
  
  # Check 4: Management node URL is set
  ((checks_total++))
  if echo "$output" | grep -q "management.node.base.url="; then
    echo "  ✅ Management node URL configured"
    ((checks_passed++))
  else
    echo "  ❌ Management node URL not found"
  fi
  
  echo ""
  echo "  Checks: $checks_passed/$checks_total passed"
  
  if [ $checks_passed -eq $checks_total ]; then
    echo "  ✅ All checks passed"
    return 0
  else
    echo "  ⚠️  Some checks failed"
    return 1
  fi
}

# Run all scenarios
for scenario in "${SCENARIOS[@]}"; do
  name="${scenario%%:*}"
  files="${scenario#*:}"
  
  if test_scenario "$name" "$files"; then
    ((PASSED++))
    echo "✅ PASS: $name"
  else
    ((FAILED++))
    echo "❌ FAIL: $name"
  fi
  echo ""
done

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "Total:  $((PASSED + FAILED))"
echo ""

if [ $FAILED -eq 0 ]; then
  echo "✅ All tests passed!"
  exit 0
else
  echo "❌ Some tests failed"
  exit 1
fi

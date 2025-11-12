#!/bin/bash
# Survey language spec compilation errors

echo "Surveying language spec compilation errors..."
echo "============================================="
echo

for spec in rubyspec/language/*.rb; do
  name=$(basename "$spec")
  # Skip specs that are known to pass
  if [[ "$name" == "versions_spec.rb" || "$name" == "fixtures" ]]; then
    continue
  fi

  result=$(./run_rubyspec "$spec" 2>&1 | head -50)

  if echo "$result" | grep -q "✓ Compiled successfully"; then
    status="PASS"
    error=""
  elif echo "$result" | grep -q "Compilation failed"; then
    status="FAIL"
    error=$(echo "$result" | grep -E "Parse error|Syntax error|Missing value|undefined method" | head -1 | sed 's/^.*: //')
  else
    status="CRASH"
    error=$(echo "$result" | grep -E "Error|Exception" | head -1)
  fi

  printf "%-35s %s\n" "$name" "$status"
  if [[ -n "$error" && ${#error} -lt 100 ]]; then
    printf "  └─ %s\n" "$error"
  fi
done

#!/bin/bash
# Analyze compilation errors across all language specs to find most common blockers

echo "Analyzing compilation errors in language specs..."
echo ""

cd rubyspec/language || exit 1

# Collect all first errors
for spec in *.rb; do
    timeout 2 ../../compile "$spec" -I ../.. 2>&1 | \
        grep -E "Parse error|Compiler error|Expected:" | \
        head -1 | \
        sed "s|$spec.*||" # Remove file-specific parts
done > /tmp/all_errors.txt 2>&1

# Count unique error patterns
echo "=== Top 15 Most Common Error Patterns ==="
cat /tmp/all_errors.txt | \
    sed 's/:[0-9]*:[0-9]*/:[LINE]:[COL]/g' | \  # Normalize line/col numbers
    sed 's/\x1b\[[0-9;]*m//g' | \               # Remove ANSI codes
    sort | uniq -c | sort -rn | head -15

echo ""
echo "=== Total specs analyzed: $(ls *.rb | wc -l) ==="
echo "=== Total errors collected: $(wc -l < /tmp/all_errors.txt) ==="

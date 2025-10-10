#!/bin/bash
SPEC_FILE="$1"
SPEC_NAME=$(basename "$SPEC_FILE" .rb)
TEMP_SPEC="rubyspec_temp_${SPEC_NAME}.rb"

# Create temporary spec
echo "require 'rubyspec_helper'" > "$TEMP_SPEC"
echo "" >> "$TEMP_SPEC"

# Inline spec content, removing require_relative lines
grep -v "require_relative" "$SPEC_FILE" >> "$TEMP_SPEC"

# Add runner
echo "" >> "$TEMP_SPEC"
echo 'SpecRunner.new.run_specs' >> "$TEMP_SPEC"

# Compile
TEMP_SPEC_NAME="rubyspec_core_integer_${SPEC_NAME}"
ruby -I. ./driver.rb "$TEMP_SPEC" -I . 2>&1 > "out/${TEMP_SPEC_NAME}.s"
if [ $? -ne 0 ]; then
    echo "Compilation failed"
    exit 1
fi

gcc -m32 -g -o "out/${TEMP_SPEC_NAME}" "out/${TEMP_SPEC_NAME}.s" tgc.c -lm
if [ $? -ne 0 ]; then
    echo "Assembly failed"
    exit 1
fi

# Run with gdb
timeout 10 gdb -batch -ex "run" -ex "where" -ex "info registers" -ex "quit" "out/${TEMP_SPEC_NAME}" 2>&1

# Cleanup
rm -f "$TEMP_SPEC"

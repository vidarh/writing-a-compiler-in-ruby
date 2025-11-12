#!/bin/bash
cd rubyspec/language
for spec in *.rb; do
  timeout 5 ../../compile "$spec" -I ../.. > /dev/null 2>&1
  case $? in
    0) echo "PASS: $spec" ;;
    124) echo "TIMEOUT: $spec" ;;
    *) echo "COMPILE_FAIL: $spec" ;;
  esac
done

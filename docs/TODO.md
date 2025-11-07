# Ruby Compiler TODO

**Purpose**: Outstanding tasks only. See KNOWN_ISSUES.md for bug details.

## Current Tasks

### FIRST: Assess Current State
- [ ] Run fresh RubySpec tests (integer + language)
- [ ] Document current pass rates and failure patterns
- [ ] Identify highest-impact next tasks

### After Assessment
- [ ] Fix control flow as expressions (architectural blocker - 5+ specs)
- [ ] Fix toplevel constant paths (`class ::Foo` - reverted feature)
- [ ] Fix ternary operator bug (`false ? x : y` returns `false`)
- [ ] Investigate Integer::MIN corruption (-1073741824 corrupts during selftest-c)
- [ ] Improve Float support (currently stubs only)
- [ ] Fix remaining integer spec failures (shifts, power/multiplication)
- [ ] Eigenclass (class << obj) support - very complex

## Testing

```bash
make selftest        # Must pass (1 expected failure)
make selftest-c      # Must pass (1 expected failure)
./run_rubyspec rubyspec/core/integer/    # Integer specs
./run_rubyspec rubyspec/language/         # Language specs
```

## References

- **WORK_STATUS.md** - Current work journal
- **DEBUGGING_GUIDE.md** - Debugging techniques
- **ARCHITECTURE.md** - System architecture
- **RUBYSPEC_INTEGRATION.md** - How to run specs

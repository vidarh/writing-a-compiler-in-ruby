# Full Marshal via dynamic-ivar reflection — implementation plan

*The ongoing job (user, 2026-07-09): "full Marshal is required for this performance work to be
complete." The custom AST serializer ([[docs/coremarshal-ast/FINDINGS.md]]) is a TEMPORARY bridge;
the destination is `pure_ruby_marshal` ported into lib/core, which needs the reflection below.*

Step order (user-mandated): enable the temp cache → **fix reflection prerequisites** → implement
full Marshal → sweep the Marshal specs → resume other perf work.

## The core gap

Ivar slots are assigned STATICALLY at compile time (`ModuleScope#find_ivar_offset` =
`@ivaroff + @instance_vars.index(name)`) and never emitted to runtime. So `object.rb`'s
`instance_variable_get/set/instance_variables/defined?` are lossy stubs (get→nil, set→no-op).
`pure_ruby_marshal` needs real versions plus `const_get` / `allocate` / `send` (send + allocate
already exist; const_get has runtime forms in kernel.rb).

## Design (NO class-object layout change)

Adding a class metadata slot is a documented bootstrap hazard (class.rb:1-9: CLASS_IVAR_NUM=6 and
scattered hardcoded `(index ob N)` uses all shift together). So DO NOT touch layout. Instead:

1. **Compiler emits a static per-class ivar table at output time** (model: `output_vtable_names`,
   compiler.rb:1804). After all classes are parsed (ivars are only final post-parse, classcope.rb:37),
   walk `@classes`; for each ClassScope emit triples into one flat static table:

   ```
   __ivar_table:                         # each row = 3 longs
     .long <fqname_cstr>                 # strconst of the class fq-name (identity key)
     .long <ivar_name_cstr>              # strconst of "@foo" (WITH the @, MRI convention)
     .long <raw_offset>                  # RAW machine int slot index (usable by (index self off))
     ... one row per (class, ivar) ...
   __ivar_table_rows: .long <N>
   ```

   Key by the class **fq-name cstr**, NOT a class-object pointer: class objects are runtime-allocated
   (`__new_class_object`) so their addresses aren't known at static-data-emission time; the `.bss` cell
   under the class name only holds the pointer after init. But each class object's slot 2 (`@name`) IS
   set to the fq-name cstr at class setup (compile_class.rb:745 `[:assign,[:index,:self,2],fq_name.to_s]`,
   read back by `Class#name` via `__get_string`), and string constants are interned. So the runtime
   match is: `cls_name_cstr = (index (index obj 0) 2)` compared (strcmp, or pointer-eq if interned)
   against the row's fqname_cstr. `cscope.name` at emit time must equal that fq_name — verify with a
   probe. Emit the FULL inherited set per class (walk superclass chain) so a subclass row-set is
   self-contained. Offsets are RAW (`.long 6`) so `(index self off)` consumes them directly (raw index,
   like `(index @ptr @len)` in array.rb:521).

2. **lib/core lookup** (new, e.g. in object.rb or a dedicated reflection.rb):
   ```ruby
   # returns raw offset, or -1 if absent
   %s(defun __ivar_offset (obj name_cstr) ...
      walk __ivar_table rows; row class == (index obj 0)? and strcmp(row ivar, name_cstr)==0 -> return off
      return -1)
   ```
   Then:
   ```ruby
   def instance_variable_get(name)
     nm = name.to_s                       # accept :@x or "@x"
     %s(assign off (__ivar_offset self (callm nm __get_raw)))
     %s(if (lt off 0) (return nil))
     %s(index self off)                   # raw off -> the slot value (already a tagged Ruby object)
   end
   def instance_variable_set(name, value)
     nm = name.to_s
     %s(assign off (__ivar_offset self (callm nm __get_raw)))
     raise NameError... if off<0            # MRI raises on a bad ivar name; but marshal only sets known ones
     %s(assign (index self off) value)
     value
   end
   def instance_variables
     # collect names whose row class == self.class from __ivar_table; return [:@a, :@b, ...]
   end
   def instance_variable_defined?(name); !instance_variable_get(name).nil? end  # approx; refine
   ```

   Caveats to verify during implementation:
   - Slot value returned by `(index self off)` is already a tagged Ruby object (ivars store tagged
     values) — confirm no re-tagging needed.
   - `instance_variables` must return only SET ivars in MRI; our slots always exist. Marshal only
     needs the declared set, so returning all declared names is acceptable initially; refine if a
     spec distinguishes unset (slot == nil/0) — skip raw-0 slots.
   - `@__class__` (slot 0 for Object) and class-metadata ivars must be EXCLUDED from the user-visible
     ivar table (they are machinery, not user ivars). Emit only ivars whose name the user wrote
     (i.e. `@instance_vars` minus `:@__class__`, and for Class exclude the 6 metadata names).
   - Name convention: MRI ivar names include the `@`. Store WITH `@` and normalise input via `to_s`.

3. **Port pure_ruby_marshal** (github.com/vidarh/pure_ruby_marshal, ~816 lines) into lib/core,
   swapping its `instance_variable_get/set`, `instance_variables`, `const_get`, `allocate`, `send`,
   `marshal_dump`/`marshal_load` onto the now-real reflection. Wire `Marshal.dump`/`Marshal.load`.

4. **Then** the temp AST cache (COREMARSHAL) can be re-expressed via real `Marshal` (or kept if the
   custom serializer stays faster — but full Marshal is the correctness baseline). Sweep
   core/marshal/{dump,load,restore}_spec (~401/451/451 fails) as the payoff.

## pure_ruby_marshal API inventory (what the port actually calls)

Fetched from github.com/vidarh/pure_ruby_marshal (lib/pure_ruby_marshal/{read,write}_buffer.rb).
Requires `pure_ruby_marshal/version`, `.../read_buffer`, `.../write_buffer`.

- **write_buffer** needs: `instance_variables`, `instance_variable_get`, `respond_to?(:_dump/:marshal_dump/:b)`,
  `.class`, `.class.name`, `to_sym`/`to_s`/`to_h`, String `<<`, `.chr`. Byte output = String concat.
- **read_buffer** needs: `Object.const_get`, `klass.allocate`, `instance_variable_set`, `extend`,
  `marshal_load`, `klass._load`, `klass.members` (Struct), `instance_of?`. Byte input = `data.unpack("C*")` + `shift`.

Status after this task: `instance_variables` / `instance_variable_get` / `instance_variable_set` are
now REAL (done here). ALL other prerequisites CONFIRMED PRESENT in lib/core (2026-07-09):
`const_get` (class.rb:232, so `Object.const_get` resolves), `allocate` (class.rb:160), `extend`
(object.rb:734), `respond_to?` (object.rb:266), `members` (struct.rb:200 / data.rb:63), `unpack`
(string.rb:2142), `chr` (string.rb:407), `String#<<` (string.rb:1269). So the port is now mostly a
straight copy of the two buffers + a `Marshal` module wrapper (`Marshal.dump`/`.load` + MAJOR/MINOR).
Watch: pure_ruby_marshal deliberately drops encodings/Regexp (mruby target) — fine here.

## Port probe results (2026-07-09) — compiler idiom support for the port

Verified working in the compiler: `unpack("C*")`, `Integer#times.map`, `inject`, `tap`, `object_id`
(stable), `Hash#values_at`, `String#<<`, `Integer#chr`, `Array#shift`, `Float::INFINITY`, `nan?`.
Two gaps to work around in marshal.rb:
- **`"\b"` string escape is NOT backspace** (yields literal 'b' = 98, not 8). Build the `"\x04\b"`
  Marshal header via `4.chr + 8.chr`, never the escape literal.
- **`2**30` is a broken bignum boundary** (`(2**30).class` returns the value, not Integer; bignum path
  is fragile — see [[compiler_bignum_heap_multiply_bug]]). Handle fixnum-range integers correctly and
  STUB bignum (`'l'` type) initially; most marshal specs use small ints. Don't compute `2**30` at
  runtime for the fixnum/bignum boundary; use a fixnum-safe test.

Port increment plan: write path (dump) for nil/bool/int(fixnum)/string/symbol/array/hash/float/
object-with-ivars first, round-trip-tested against MRI `Marshal.dump`; then read path (load); then
edge cases (bignum, Regexp, _dump/marshal_dump, object/symbol link caches). Commit + gate each slice.

## Gates (every step)
`make selftest` + `make selftest-c` Fails:0; `bash tools/crash_battery.sh` on ax52; then a full
ax52 sweep to confirm no CRASH/COMPILE_FAIL regression. Reflection touches object.rb (a foundational
file) so de-stubbing may unmask latent bugs ([[compiler_stub_masks_latent_bugs]]) — expect wobble,
triage under `setarch -R`, guard repros in test/repros/battery/.

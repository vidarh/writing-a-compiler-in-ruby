# Regression guard for the per-slot (generation) devirtualisation model in type_inference.rb.
#
# The old analysis marked a whole class "dynamic" the moment it used attr_reader/attr_accessor/define_method,
# which bailed devirt on ALL of that class's methods -- including ordinary static `def`s. The generation
# model instead advances only the SPECIFIC slot a reflective helper defines (resolved from a
# `%s(__compiler_internal type_effect ...)` pragma at the helper's definition), leaving the class's other
# slots single-generation and devirtualizable.
#
# Run under MRI:  ruby -I . test/devirt_generation_test.rb

require 'type_inference'

$fails = 0
def check(desc, got, want)
  if got == want
    puts "PASS: #{desc}"
  else
    puts "FAIL: #{desc} -- got #{got.inspect}, want #{want.inspect}"
    $fails += 1
  end
end

# Post-rewrite-shaped tree (symbol literals appear as [:sexp, :__S_name]; the effect pragma as a
# [:__compiler_internal, :type_effect, kind, arg-index] sexp in the helper body).
def s_sym(name) = [:sexp, "__S_#{name}".to_sym]
def effect(kind, i) = [:sexp, [:__compiler_internal, :type_effect, kind, i]]

# class Class; def attr_accessor(sym); <pragmas>; end; def define_method(sym); <pragma>; end; end
core = [:class, :Class, :Object, [
  [:defm, :attr_accessor, [:sym], [effect(:defines_slot, 0), effect(:defines_slot_eq, 0)]],
  [:defm, :define_method, [:sym], [effect(:defines_slot, 0)]],
]]

# class Foo; attr_accessor :y; def bar; 1; end; end; f = Foo.new; f.bar; f.y
bar_call = [:callm, :f, :bar]
y_call   = [:callm, :f, :y]
foo = [:class, :Foo, :Object, [
  [:call, :attr_accessor, [s_sym(:y)]],
  [:defm, :bar, [], [1]],
]]
prog = [:do, core, foo, [:assign, :f, [:callm, :Foo, :new]], bar_call, y_call]

ti = TypeInference.new
ti.analyze(prog)

# The whole thing must not collapse to "no devirt anywhere".
check("dyn_global stays false with a resolvable attr_accessor", ti.instance_variable_get(:@dyn_global), false)
# attr_accessor :y advanced exactly slots (Foo,:y) and (Foo,:y=), nothing else.
dyn = ti.instance_variable_get(:@dyn_slot)
check("attr_accessor advanced slot (Foo,:y)",  dyn[[:Foo, :y]],  true)
check("attr_accessor advanced slot (Foo,:y=)", dyn[[:Foo, :"y="]], true)
check("attr_accessor did NOT advance slot (Foo,:bar)", dyn[[:Foo, :bar]], nil)
# The ordinary static method devirtualises to Foo; the accessor slot does not (dynamically installed).
check("Foo#bar devirtualises despite attr_accessor", ti.devirt_decision({ :Foo => true }, :bar), :Foo)
check("Foo#y (accessor slot) does not devirtualise", ti.devirt_decision({ :Foo => true }, :y), nil)

# A dynamic-name define_method in a class body -> that name is unresolvable -> the class is unknowable, so its
# static methods bail (sound); an unrelated class is unaffected.
dyn_prog = [:do, core,
  [:class, :Baz, :Object, [
    [:call, :define_method, [:some_var]],   # bare var arg -> dynamic name
    [:defm, :qux, [], [1]],
  ]],
  [:class, :Quux, :Object, [[:defm, :qux, [], [1]]]],
]
ti2 = TypeInference.new
ti2.analyze(dyn_prog)
check("dynamic define_method makes Baz unknowable", ti2.instance_variable_get(:@unknowable)[:Baz], true)
check("Baz#qux bails (unknowable class)", ti2.devirt_decision({ :Baz => true }, :qux), nil)
check("Quux#qux still devirtualises (unaffected)", ti2.devirt_decision({ :Quux => true }, :qux), :Quux)

puts $fails == 0 ? "\nDONE\nFails: 0" : "\nDONE\nFails: #{$fails}"
exit($fails == 0 ? 0 : 1)

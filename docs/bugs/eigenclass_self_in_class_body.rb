# Minimal deterministic repro (run with ASLR off: `setarch -R ./out/<bin>`) for the
# `class << self` heap corruption (issue #8, method_missing_spec cluster).
#
# `class << self` inside a CLASS/MODULE body installs its singleton methods via
# __set_vtable(:self, off, fn). But :self inside the eigenclass body resolves to a
# WRONG stack slot (a bare 4-byte Object.new-style instance) instead of the metaclass,
# so __set_vtable writes a method pointer at slot `off` (~783) far past the 4-byte
# object -> clobbers an adjacent malloc header -> "free(): invalid next size" at the
# next GC. `def obj.x` on a top-level LOCAL works (no enclosing ClassScope), so the bug
# is specific to the eigenclass's let(:self) offset when nested in a class/module body.
class M
  class << self
    def zqzq1() 1 end
    def zqzq2() 2 end
    def zqzq3() 3 end
  end
end
puts M.zqzq1



# The purpose of this scope is mainly to prevent
# (call foo) in an escaped s-expression from being
# rewritten to (callm self foo) when inside a class
# definition - this rewrite is ok for non-escaped
# code, but for embedded s-expressions the purpose
# is to have explicit control  over the low level
# constructs
class SexpScope < Scope
  def initialize(next_scope)
    @next = next_scope
  end

  def method
    @next ? @next.method : nil
  end

  def rest?
    @next.rest?
  end

  def lvaroffset
    0
  end

  # @FIXME This works only due to a quirk of Ruby:
  # `arg` may not be an `Array`. If `arg` is a number,
  # then `arg.[]` returns the value of the bit specified
  # by the index. Since this returns 1 or 0, it will
  # never match `:possible_callm` so the code works,
  # but smells...
  def get_arg(a)
    arg = @next.get_arg(a)
    if arg[0] == :possible_callm
      arg[0] = :addr
    end
    arg
  end

  # Delegate to next scope to find ClassScope/ModuleScope
  def class_scope
    if @next
      return @next.class_scope
    end
    return self
  end
end

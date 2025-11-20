
# Used to provide the label that "break" should exit to.

class ControlScope < Scope
  def initialize n, b, l
    @break_label = b
    @loop_label  = l
    super n
  end

  def break_label
    @break_label || super
  end

  def loop_label
    @loop_label || super
  end

  # Delegate to next scope to check for rest arguments
  def rest?
    @next ? @next.rest? : false
  end

  # Delegate to next scope to find ClassScope/ModuleScope
  def class_scope
    if @next
      return @next.class_scope
    end
    return self
  end
end

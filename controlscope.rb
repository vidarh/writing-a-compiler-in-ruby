
# Used to provide the label that "break" should exit to. 

class ControlScope < Scope
  def initialize n, b
    @break_label = b
    super n
  end

  def break_label
    @break_label || super
  end
end


class Kernel
  def puts s
    %s(puts (index s 1))
  end
end

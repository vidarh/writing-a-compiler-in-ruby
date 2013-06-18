
class Fixnum < Integer

  def initialize
    %s(assign @value 0)
  end

  def __set_raw(value)
    @value = value
  end

  def __get_raw
    @value
  end

  def + other
    %s(call __get_fixnum ((add @value (callm other __get_raw))))
  end

  def - other
    %s(call __get_fixnum ((sub @value (callm other __get_raw))))
  end

  def <= other

  end

  def == other

  end

  def < other

  end

  def > other

  end

  def >= other

  end

  def div other
  end

  def mul other
    %s(call __get_fixnum ((mul @value (callm other __get_raw))))
  end

  # These two definitions are only acceptable temporarily,
  # because we will for now only deal with integers

  def * other
    mul(other)
  end

  def / other
    div(other)
  end
  
end


%s(defun __get_fixnum (val) (let (num)
  (assign num (callm Fixnum new))
  (callm num __set_raw (val))
  num
))

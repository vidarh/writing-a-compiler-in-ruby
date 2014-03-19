
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

  def to_s
    %s(let (buf)
       (assign buf (malloc 16))
       (snprintf buf 16 "%ld" @value)
       (__get_string buf)
       )
  end

  def chr
   %s(let (buf)
       (assign buf (malloc 2))
       (snprintf buf 2 "%c" @value)
       (__get_string buf)
       )
  end

  def + other
    %s(call __get_fixnum ((add @value (callm other __get_raw))))
  end

  def - other
    %s(call __get_fixnum ((sub @value (callm other __get_raw))))
  end

  def <= other
    %s(le @value (callm other __get_raw))
  end

  def == other
    %s(eq @value (callm other __get_raw))
  end

  def != other
    %s(ne @value (callm other __get_raw))
  end

  def < other
    %s(lt @value (callm other __get_raw))
  end

  def > other
    %s(gt @value (callm other __get_raw))
  end

  def >= other
    %s(ge @value (callm other __get_raw))
  end

  def div other
    %s(call __get_fixnum ((div @value (callm other __get_raw))))
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


class Fixnum < Integer

  def initialize
    # Can't use a Ruby expression here, because it
    # would cause infinite recursion. Well, run out
    # of memory.
    %s(assign @value 0)
  end

  def % other
#    %s(printf "%i\n" (callm other __get_raw))
    %s(assign r (callm other __get_raw))
    %s(assign m (mod @value r))
    %s(if (eq (ge m 0) (lt r 0))
         (assign m (add m r)))
    %s(__get_fixnum m)
  end

  def __set_raw(value)
    @value = value
  end

  def __get_raw
    @value
  end

  def to_i
    self
  end

  # FIXME
  # Bit access
  def [] i
    1
  end
  def to_s(radix=10)
    if radix == 10
      %s(assign buf (malloc 16))
      %s(snprintf buf 16 "%ld" @value)
      %s(__get_string buf)
    elsif radix < 2 || radix > 36
      STDERR.puts "ERROR: Invalid radix #{radix.inspect} - must be between 2 and 36"
      1/0
    else
      out = ""
      n = self
      digits = "0123456789abcdefghijklmnopqrstuvwxyz"
      while n != 0
        r = n % radix
        out << digits[r]
        break if n < radix
        n = n / radix
      end
      if out.empty?
        out = "0"
      end
      out.reverse
    end
  end

  def hash
    self
  end

  def inspect
    to_s
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
    %s(if (le @value (callm other __get_raw)) true false)
  end

  def == other
    if other.nil?
      return false 
    end
    return false if !other.is_a?(Numeric)
    %s(if (eq @value (callm other __get_raw)) true false)
  end

  # FIXME: I don't know why '!' seems to get an argument...
  def ! *args
    false
  end

  def != other
    return true if !other.is_a?(Numeric)
    other = other.to_i
    %s(if (ne @value (callm other __get_raw)) true false)
  end

  def < other
    %s(if (lt @value (callm other __get_raw)) true false)
  end

  def > other
    %s(if (gt @value (callm other __get_raw)) true false)
  end

  def >= other
    %s(if (ge @value (callm other __get_raw)) true false)
  end

  def <=> other
    return nil if !other.is_a?(Numeric)
    if self > other
      return 1
    end
    if self < other
      return -1
    end
    return 0
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

  def ord
    self
  end
  
  def times
    i = 0
    while i < self
      yield
      i +=1
    end
  end
end


%s(defun __get_fixnum (val) (let (num)
  (assign num (callm Fixnum allocate))
  (callm num __set_raw (val))
  num
))

# IO non-blocking mode accessors (normally backed by fcntl O_NONBLOCK).
class IO
  def nonblock?
    @nonblock ? true : false
  end

  def nonblock=(bool)
    @nonblock = bool ? true : false
  end

  def nonblock(bool = true)
    @nonblock = bool ? true : false
    self
  end
end

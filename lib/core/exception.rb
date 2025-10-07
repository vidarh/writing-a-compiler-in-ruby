
class Exception
end

class StandardError < Exception
end

class TypeError < StandardError
end

class NoMethodError
end

class ArgumentError
end

class FrozenError
end

class RangeError
end

class ZeroDivisionError < StandardError
end

class RuntimeError < StandardError
end

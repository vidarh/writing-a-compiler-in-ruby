
STDIN  = IO.new(0)
STDOUT = IO.new(1)
STDERR = IO.new(2)

$stdin = STDIN
$stdout = STDOUT
$stderr = STDERR

# Special I/O globals with meaningful defaults ($/ is the input record separator, "\n"). Others default
# to nil (the nil-init handles that); set the non-nil ones here.
$/ = "\n"
$\ = nil
$, = nil
$; = nil

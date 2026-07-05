# Guards the return-in-ensure compiler bug: a `return` inside an ensure clause made compile_return
# re-enter the same ensure via @ensure_stack and recurse forever (language/ensure_spec COMPILE_FAIL).
# A return in an ensure supersedes the pending return and runs only enclosing ensures.
def m; return 1; ensure; return 2; end
p m            # 2

def n; return 3; ensure; 99; end
p n            # 3

def o
  begin
    return 5
  ensure
    return 6
  end
ensure
  7
end
p o            # 6

def q; return 8; ensure; nil; end
p q            # 8

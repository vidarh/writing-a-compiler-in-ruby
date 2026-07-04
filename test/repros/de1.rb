# def with a DEFAULT ARG and an ensure clause: the bare [:block, args, stmts,
# rescue, ensure] defm body must survive rewrite_default_args.
# Expected output:
#   body 1
#   cleanup
#   body 5
#   cleanup
def f(a = 1)
  puts "body #{a}"
ensure
  puts "cleanup"
end
f
f(5)

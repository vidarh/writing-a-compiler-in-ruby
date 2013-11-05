
def foo
%s(let (a b c foobar)
   (assign foobar 5)
   (assign a 2)
   (assign b 5)
   (assign c 10)

   (assign a (add a b))

   (assign a (add a c))
   (assign a (mul a 2))

   (printf "a = %d\n" a)
   (printf "b = %d\n" b)
   (printf "c = %d\n" c)

   (assign a (add a 1))

   (printf "a = %d\n" a)
   (printf "b = %d\n" b)
   (printf "c = %d\n" c)

)
end

foo

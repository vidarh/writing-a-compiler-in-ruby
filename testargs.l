
def f test, *arr
%s(assign i 0)
%s(while (lt i (sub numargs 1)) 
	(do
	 (printf "test=%ld, i=%ld, numargs=%ld, arr[i]=%ld\n" test i numargs (index arr i))
	 (assign i (add i 1))
	 )
	)
end

def g i, j
%s(let (k)
	(assign k 42)
	(printf "numargs=%ld, i=%ld,j=%ld,k=%ld\n" numargs i j k)
	)
end

%s(f 123 42 43 45)
%s(g 23 67)

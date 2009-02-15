
%s(defun f (test (arr rest)) 
	(let (i)
	  (assign i 0)
	  (while (lt i (sub numargs 1)) 
		(do
			(printf "test=%ld, i=%ld, numargs=%ld, arr[i]=%ld\n" test i numargs (index arr i))
			(assign i (add i 1))
		  )
		)
	  )
	)

%s(defun g (i j)
	(let (k)
	  (assign k 42)
	  (printf "numargs=%ld, i=%ld,j=%ld,k=%ld\n" numargs i j k)
	  )
	)

%s(f 123 42 43 45)
%s(g 23 67)

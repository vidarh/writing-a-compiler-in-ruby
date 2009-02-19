
def f test, *arr
  %s(assign i 0)
  while %s(lt i (sub numargs 1))
    %s(printf "test=%ld, i=%ld, numargs=%ld, arr[i]=%ld\n" test i numargs (index arr i))
    %s(assign i (add i 1))
  end
end

def g i, j
  %s(assign k 42)
  %s(printf "numargs=%ld, i=%ld,j=%ld,k=%ld\n" numargs i j k)
end

%s(f 123 42 43 45)
%s(g 23 67)

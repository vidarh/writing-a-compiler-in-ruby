
def f test, *arr
  i = 0
  while i < (numargs - 1)
    printf("test=%ld, i=%ld, numargs=%ld, arr[i]=%ld\n",test,i,numargs,arr[i]))
    i = i + 1
  end
end

def g i, j
  k = 42
  printf("numargs=%ld, i=%ld,j=%ld,k=%ld\n",numargs,i,j,k)
end

f(123,42,43,45)
g(23,67)

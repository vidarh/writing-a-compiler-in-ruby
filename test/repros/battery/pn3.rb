def m2
  [1].each { [2].each { return :deep } }
  :no
end
p m2

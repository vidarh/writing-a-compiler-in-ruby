def pick(x)
  case x
  when 1
    r = :one
  when 2
    r = :two
  else
    q = :other
  end
  [r, q]
end
p pick(1)
p pick(9)

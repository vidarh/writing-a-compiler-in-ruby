def run
  yield
end

run do
  case [0, 1]
  in [a, 1] if a >= 0
    puts "matched #{a}"
  end
end

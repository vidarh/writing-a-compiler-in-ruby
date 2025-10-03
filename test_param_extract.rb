params_raw = [[:a, :rest], :b, :c]
param_names = params_raw.collect { |p| p.is_a?(Array) ? p[0] : p }
puts param_names.inspect

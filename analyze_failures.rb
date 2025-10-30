# Analyze spec_failures.txt to categorize failure types
failures = File.read("spec_failures.txt")

categories = {
  float_related: [],
  type_error: [],
  coerce: [],
  infinity: [],
  comparison: [],
  other: []
}

current_spec = nil
failures.each_line do |line|
  if line =~ /\[FAIL\] (.*?)\.rb/
    current_spec = $1
  elsif current_spec && line =~ /P:(\d+) F:(\d+)/
    passed = $1.to_i
    failed = $2.to_i
    categories[:float_related] << current_spec if current_spec =~ /(fdiv|to_f)/
    categories[:type_error] << current_spec if current_spec =~ /type/i
    categories[:coerce] << current_spec if current_spec =~ /coerce/
    categories[:comparison] << current_spec if current_spec =~ /comparison|cmp|gte|lte|gt|lt/
  end
end

puts "Failure Categories:"
categories.each do |cat, specs|
  puts "  #{cat}: #{specs.length} specs" if specs.length > 0
  specs.each { |s| puts "    - #{s}" }
end

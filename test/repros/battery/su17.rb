class K; end
def check
  K.send(:define_method, :a) do |arg|
    super
  end
  begin
    p K.new.a(:x)
  rescue => e
    puts "#{e.class}: #{e.message}"
  end
end
check
puts "done"

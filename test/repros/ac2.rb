require_relative '../rubyspec_helper'
it "x" do
  [-1, +1, nil, "s"].each do |result|
    lhs = Array.new(3) { mock("#{result}") }
    rhs = Array.new(3) { mock("#{result}") }
    lhs[0].should_receive(:<=>).with(rhs[0]).and_return(0)
    lhs[1].should_receive(:<=>).with(rhs[1]).and_return(result)
    (lhs <=> rhs).should == result
  end
end
puts "done"

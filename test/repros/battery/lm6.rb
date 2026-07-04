require 'rubyspec_helper'
def run_specs
describe("A method send") do
  context "with a single splatted Object argument" do
    before :all do
      def m(a) a end
    end
    it "raises a TypeError if #to_a does not return an Array" do
      x = mock("splat argument")
      x.should_receive(:to_a).and_return(1)
      -> { m(*x) }.should raise_error(TypeError)
    end
  end
end
end
run_specs
print_spec_results

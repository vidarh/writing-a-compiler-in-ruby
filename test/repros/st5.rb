require_relative '../rubyspec_helper'
it "contained" do
  a = [3, 1, 2]
  begin
    class Integer
      alias old_ss <=>
      def <=>(other)
        raise
      end
    end
    a.sort {|n, m| (n - m) }.should == [1, 2, 3]
  ensure
    class Integer
      alias <=> old_ss
    end
  end
end
puts "done"

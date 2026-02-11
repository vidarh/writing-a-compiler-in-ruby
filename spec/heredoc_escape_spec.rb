require_relative '../rubyspec/spec_helper'

describe "Heredoc escape sequences" do
  describe "basic escapes in interpolated heredocs" do
    it "converts \\n to LF" do
      s = <<HERE
a\nb
HERE
      s.should == "a\nb\n"
    end

    it "converts \\t to TAB" do
      s = <<HERE
a\tb
HERE
      s.should == "a\tb\n"
    end

    it "converts \\\\ to single backslash" do
      s = <<HERE
a\\b
HERE
      s.should == "a\\b\n"
    end

    it "converts \\e to ESC (0x1B)" do
      s = <<HERE
\e[31m
HERE
      s.should == "\e[31m\n"
    end

    it "converts \\r to CR" do
      s = <<HERE
a\rb
HERE
      s.should == "a\rb\n"
    end
  end

  describe "line continuation" do
    it "joins lines with backslash-newline" do
      s = <<HERE
ab\
cd
HERE
      s.should == "abcd\n"
    end
  end

  describe "interaction with interpolation" do
    it "prevents interpolation with \\#" do
      x = "nope"
      s = <<HERE
\#{x}
HERE
      s.should == "\#{x}\n"
    end

    it "handles escapes and interpolation together" do
      val = "world"
      s = <<HERE
hello\t#{val}\n
HERE
      s.should == "hello\tworld\n\n"
    end
  end

  describe "single-quoted heredocs" do
    it "preserves backslashes literally" do
      s = <<'HERE'
a\nb\tc\\d
HERE
      s.should == "a\\nb\\tc\\\\d\n"
    end
  end

  describe "squiggly heredocs" do
    it "processes \\n in <<~ heredoc" do
      s = <<~HERE
        a\nb
      HERE
      s.should == "a\nb\n"
    end
  end

  describe "edge cases" do
    it "handles \\\\ before newline without triggering line continuation" do
      s = <<HERE
trail\\
HERE
      s.should == "trail\\\n"
    end

    it "passes through unknown escape sequences" do
      s = <<HERE
\q\z
HERE
      s.should == "qz\n"
    end

    it "handles multiple consecutive escape sequences" do
      s = <<HERE
\t\t\n\\
HERE
      s.should == "\t\t\n\\\n"
    end
  end
end

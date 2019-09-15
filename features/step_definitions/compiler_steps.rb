$: << File.expand_path(File.dirname(__FILE__)+"/../..")
require 'compiler'
#require 'spec/expectations'
require 'tempfile'
require 'pathname'

# The rest is shared with the shunting yard steps

When /^I compile it$/ do
  @parser = Parser.new(@scanner,{:norequire => true})
  @ptree = @parser.parse
  @aout = ArrayOutput.new
  @emitter = Emitter.new(@aout)
  @emitter.basic_main = true
  @compiler = Compiler.new(@emitter)
  @compiler.compile(@ptree)
  @tree = @aout.output
end

Then /^the output should match(.*)$/ do |f|
  @output.to_s.should == File.read("outputs/"+@src.split(".")[0]+".txt")
end

Then /^the output should be (.*)$/ do |tree|
  @tree.should == eval(tree)
end


Given /^the source file (.*)$/ do |f|
  @src = f
end

When /^I compile it and run it$/ do
  Dir.chdir((Pathname.new(File.dirname(__FILE__)) + "../..").to_s) do
    Tempfile.open('ruby-compiler') do |tmp|
      src = "inputs/#{@src}"
      raise "Input '#{src}' does not exist" if !File.exists?("features/#{src}")
      cmd = "ruby -I. driver.rb features/#{src} >#{tmp.path}.s 2>#{tmp.path}"
      `#{cmd}`
      Tempfile.open('ruby-compiler') do |exe|
#        STDERR.puts "Asm file is in #{tmp.path}.s"
        system("gcc 2>#{tmp.path} -m32 -gstabs -o #{exe.path}-binary #{tmp.path}.s out/tgc.o")
        @output = `echo test | #{exe.path}-binary`
      end
    end
  end
end

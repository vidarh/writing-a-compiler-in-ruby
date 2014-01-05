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

Then /^the output should match (.*)$/ do |f|
  @output.to_s.should == File.read(f)
end

Then /^the output should be (.*)$/ do |tree|
  @tree.should == eval(tree)
end


Given /^the source file (.*)$/ do |f|
  @src = f #@scanner = Scanner.new(File.open(f,"r"))
end

When /^I compile it and run it$/ do
  Dir.chdir((Pathname.new(File.dirname(__FILE__)) + "../..").to_s) do
    Tempfile.open('ruby-compiler') do |tmp|
      `ruby compiler.rb features/#{@src} >#{tmp.path}.s 2>#{tmp.path}`
      Tempfile.open('ruby-compiler') do |exe|
        STDERR.puts "Asm file is in #{tmp.path}.s"
        `gcc -gstabs -o #{exe.path}-binary #{tmp.path}.s ./runtime.o`
        @output = `echo test | #{exe.path}-binary`
      end
    end
  end
end

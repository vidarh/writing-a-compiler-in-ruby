
require 'compilererror'
require 'compiler'

  dump = ARGV.include?("--parsetree")
  norequire = ARGV.include?("--norequire") # Don't process require's statically - compile them instead
  trace = ARGV.include?("--trace")
  stackfence = ARGV.include?("--stackfence")
  transform = !ARGV.include?("--notransform")
  nostabs = ARGV.include?("--nostabs")
  dumpsymtabs = ARGV.include?("--dumpsymtabs")
  type_ast = ARGV.include?("--type-ast")

  # Option to not rewrite the parse tree (breaks compilation, but useful for debugging of the parser)
  OpPrec::TreeOutput.dont_rewrite if ARGV.include?("--dont-rewrite")


  # Process remaining arguments
  #
  # If a filename is not given, read from STDIN.
  input_source = STDIN
  include_paths = []

  while arg = ARGV.shift
     if arg[0..1] == "-I"
       if arg == "-I"
        path = ARGV.shift
      else
        path = arg[2..-1]
      end

       include_paths << path
     elsif arg == "-g" # Implemented in ./compile
     elsif arg[0..1] == "--"

     elsif File.exist?(arg)
       input_source = File.open(arg, "r")
     else
       STDERR.puts "No such file or argument: '#{arg}'"
       exit(1)
     end
  end

  s = Scanner.new(input_source)
  prog = nil

  begin
    parser = Parser.new(s, {:norequire => norequire, :include_paths => include_paths})
    t_parse = Time.now
    prog = parser.parse
    STDERR.puts "[time] parse: %.3fs" % (Time.now - t_parse) if ENV["COMPILER_TIME"]
  rescue CompilerError => e
    STDERR.puts e.message
    exit(1)
  end
  
  if prog
    begin
      e = Emitter.new
      e.debug == nil if nostabs

      c = Compiler.new(e)
      c.trace = true if trace
      c.stackfence = true if stackfence

      t_preprocess = Time.now
      c.preprocess(prog) if transform
      STDERR.puts "[time] preprocess: %.3fs" % (Time.now - t_preprocess) if ENV["COMPILER_TIME"] && transform

      if dump || dumpsymtabs
        print_sexp prog if dump
        c.global_scope.dump if dumpsymtabs
        exit(0)
      end

      if type_ast
        require 'type_inference'
        ti = TypeInference.new
        ti.analyze(prog)
        ti.dump(prog)
        exit(0)
      end

      t_compile = Time.now
      c.compile(prog)
      STDERR.puts "[time] compile: %.3fs" % (Time.now - t_compile) if ENV["COMPILER_TIME"]
    rescue CompilerError => e
      STDERR.puts e.message
      exit(1)
    end
  end


exit(0)

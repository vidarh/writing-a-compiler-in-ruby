

  dump = ARGV.include?("--parsetree")
  norequire = ARGV.include?("--norequire") # Don't process require's statically - compile them instead
  trace = ARGV.include?("--trace")
  stackfence = ARGV.include?("--stackfence")
  transform = !ARGV.include?("--notransform")
  nostabs = ARGV.include?("--nostabs")

  # Option to not rewrite the parse tree (breaks compilation, but useful for debugging of the parser)
  OpPrec::TreeOutput.dont_rewrite if ARGV.include?("--dont-rewrite")


  # check remaining arguments, if a filename is given.
  # if not, read from STDIN.
  input_source = STDIN
  ARGV.each do |arg|
    if File.exists?(arg)
      input_source = File.open(arg, "r")
      STDERR.puts "reading from file: #{arg}"
      break
    end
  end

  s = Scanner.new(input_source)
  prog = nil
  
  begin
    parser = Parser.new(s, {:norequire => norequire})
    prog = parser.parse
  rescue Exception => e
    STDERR.puts "#{e.message}"
    # FIXME: The position ought to come from the parser, as should the rest, since it could come
    # from a 'require'd file, in which case the fragment below means nothing.
    STDERR.puts "Failed at line #{s.lineno} / col #{s.col} / #{s.filename}  before:\n"
    buf = ""
    while s.peek && buf.size < 100
      buf += s.get
    end
    STDERR.puts buf
  end
  
  if prog
    e = Emitter.new
    e.debug == nil if nostabs

    c = Compiler.new(e)
    c.trace = true if trace
    c.stackfence = true if stackfence

    c.preprocess(prog) if transform

    if dump
      print_sexp prog
      exit
    end
    
    c.compile(prog)
  end



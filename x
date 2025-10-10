This is a copout. Your next task is to fix the rational parsing *properly*. It should 
  1) fix it in the tokenizer. Then 2) rewrite to [:call, :Rational, [first num, second 
  num]]. The tokenizer *must* handle the full <number>/<number>r in one go, and must 
  unget up to before / if it doesn't find the final r.

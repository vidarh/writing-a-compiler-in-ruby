
# Writing a (Ruby) compiler in Ruby

Source for my series on writing a compiler in Ruby.

See <http://www.hokstad.com/compiler>

**NOTE** This is still wildly incomplete. 

## Status as of April 27th 2019

The AST transformation steps now succeeds up to and including `rewrite_operators`, which means only `rewrite_let_env` is currently failing.
However `rewrite_let_env` is a complicated mess, and also one I've been changing as part of the GC work, so might use this point to commit
and wrap up my GC article before I fix this bug. Once this bug is fixed, the next step is to get the actual code generation step working.

## Status as of April 24th 2019

This is *all new* as of April, as I finally started playing with it again:

 * When compiling the compiler with itself with a slightly modified driver, it successfully parses all of itself and produces identical output to when run under MRI. This does not mean the parse is complete (it absolutely is not), or bug free - it means the parser acts correctly on the very specific subset of expressions currently present in the compiler itself.
 * The AST transformation steps (in transform.rb) up to but not including `rewrite_strcont` gives identical results under the compiler itself and MRI, the differences for the remaining four rewrites appears to be down to bugs/missing pieces in the standard library rather than the compiler itself (but we'll see).
 * Status of the bootstrapped compilers ability to run the code generation step is currently largely unknown; I believe it likely to fail and need fixes, but I don't get a realistic test until the transform steps all work, however experience bringing the parser and transform steps up suggests most bugs at this point are missing pieces in the standard library, which are generally quick to fix, rather than bugs in the code generation itself, so I expect getting this to work to be fairly quick.
 
 * Compiling the compiler with itself under MRI produces a binary that runs through a substantial portion of the full compilation, but eventually does fail.
 
 * I have a GC under preparation (it is working, but I need to put some effort into cleaning things up); **A new blog post or two that covers integration of the GC is coming as a continuation of the original series**

Assuming I get time to continue current progress, the compiler should fully compile itself and the compiled version should be able to compile itself by summer.
Before getting too excited about trying to use it for other things, however, note:

 * The compiler itself carefully avoids known missing functionality, and/or I work around some during testing the bootstrap. The big ones:
   * ARGV (used by the compiler; when testing bootstrapping I currently hardcode options)
   * Exceptions (used by the compiler, but only begin/rescue causes problems and that's only used once; commented out for testing)
   * Regexp (not used by the compiler)
   * Float (not used by the compiler)
 * The compiler code is littered with workarounds for specific bugs (they're not consistently marked, but `FIXME` will include all of the workarounds for compiler bugs and more).
 * The GC mentioned above is very simple and not well suited for the sheer amount of objects currently allocated. It needs a number of improvements to handle many small objects, and the compiler needs additional work to reduce the number of objects created.

Once the compiler is bootstrapped w/workarounds, my next steps are:

 * Add support for for ARGV
 * Add support for exceptions (prob. worth a blog post)
 * Go through the current FIXME's and explicitly check which are still relevant (some have likely been fixed as a result of other bug fixes); add test cases, and fix them in turn.
 * Make [mspec](https://github.com/ruby/mspec) compile
 * Make [the Ruby Spec Suite](https://github.com/ruby/spec) run, and cry over how large parts of it will fail.
 * Some of the GC improvements mentioned above.


## Caveats

This section covers caveats about compiled Ruby vs. MRI, not
generally missing pieces or bugs in the current state of the
compiler (of which there are many).

### require

Presently, "require" is evaluated statically at compile time.

This makes certain Ruby patterns hard or impossible to support.
E.g. reading the contents of a directory and caling "require"
for each .rb file found will not presently work, and may never
work, as it is not clear in the context of compilation whether
or not the intent is to load this file at compile time or runtime.

Ruby allows the argument to "require" to be dynamically generated.
E.g. "require File.dirname(__FILE__) + '/blah'". To facilitate
compatibility, limited forms of this pattern may eventually
be supported.

On MRI, "require" is generally overridden by a custom version
for rubygems or bundler. This is not likely to ever be
supported. "require" is likely to be treated as a keyword,
rather than as an overrideable method.


### $0

While `$0` will at some point be initialized with the name of
the file compilation is triggered for, certain patterns of
Ruby, such as conditionally executing code based on whether
a given file is executed directly are conceptually different,
given that $0 gets bound at *compile time*.

We'll need to consider if the right behaviour is for `$0` and/or
`__FILE__` to contain the equivalent of C's `argv[0]` instead.
Possibly make `$0` and `__FILE__` refer to different things.


### $:, $LOAD_PATH

The load path is malleable in MRI, and this is very frequently
used alongside certain methods to modify which files may be
loaded. Currently this is not supported.

It is likely that for compatibility a limited subset of Ruby
will be *interpreted* at compile time to support some forms
of this pattern. See also "require"

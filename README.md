
# Writing a (Ruby) compiler in Ruby

Source for my series on writing a compiler in Ruby.

See <http://www.hokstad.com/compiler>

**NOTE** This is still wildly incomplete.

## Status as of September 15th 2019

(see commit history for README.md for past updates; I will consolidate this regularly to be current
state only)

 * The bootstrapped compiler will now generate a full parse for the
   selftest. There are minor differences down to compiler bugs:
   * the last entry of the `Operators` hash does not get output.
   * The argument to `STDERR.puts` in `expect_dquoted` gets parsed as false
     (I believe the bug causing this is already captured as a testcase)
   * Most of the other differences appears to be caused by the same issue
     as the bug causing problems in `expect_quoted`.
   * Next focus is to weed out the above, and then attempt to get the
     selftest to run after compilation by the bootstrapped compiler,
     and then collate and find test-cases covering the 30+ places in the
     compiler currently annotated with @bug, as they're likely also affecting
     other parts of the compiler.

 * Garbage collector is integrated; garbage collection article nearly done.
 * ARGV works, and as a result the separate bootstrap version of the compiler driver is
   obsolete.
 * The "hello world" compiled with the bootstrapped/compiled compiler now *runs* and the
   compiled source is identical if care is taken about filesystem paths.
 * This includes a number of ugly workarounds for compiler bugs that have
   not been nailed down yet. I'm trying to ensure sites of known workarounds
   for bugs in the compiler are marked with `@bug`.
 * Current biggest problem is actually reducing garbage collection overhead
   as compiling even a minimal hello world takes several minutes, so the next
   few rounds of changes might be focused on that. A few easy wins, and avenues
   to investigate:
     * Pre-create objects for all constants (numeric and string in particular,
       as symbols are already looked up; symbols would cut code size, but not
       do anything for GC). String would require supporting the frozen string
       constant pragma to do it *safely*
     * Ensure all objects that can be allocated as leaves are.
     * Currently Proc and env objects are created separately; might be worth
       allocating the env as part of the Proc object, but not sure it's worthwhile
     * Capture stats on number of allocated objects per class, and output,

 * When compiling the compiler with itself it successfully parses all of itself
 and produces identical output to when run under MRI. This does not mean the
 parse is complete (it absolutely is not), or bug free - it means the parser
 acts correctly on the very specific subset of expressions currently present
 in the compiler itself.

Assuming I get time to continue current progress, the compiler might fully compile
itself and the compiled version might be able to compile itself this autumn.

(to make that clear, what I want to get to is:

 1. Run the compiler source with MRI on its own source to produce a "compiler1" that is a native i386 binary
 2. Run "compiler1" with its own source as input to produce a "compiler2"
 3. Run "compiler2" with its own source as input to produce a "compiler3"

Currently step 1 "works" to the extent that it produces a binary, but that binary has bugs, and so
fails to produce a compiler2. To complete the bootstrap process I need it to complete the compile
and produce a binary, but I *also* need that binary to be correct. I can part-validate that by comparing
it to "compiler1" - they should have identical assembler source, but the best way of validating it
fully is to effectively repeat step 2, but with "compiler2" as the input, and verify that "compiler2"
and "compiler3" are identical, to validate the entire end-to-end process. This may seem paranoid,
but once step2 works the point is step3 *should* be trivial, so there's no point in not taking
that extra step.


### Before getting too excited about trying to use the compiler at the point when it bootstraps fully, note:

 * The compiler itself carefully avoids known missing functionality, and/or I work around some during testing the bootstrap. The big ones:
   * ARGV (used by the compiler; when testing bootstrapping I currently hardcode options)
   * Exceptions (used by the compiler, but only begin/rescue causes problems and that's only used once; commented out for testing)
   * Regexp (not used by the compiler)
   * Float (not used by the compiler)
 * The compiler code is littered with workarounds for specific bugs (they're not consistently marked, but `FIXME` will include all of the workarounds for compiler bugs and more, and whenever I find new ones they're also marked `@bug`).
 * The GC mentioned above is very simple and not well suited for the sheer amount
 of objects currently allocated. It needs a number of improvements to handle
 many small objects, and the compiler needs additional work to reduce the number of objects created.

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

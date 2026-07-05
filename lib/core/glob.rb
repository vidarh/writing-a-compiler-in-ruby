# Shared glob engine: File.fnmatch/fnmatch? and Dir.glob/Dir.[].
# Byte-oriented recursive matcher; brace alternatives are handled by EXPANSION
# (pattern -> list of brace-free patterns), used both for Dir.glob (always) and
# File.fnmatch with FNM_EXTGLOB.

class File
  # Recursive fnmatch over byte indices.
  def self.__fnmatch_r(pat, pi, str, si, flags)
    plen = pat.length
    slen = str.length
    pathname = (flags & FNM_PATHNAME) != 0
    dotmatch = (flags & FNM_DOTMATCH) != 0
    noescape = (flags & FNM_NOESCAPE) != 0
    casefold = (flags & FNM_CASEFOLD) != 0
    while pi < plen
      pc = pat[pi]
      if pc == 42                                     # '*'
        doublestar = false
        while pi < plen && pat[pi] == 42
          pi += 1
          doublestar = true if pi < plen && pat[pi] == 42
        end
        # A '*' at a component start cannot match a leading '.' (unless DOTMATCH).
        if si < slen && str[si] == 46 && !dotmatch
          at_start = si == 0
          at_start = true if si > 0 && str[si - 1] == 47
          if at_start
            # '*' contributes only the empty match here; the '.' must be
            # matched by a literal in the rest of the pattern.
            return __fnmatch_r(pat, pi, str, si, flags)
          end
        end
        k = si
        while true
          return true if __fnmatch_r(pat, pi, str, k, flags)
          break if k >= slen
          if pathname && !doublestar && str[k] == 47   # '*' stops at '/'
            return false if !__fnmatch_r(pat, pi, str, k, flags)
            return false
          end
          k += 1
        end
        return false
      elsif pc == 63                                  # '?'
        return false if si >= slen
        return false if pathname && str[si] == 47
        if str[si] == 46 && !dotmatch
          at_start = si == 0
          at_start = true if si > 0 && str[si - 1] == 47
          return false if at_start
        end
        pi += 1
        si += 1
      elsif pc == 91                                  # '['
        return false if si >= slen
        return false if pathname && str[si] == 47
        if str[si] == 46 && !dotmatch
          at_start = si == 0
          at_start = true if si > 0 && str[si - 1] == 47
          return false if at_start
        end
        r = __fnmatch_class(pat, pi, str[si], flags)
        return false if r.nil? || r[0] == 0
        pi = r[1]
        si += 1
      elsif pc == 92 && !noescape && pi + 1 < plen    # '\'
        return false if si >= slen
        return false if !__fnmatch_eq(pat[pi + 1], str[si], casefold)
        pi += 2
        si += 1
      else
        return false if si >= slen
        return false if !__fnmatch_eq(pc, str[si], casefold)
        pi += 1
        si += 1
      end
    end
    si == slen
  end

  def self.__fnmatch_eq(a, b, casefold)
    if casefold
      a += 32 if a >= 65 && a <= 90
      b += 32 if b >= 65 && b <= 90
    end
    a == b
  end

  # Parse a [...] class at pat[pi] ('[' position) and test byte c.
  # Returns [1-or-0, index-after-']'] or nil for an unterminated class.
  def self.__fnmatch_class(pat, pi, c, flags)
    plen = pat.length
    casefold = (flags & FNM_CASEFOLD) != 0
    i = pi + 1
    negate = false
    if i < plen && (pat[i] == 33 || pat[i] == 94)     # '!' / '^'
      negate = true
      i += 1
    end
    matched = 0
    first = true
    while i < plen && (pat[i] != 93 || first)         # ']' literal when first
      lo = pat[i]
      if lo == 92 && i + 1 < plen                     # escaped char in class
        i += 1
        lo = pat[i]
      end
      hi = lo
      if i + 2 < plen && pat[i + 1] == 45 && pat[i + 2] != 93   # 'a-z' range
        hi = pat[i + 2]
        i += 2
      end
      cc = c
      l2 = lo
      h2 = hi
      if casefold
        cc += 32 if cc >= 65 && cc <= 90
        l2 += 32 if l2 >= 65 && l2 <= 90
        h2 += 32 if h2 >= 65 && h2 <= 90
      end
      matched = 1 if cc >= l2 && cc <= h2
      i += 1
      first = false
    end
    return nil if i >= plen                           # unterminated
    if negate
      if matched == 1
        matched = 0
      else
        matched = 1
      end
    end
    [matched, i + 1]
  end

  # Expand ONE level of {a,b,...} alternatives (recursively) into a pattern list.
  def self.__brace_expand(pat)
    i = 0
    plen = pat.length
    depth = 0
    start = -1
    while i < plen
      c = pat[i]
      if c == 92                                       # skip escaped char
        i += 2
        next
      end
      if c == 123                                      # '{'
        start = i if depth == 0
        depth += 1
      elsif c == 125 && depth > 0                      # '}'
        depth -= 1
        if depth == 0
          prefix = pat[0, start].to_s
          suffix = pat[(i + 1) .. -1].to_s
          body = pat[start + 1, i - start - 1].to_s
          alts = []
          d2 = 0
          cur = ""
          j = 0
          while j < body.length
            bc = body[j]
            if bc == 123
              d2 += 1
              cur = cur + bc.chr
            elsif bc == 125
              d2 -= 1
              cur = cur + bc.chr
            elsif bc == 44 && d2 == 0                  # ','
              alts << cur
              cur = ""
            else
              cur = cur + bc.chr
            end
            j += 1
          end
          alts << cur
          out = []
          alts.each do |alt|
            __brace_expand(prefix + alt + suffix).each { |p| out << p }
          end
          return out
        end
      end
      i += 1
    end
    [pat]
  end

  def self.fnmatch(pattern, path, flags = 0)
    pattern = __coerce_path(pattern)
    path = __coerce_path(path)
    if (flags & FNM_EXTGLOB) != 0
      __brace_expand(pattern).each do |p|
        return true if __fnmatch_r(p, 0, path, 0, flags)
      end
      return false
    end
    __fnmatch_r(pattern, 0, path, 0, flags)
  end

  def self.fnmatch?(pattern, path, flags = 0)
    fnmatch(pattern, path, flags)
  end
end

class Dir
  # Dir.glob(pattern-or-list, flags=0, base: nil). Brace alternatives always
  # expand; matching is per path component with FNM_PATHNAME semantics; '**'
  # descends recursively. Results are sorted (MRI 3.x default).
  def self.glob(patterns, flags = 0, opts = nil, &block)
    if flags.is_a?(Hash) && opts.nil?
      opts = flags
      flags = 0
    end
    base = nil
    base = opts[:base] if opts.is_a?(Hash)
    pats = patterns
    pats = [patterns] if !patterns.is_a?(Array)
    out = []
    pats.each do |pat|
      pat = File.__coerce_path(pat)
      File.__brace_expand(pat).each do |p|
        __glob_one(p, flags, base, out)
      end
    end
    # dedupe + sort
    seen = {}
    res = []
    out.each do |p|
      if !seen.key?(p)
        seen[p] = true
        res << p
      end
    end
    res = res.sort
    if block
      res.each { |p| block.call(p) }
      return nil
    end
    res
  end

  def self.[](*patterns)
    glob(patterns)
  end

  def self.__glob_one(pat, flags, base, out)
    rooted = pat.length > 0 && pat[0] == 47
    start = "."
    start = base if !base.nil?
    start = "/" if rooted
    comps = []
    cur = ""
    i = 0
    i = 1 if rooted
    while i < pat.length
      if pat[i] == 47
        comps << cur if cur.length > 0
        cur = ""
      else
        cur = cur + pat[i].chr
      end
      i += 1
    end
    trailing_slash = pat.length > 0 && pat[pat.length - 1] == 47
    comps << cur if cur.length > 0
    prefix = ""
    prefix = "/" if rooted
    __glob_walk(start, prefix, comps, 0, flags, trailing_slash, out)
  end

  def self.__glob_walk(dir, prefix, comps, ci, flags, trailing_slash, out)
    if ci >= comps.length
      p = prefix
      p = "." if p.length == 0
      p = p + "/" if trailing_slash && p[p.length - 1] != 47
      out << p
      return
    end
    comp = comps[ci]
    if comp == "**"
      # zero directories
      __glob_walk(dir, prefix, comps, ci + 1, flags, trailing_slash, out)
      # or descend into each subdirectory
      entries = __glob_entries(dir)
      entries.each do |e|
        next if e == "." || e == ".."
        next if e.length > 0 && e[0] == 46 && (flags & File::FNM_DOTMATCH) == 0
        full = __glob_join(dir, e)
        if File.directory?(full)
          __glob_walk(full, __glob_join_prefix(prefix, e), comps, ci, flags, trailing_slash, out)
        end
      end
      return
    end
    if !__glob_has_meta?(comp)
      # literal component: stat directly (also matches dotfiles given literally)
      full = __glob_join(dir, comp)
      if ci + 1 >= comps.length
        if File.exist?(full) || File.directory?(full)
          __glob_walk(full, __glob_join_prefix(prefix, comp), comps, ci + 1, flags, trailing_slash, out)
        end
      elsif File.directory?(full)
        __glob_walk(full, __glob_join_prefix(prefix, comp), comps, ci + 1, flags, trailing_slash, out)
      end
      return
    end
    entries = __glob_entries(dir)
    entries.each do |e|
      next if e == "." || e == ".."
      next if !File.fnmatch(comp, e, flags | File::FNM_PATHNAME)
      full = __glob_join(dir, e)
      if ci + 1 >= comps.length
        __glob_walk(full, __glob_join_prefix(prefix, e), comps, ci + 1, flags, trailing_slash, out) if !trailing_slash || File.directory?(full)
      elsif File.directory?(full)
        __glob_walk(full, __glob_join_prefix(prefix, e), comps, ci + 1, flags, trailing_slash, out)
      end
    end
  end

  def self.__glob_has_meta?(comp)
    i = 0
    while i < comp.length
      c = comp[i]
      return true if c == 42 || c == 63 || c == 91
      i += 1
    end
    false
  end

  def self.__glob_entries(dir)
    begin
      Dir.entries(dir)
    rescue
      []
    end
  end

  def self.__glob_join(dir, e)
    return "/" + e if dir == "/"
    return e if dir == "."
    dir + "/" + e
  end

  def self.__glob_join_prefix(prefix, e)
    return e if prefix.length == 0
    return prefix + e if prefix == "/"
    prefix + "/" + e
  end
end

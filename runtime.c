
signed int not(signed int a)
{
  return !a;
}

// Note that our "and" won't shortcircuit, as the
// evaluation happens before this function is called.
signed int and(signed int a, signed int b)
{
  return a && b;
}


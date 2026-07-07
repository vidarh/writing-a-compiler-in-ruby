# Array#pack / String#unpack Float directives d D f F e E g G (IEEE-754 bytes of the double at
# offset 4). Uses ROUND-TRIP tests through pack's binary-safe strings (string LITERALS with \x00 are
# truncated by a separate pre-existing bug, so avoid them here). Verified vs MRI.
p([1.5].pack("d").bytes)                    # [0,0,0,0,0,0,248,63]
p([1.5].pack("G").bytes)                    # [63,248,0,0,0,0,0,0] (big-endian)
p([1.5].pack("f").bytes)                    # [0,0,192,63]
p([3.14].pack("E").unpack("E"))             # [3.14] round-trip
p([1.0,2.0,3.0].pack("d*").unpack("d*"))    # [1.0,2.0,3.0]
p([100.0].pack("g").unpack("g"))            # [100.0] single BE round-trip
p([2.5].pack("d").unpack("E"))              # [2.5] (d and E both LE double)

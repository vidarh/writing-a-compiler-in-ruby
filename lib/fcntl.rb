# fcntl(2) command and flag constants (Linux/x86 values).
module Fcntl
  F_DUPFD  = 0
  F_GETFD  = 1
  F_SETFD  = 2
  F_GETFL  = 3
  F_SETFL  = 4
  F_GETLK  = 5
  F_SETLK  = 6
  F_SETLKW = 7

  FD_CLOEXEC = 1

  O_RDONLY   = 0
  O_WRONLY   = 1
  O_RDWR     = 2
  O_ACCMODE  = 3
  O_CREAT    = 64
  O_EXCL     = 128
  O_NOCTTY   = 256
  O_TRUNC    = 512
  O_APPEND   = 1024
  O_NONBLOCK = 2048
  O_CLOEXEC  = 524288

  F_RDLCK = 0
  F_WRLCK = 1
  F_UNLCK = 2
end


# 
# Low level debugging tools
# 


%s(defun printregs (regs) (do
  (printf "eax: %08x, ebx: %08x, ecx: %08x, edx: %08x, esi: %08x, edi: %08x, ebp: %08x, esp: %08x\n"
   (index regs 0)
   (index regs 1)
   (index regs 2)
   (index regs 3)
   (index regs 4)
   (index regs 5)
   (index regs 6)
   (index regs 7))

  (assign sp (index regs 6))
  (printf "(ebp): %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x\n"
   (index sp 0)
   (index sp 1)
   (index sp 2)
   (index sp 3)
   (index sp 4)
   (index sp 5)
   (index sp 6)
   (index sp 7)
   (index sp 8)
   (index sp 9)
)

  (assign sp (index regs 7))
  (printf "(esp): %08x, %08x, %08x, %08x, %08x, %08x, %08x, %08x\n"
   (index sp 0)
   (index sp 1)
   (index sp 2)
   (index sp 3)
   (index sp 4)
   (index sp 5)
   (index sp 6)
   (index sp 7))

))

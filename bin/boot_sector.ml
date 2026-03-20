(* boot_sector.ml -- An x86 boot sector, defined entirely in OCaml.

   When a PC powers on, the BIOS loads the first 512 bytes of the
   boot disk to address 0x7C00 and jumps to it. That's ALL you get:
   512 bytes, 16-bit real mode, no OS, no libraries, no runtime.

   This program defines a bootloader as a list of OCaml values,
   assembles them into x86 machine code, and writes the result
   as a bootable disk image. The equivalent NASM would be ~30 lines;
   our OCaml is more verbose but the assembler checks everything
   at compile time. *)

open X86_asm.Types

(* ---- The boot sector program ----

   What it does:
   1. Set up segment registers (required for memory access)
   2. Initialize COM1 serial port (0x3F8) for output
   3. Point SI to our message string
   4. Print each character to BOTH VGA screen and serial port
   5. Halt the CPU forever

   With serial output, the bootloader works in headless mode too:
     qemu-system-i386 -drive format=raw,file=boot.img -nographic
   The message appears right in your terminal.

   I/O PORTS: x86 has a separate 64K address space for hardware.
   You talk to devices by reading/writing port numbers with IN/OUT.
   COM1 (first serial port) lives at ports 0x3F8-0x3FD. *)

let boot_program = [
  (* ---- Origin: BIOS loads us at 0x7C00 ---- *)
  Org 0x7C00;

  (* ---- Segment setup ----
     In real mode, memory access uses segment:offset addressing.
     Physical address = segment * 16 + offset.
     We zero all segments so offset = physical address (up to 64 KB).
     Disable interrupts during setup to avoid stack issues. *)
  Cli;
  Xor_r16_r16 (AX, AX);        (* AX = 0 *)
  Mov_seg_r16 (DS, AX);         (* data segment = 0 *)
  Mov_seg_r16 (ES, AX);         (* extra segment = 0 *)
  Mov_seg_r16 (SS, AX);         (* stack segment = 0 *)
  Mov_r16_imm (SP, Imm16 0x7C00); (* stack grows down from 0x7C00 *)
  Sti;                           (* re-enable interrupts *)

  (* ---- Initialize COM1 serial port ----
     The 8250/16550 UART has several registers at ports 0x3F8-0x3FD.
     We configure: 38400 baud, 8 data bits, no parity, 1 stop bit (8N1).

     UART register map (base = 0x3F8):
       +0  Data / Divisor Latch Low (when DLAB=1)
       +1  Interrupt Enable / Divisor Latch High (when DLAB=1)
       +2  FIFO Control
       +3  Line Control (bit 7 = DLAB)
       +4  Modem Control
       +5  Line Status (bit 5 = TX empty) *)

  Mov_r16_imm (DX, Imm16 0x3F9);   (* IER: Interrupt Enable Register *)
  Mov_r8_imm (AL, 0x00);            (* disable all UART interrupts *)
  Out_dx_al;

  Mov_r16_imm (DX, Imm16 0x3FB);   (* LCR: Line Control Register *)
  Mov_r8_imm (AL, 0x80);            (* set DLAB=1 to access baud divisor *)
  Out_dx_al;

  Mov_r16_imm (DX, Imm16 0x3F8);   (* DLL: Divisor Latch Low *)
  Mov_r8_imm (AL, 0x03);            (* divisor=3 -> 38400 baud *)
  Out_dx_al;

  Mov_r16_imm (DX, Imm16 0x3F9);   (* DLH: Divisor Latch High *)
  Mov_r8_imm (AL, 0x00);            (* high byte = 0 *)
  Out_dx_al;

  Mov_r16_imm (DX, Imm16 0x3FB);   (* LCR: Line Control Register *)
  Mov_r8_imm (AL, 0x03);            (* 8 bits, no parity, 1 stop = 8N1 *)
  Out_dx_al;

  Mov_r16_imm (DX, Imm16 0x3FA);   (* FCR: FIFO Control Register *)
  Mov_r8_imm (AL, 0xC7);            (* enable + clear FIFOs, 14-byte threshold *)
  Out_dx_al;

  Mov_r16_imm (DX, Imm16 0x3FC);   (* MCR: Modem Control Register *)
  Mov_r8_imm (AL, 0x0B);            (* DTR + RTS + OUT2 (enables IRQs) *)
  Out_dx_al;

  (* ---- Load message address and print ---- *)
  Mov_r16_imm (SI, Label "message");  (* SI -> our string *)
  Call "print_string";                 (* print it! *)

  (* ---- Halt: infinite loop ----
     HLT stops the CPU until an interrupt. The JMP catches
     any spurious interrupts and re-halts. *)
  Label_def "halt";
  Cli;
  Hlt;
  Jmp "halt";

  (* ---- print_string subroutine ----
     Prints null-terminated string at DS:SI to BOTH outputs:
     - VGA screen via BIOS INT 0x10 (AH=0x0E)
     - Serial port via direct I/O to COM1 (0x3F8)

     LODSB loads byte from [DS:SI] into AL and increments SI.
     We use PUSH/POP to save the character across the VGA call. *)
  Label_def "print_string";
  Lodsb;                         (* AL = [DS:SI], SI++ *)
  Test_r8_r8 (AL, AL);          (* set zero flag if AL = 0 *)
  Jz "print_done";              (* null terminator? done *)
  Call "putchar";                (* print to VGA + serial *)
  Jmp "print_string";           (* next character *)
  Label_def "print_done";
  Ret;

  (* ---- putchar subroutine ----
     Prints character in AL to both VGA and serial port.

     Register dance:
     1. Save AX (has our char) on the stack
     2. Print to VGA via BIOS (may trash registers)
     3. Wait for serial TX to be ready (poll Line Status Register)
     4. Restore our char from stack and write to serial data port *)
  Label_def "putchar";
  Push_r16 AX;                  (* save char *)
  Push_r16 DX;                  (* save DX *)

  (* VGA output *)
  Mov_r8_imm (AH, 0x0E);       (* BIOS teletype function *)
  Int 0x10;                     (* print to screen *)

  (* Serial: wait for transmitter to be ready *)
  Label_def "serial_wait";
  Mov_r16_imm (DX, Imm16 0x3FD);   (* Line Status Register *)
  In_al_dx;                         (* read LSR *)
  Test_al_imm 0x20;                 (* bit 5 = Transmitter Holding Empty *)
  Jz "serial_wait";                 (* spin until ready *)

  (* Serial: write the character *)
  Pop_r16 DX;                   (* restore DX *)
  Pop_r16 AX;                   (* restore AX (AL = our char) *)
  Push_r16 DX;                  (* save DX again for cleanup *)
  Mov_r16_imm (DX, Imm16 0x3F8);   (* COM1 data port *)
  Out_dx_al;                        (* send character! *)

  Pop_r16 DX;                   (* restore DX *)
  Ret;

  (* ---- The message ---- *)
  Label_def "message";
  Dstring "Hello from OCaml bootloader!";
]

(* ---- Assemble and write the boot image ---- *)

let () =
  match X86_asm.Assembler.assemble boot_program with
  | Error e ->
    Printf.eprintf "Assembly error: %s\n"
      (X86_asm.Assembler.string_of_error e);
    exit 1
  | Ok code ->
    let code_len = String.length code in
    if code_len > 510 then begin
      Printf.eprintf "Error: code is %d bytes, max is 510 for boot sector\n"
        code_len;
      exit 1
    end;

    (* Pad to 510 bytes with zeros, then append the magic boot signature.
       The BIOS checks for 0x55 0xAA at bytes 510-511 to confirm
       this is a valid boot sector. Without it, BIOS won't boot us. *)
    let padding = String.make (510 - code_len) '\x00' in
    let signature = "\x55\xAA" in
    let image = code ^ padding ^ signature in

    (* Write the 512-byte image to a file *)
    let filename =
      if Array.length Sys.argv > 1
      then Sys.argv.(1)
      else "boot.img"
    in
    let oc = open_out_bin filename in
    output_string oc image;
    close_out oc;

    Printf.printf "Boot sector assembled: %s\n" filename;
    Printf.printf "  Code:      %d bytes\n" code_len;
    Printf.printf "  Padding:   %d bytes\n" (510 - code_len);
    Printf.printf "  Signature: 0x55AA\n";
    Printf.printf "  Total:     512 bytes\n";
    Printf.printf "\nRun with: qemu-system-i386 -drive format=raw,file=%s\n"
      filename

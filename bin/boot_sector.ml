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
   2. Point SI to our message string
   3. Call a subroutine that prints each character via BIOS
   4. Halt the CPU forever

   The BIOS teletype function (INT 0x10, AH=0x0E) prints one
   character at a time to the screen. We loop until we hit a
   null byte. Simple, ancient, beautiful. *)

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
     Prints null-terminated string at DS:SI using BIOS teletype.
     LODSB loads byte from [DS:SI] into AL and increments SI.
     INT 0x10 with AH=0x0E prints the character in AL. *)
  Label_def "print_string";
  Lodsb;                         (* AL = [DS:SI], SI++ *)
  Test_r8_r8 (AL, AL);          (* set zero flag if AL = 0 *)
  Jz "print_done";              (* null terminator? done *)
  Mov_r8_imm (AH, 0x0E);       (* BIOS teletype function *)
  Int 0x10;                     (* call BIOS video interrupt *)
  Jmp "print_string";           (* next character *)
  Label_def "print_done";
  Ret;                           (* return to caller *)

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

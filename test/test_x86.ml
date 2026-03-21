(* test_x86.ml -- Tests for the x86 assembler.

   Same pattern as test_dns.ml: construct known inputs, verify the
   output matches expected byte sequences. Instead of DNS packets
   we're testing x86 machine code encoding.

   Every test constructs instructions, encodes them, and compares
   the resulting bytes against hand-verified x86 opcodes. *)

open X86_asm

(* Helper: assemble a list of instructions and return the bytes *)
let assemble_ok instructions =
  match Assembler.assemble instructions with
  | Ok bytes -> bytes
  | Error e ->
    Alcotest.fail (Printf.sprintf "assembly failed: %s"
                     (Assembler.string_of_error e))

(* Helper: convert a string to a list of ints for readable comparison *)
let bytes_of_string s =
  List.init (String.length s) (fun i -> Char.code (String.get s i))

(* Helper: check assembled bytes match expected byte list *)
let check_bytes name expected instructions =
  let actual = assemble_ok instructions in
  let actual_bytes = bytes_of_string actual in
  Alcotest.(check (list int)) name expected actual_bytes

(* ================================================================
   Single-byte instructions
   ================================================================ *)

let test_cli () =
  check_bytes "cli = 0xFA" [0xFA] [Types.Cli]

let test_sti () =
  check_bytes "sti = 0xFB" [0xFB] [Types.Sti]

let test_hlt () =
  check_bytes "hlt = 0xF4" [0xF4] [Types.Hlt]

let test_ret () =
  check_bytes "ret = 0xC3" [0xC3] [Types.Ret]

let test_lodsb () =
  check_bytes "lodsb = 0xAC" [0xAC] [Types.Lodsb]

(* ================================================================
   Register-register operations
   ================================================================ *)

let test_xor_ax_ax () =
  (* XOR AX, AX: opcode 0x31, ModRM = 11_000_000 = 0xC0 *)
  check_bytes "xor ax, ax" [0x31; 0xC0]
    [Types.Xor_r16_r16 (AX, AX)]

let test_xor_bx_bx () =
  (* XOR BX, BX: ModRM = 11_011_011 = 0xDB
     reg=3 (BX as source), r/m=3 (BX as dest) *)
  check_bytes "xor bx, bx" [0x31; 0xDB]
    [Types.Xor_r16_r16 (BX, BX)]

let test_test_al_al () =
  (* TEST AL, AL: opcode 0x84, ModRM = 11_000_000 = 0xC0 *)
  check_bytes "test al, al" [0x84; 0xC0]
    [Types.Test_r8_r8 (AL, AL)]

(* ================================================================
   Register-immediate operations
   ================================================================ *)

let test_mov_ax_imm () =
  (* MOV AX, 0x1234: opcode 0xB8 (0xB8+0), LE16 0x1234 -> [0x34, 0x12] *)
  check_bytes "mov ax, 0x1234" [0xB8; 0x34; 0x12]
    [Types.Mov_r16_imm (AX, Imm16 0x1234)]

let test_mov_si_imm () =
  (* MOV SI, 0x7C00: opcode 0xBE (0xB8+6), LE16 -> [0x00, 0x7C] *)
  check_bytes "mov si, 0x7C00" [0xBE; 0x00; 0x7C]
    [Types.Mov_r16_imm (SI, Imm16 0x7C00)]

let test_mov_sp_imm () =
  (* MOV SP, 0x7C00: opcode 0xBC (0xB8+4) *)
  check_bytes "mov sp, 0x7C00" [0xBC; 0x00; 0x7C]
    [Types.Mov_r16_imm (SP, Imm16 0x7C00)]

let test_mov_ah_imm () =
  (* MOV AH, 0x0E: opcode 0xB4 (0xB0+4), 0x0E *)
  check_bytes "mov ah, 0x0E" [0xB4; 0x0E]
    [Types.Mov_r8_imm (AH, 0x0E)]

let test_mov_ds_ax () =
  (* MOV DS, AX: opcode 0x8E, ModRM = 11_011_000 = 0xD8
     reg=3 (DS), r/m=0 (AX) *)
  check_bytes "mov ds, ax" [0x8E; 0xD8]
    [Types.Mov_seg_r16 (DS, AX)]

let test_mov_es_ax () =
  (* MOV ES, AX: ModRM = 11_000_000 = 0xC0
     reg=0 (ES), r/m=0 (AX) *)
  check_bytes "mov es, ax" [0x8E; 0xC0]
    [Types.Mov_seg_r16 (ES, AX)]

(* ================================================================
   Stack operations
   ================================================================ *)

let test_push_ax () =
  (* PUSH AX: 0x50 + 0 = 0x50 *)
  check_bytes "push ax" [0x50] [Types.Push_r16 AX]

let test_push_dx () =
  (* PUSH DX: 0x50 + 2 = 0x52 *)
  check_bytes "push dx" [0x52] [Types.Push_r16 DX]

let test_pop_ax () =
  (* POP AX: 0x58 + 0 = 0x58 *)
  check_bytes "pop ax" [0x58] [Types.Pop_r16 AX]

let test_pop_dx () =
  (* POP DX: 0x58 + 2 = 0x5A *)
  check_bytes "pop dx" [0x5A] [Types.Pop_r16 DX]

(* ================================================================
   I/O port operations
   ================================================================ *)

let test_out_dx_al () =
  check_bytes "out dx, al" [0xEE] [Types.Out_dx_al]

let test_in_al_dx () =
  check_bytes "in al, dx" [0xEC] [Types.In_al_dx]

let test_test_al_imm () =
  (* TEST AL, 0x20: opcode 0xA8, imm8 0x20 *)
  check_bytes "test al, 0x20" [0xA8; 0x20] [Types.Test_al_imm 0x20]

let test_cmp_al_imm () =
  (* CMP AL, 0x0D: opcode 0x3C, imm8 0x0D *)
  check_bytes "cmp al, 0x0D" [0x3C; 0x0D] [Types.Cmp_al_imm 0x0D]

let test_jnz_forward () =
  (* JNZ skip:
     offset 0: jnz skip  (2 bytes: 0x75, 0x01)
     offset 2: hlt       (1 byte)
     offset 3: skip:
     rel = 3 - (0 + 2) = 1 *)
  check_bytes "jnz forward" [0x75; 0x01; 0xF4]
    [Types.Jnz "skip"; Types.Hlt; Types.Label_def "skip"]

(* ================================================================
   Interrupts
   ================================================================ *)

let test_int_0x10 () =
  check_bytes "int 0x10" [0xCD; 0x10]
    [Types.Int 0x10]

(* ================================================================
   Data directives
   ================================================================ *)

let test_db () =
  check_bytes "db raw bytes" [0xDE; 0xAD; 0xBE; 0xEF]
    [Types.Db [0xDE; 0xAD; 0xBE; 0xEF]]

let test_dstring () =
  (* "Hi" + null terminator *)
  check_bytes "dstring with null" [0x48; 0x69; 0x00]
    [Types.Dstring "Hi"]

(* ================================================================
   Label resolution
   ================================================================ *)

let test_jmp_forward () =
  (* JMP over a HLT:
     offset 0: jmp skip   (2 bytes: 0xEB, 0x01)
     offset 2: hlt        (1 byte)
     offset 3: skip: nop  -- label here
     rel = 3 - (0 + 2) = 1 *)
  check_bytes "jmp forward over hlt" [0xEB; 0x01; 0xF4]
    [Types.Jmp "skip"; Types.Hlt; Types.Label_def "skip"]

let test_jmp_backward () =
  (* JMP backward:
     offset 0: loop: hlt  (1 byte)
     offset 1: jmp loop   (2 bytes)
     rel = 0 - (1 + 2) = -3 = 0xFD *)
  check_bytes "jmp backward" [0xF4; 0xEB; 0xFD]
    [Types.Label_def "loop"; Types.Hlt; Types.Jmp "loop"]

let test_jz_forward () =
  (* JZ skip:
     offset 0: jz skip   (2 bytes: 0x74, 0x01)
     offset 2: hlt       (1 byte)
     offset 3: skip:
     rel = 3 - (0 + 2) = 1 *)
  check_bytes "jz forward" [0x74; 0x01; 0xF4]
    [Types.Jz "skip"; Types.Hlt; Types.Label_def "skip"]

let test_call () =
  (* CALL sub:
     offset 0: call sub  (3 bytes: 0xE8, rel16)
     offset 3: hlt       (1 byte)
     offset 4: sub: ret  (1 byte)
     rel = 4 - (0 + 3) = 1 -> [0x01, 0x00] LE *)
  check_bytes "call forward" [0xE8; 0x01; 0x00; 0xF4; 0xC3]
    [Types.Call "sub"; Types.Hlt; Types.Label_def "sub"; Types.Ret]

let test_mov_label () =
  (* MOV SI, label (with Org 0x7C00):
     offset 0x7C00: mov si, msg  (3 bytes: 0xBE, addr16 LE)
     offset 0x7C03: msg: db "A", 0
     addr of msg = 0x7C03 -> [0x03, 0x7C] LE *)
  check_bytes "mov si, label" [0xBE; 0x03; 0x7C; 0x41; 0x00]
    [Types.Org 0x7C00;
     Types.Mov_r16_imm (SI, Label "msg");
     Types.Label_def "msg";
     Types.Dstring "A"]

(* ================================================================
   Error cases
   ================================================================ *)

let test_undefined_label () =
  let result = Assembler.assemble [Types.Jmp "nonexistent"] in
  (match result with
   | Error (Encode_error (Undefined_label "nonexistent")) -> ()
   | Error e ->
     Alcotest.fail (Printf.sprintf "wrong error: %s"
                      (Assembler.string_of_error e))
   | Ok _ -> Alcotest.fail "expected error for undefined label")

let test_duplicate_label () =
  let result = Assembler.assemble
      [Types.Label_def "dup"; Types.Label_def "dup"] in
  (match result with
   | Error (Duplicate_label "dup") -> ()
   | Error e ->
     Alcotest.fail (Printf.sprintf "wrong error: %s"
                      (Assembler.string_of_error e))
   | Ok _ -> Alcotest.fail "expected error for duplicate label")

(* ================================================================
   Multi-instruction sequence
   ================================================================ *)

let test_segment_setup () =
  (* Common bootloader pattern: zero all segment registers *)
  check_bytes "segment setup"
    [0xFA;                    (* cli *)
     0x31; 0xC0;              (* xor ax, ax *)
     0x8E; 0xD8;              (* mov ds, ax *)
     0x8E; 0xC0;              (* mov es, ax *)
     0x8E; 0xD0;              (* mov ss, ax *)
     0xBC; 0x00; 0x7C;        (* mov sp, 0x7C00 *)
     0xFB]                    (* sti *)
    Types.[
      Cli;
      Xor_r16_r16 (AX, AX);
      Mov_seg_r16 (DS, AX);
      Mov_seg_r16 (ES, AX);
      Mov_seg_r16 (SS, AX);
      Mov_r16_imm (SP, Imm16 0x7C00);
      Sti;
    ]

(* ================================================================
   Test runner
   ================================================================ *)

let () =
  Alcotest.run "x86_asm" [
    "single-byte", [
      Alcotest.test_case "cli" `Quick test_cli;
      Alcotest.test_case "sti" `Quick test_sti;
      Alcotest.test_case "hlt" `Quick test_hlt;
      Alcotest.test_case "ret" `Quick test_ret;
      Alcotest.test_case "lodsb" `Quick test_lodsb;
    ];
    "stack", [
      Alcotest.test_case "push ax" `Quick test_push_ax;
      Alcotest.test_case "push dx" `Quick test_push_dx;
      Alcotest.test_case "pop ax" `Quick test_pop_ax;
      Alcotest.test_case "pop dx" `Quick test_pop_dx;
    ];
    "io-ports", [
      Alcotest.test_case "out dx, al" `Quick test_out_dx_al;
      Alcotest.test_case "in al, dx" `Quick test_in_al_dx;
      Alcotest.test_case "test al, imm" `Quick test_test_al_imm;
      Alcotest.test_case "cmp al, imm" `Quick test_cmp_al_imm;
      Alcotest.test_case "jnz forward" `Quick test_jnz_forward;
    ];
    "register-register", [
      Alcotest.test_case "xor ax, ax" `Quick test_xor_ax_ax;
      Alcotest.test_case "xor bx, bx" `Quick test_xor_bx_bx;
      Alcotest.test_case "test al, al" `Quick test_test_al_al;
    ];
    "register-immediate", [
      Alcotest.test_case "mov ax, 0x1234" `Quick test_mov_ax_imm;
      Alcotest.test_case "mov si, 0x7C00" `Quick test_mov_si_imm;
      Alcotest.test_case "mov sp, 0x7C00" `Quick test_mov_sp_imm;
      Alcotest.test_case "mov ah, 0x0E" `Quick test_mov_ah_imm;
      Alcotest.test_case "mov ds, ax" `Quick test_mov_ds_ax;
      Alcotest.test_case "mov es, ax" `Quick test_mov_es_ax;
    ];
    "interrupts", [
      Alcotest.test_case "int 0x10" `Quick test_int_0x10;
    ];
    "data", [
      Alcotest.test_case "db raw bytes" `Quick test_db;
      Alcotest.test_case "dstring" `Quick test_dstring;
    ];
    "labels", [
      Alcotest.test_case "jmp forward" `Quick test_jmp_forward;
      Alcotest.test_case "jmp backward" `Quick test_jmp_backward;
      Alcotest.test_case "jz forward" `Quick test_jz_forward;
      Alcotest.test_case "call" `Quick test_call;
      Alcotest.test_case "mov r16, label" `Quick test_mov_label;
    ];
    "errors", [
      Alcotest.test_case "undefined label" `Quick test_undefined_label;
      Alcotest.test_case "duplicate label" `Quick test_duplicate_label;
    ];
    "sequences", [
      Alcotest.test_case "segment setup" `Quick test_segment_setup;
    ];
  ]

(* types.ml -- x86 real-mode register and instruction types.

   Just like our DNS types, we use OCaml variants so the compiler
   FORCES exhaustive handling. Add a new instruction? Every match
   expression must be updated or it won't compile.

   REAL MODE: When an x86 CPU powers on, it starts in "real mode" --
   16-bit addressing, 1 MB memory limit, direct hardware access via
   BIOS interrupts. This is where bootloaders live. *)

(* ---- 16-bit general-purpose registers ----
   The order matters: it matches the x86 register encoding.
   AX=0, CX=1, DX=2, BX=3, SP=4, BP=5, SI=6, DI=7.
   Yes, BX comes AFTER DX. x86 encoding is... historical. *)

type reg16 =
  | AX | CX | DX | BX | SP | BP | SI | DI

(* ---- 8-bit registers ----
   The low/high halves of the 16-bit registers.
   AL=0, CL=1, DL=2, BL=3, AH=4, CH=5, DH=6, BH=7.
   AL is the low byte of AX, AH is the high byte. *)

type reg8 =
  | AL | CL | DL | BL | AH | CH | DH | BH

(* ---- Segment registers ----
   x86 real mode uses segments to extend addressing beyond 16 bits.
   Physical address = segment * 16 + offset.
   ES=0, CS=1, SS=2, DS=3. *)

type seg_reg =
  | ES | CS | SS | DS

(* ---- 16-bit immediate operand ----
   KEY INSIGHT: A 16-bit immediate can be either a literal number
   or a reference to a label. Labels are just "deferred immediates"
   -- the assembler resolves them to concrete addresses.

   This is a great example of OCaml variants carrying different data:
   Imm16 0x7C00  -- a known value
   Label "msg"   -- resolved during assembly to an address *)

type imm16 =
  | Imm16 of int
  | Label of string

(* ---- x86 real-mode instructions ----
   Each variant maps to exactly ONE encoding pattern.
   No ambiguity, no overloading -- pattern matching does the rest.

   Compare to DNS types.ml: same idea, different domain.
   There we had Query | Response; here we have Cli | Sti | Hlt.
   The compiler guarantees we handle every case in the encoder. *)

type instruction =
  (* -- Zero-operand instructions (single byte each) -- *)
  | Cli                                 (* 0xFA: disable interrupts *)
  | Sti                                 (* 0xFB: enable interrupts *)
  | Hlt                                 (* 0xF4: halt until interrupt *)
  | Ret                                 (* 0xC3: return from call *)
  | Lodsb                               (* 0xAC: load byte [DS:SI] -> AL, inc SI *)

  (* -- Register-register operations -- *)
  | Xor_r16_r16 of reg16 * reg16       (* 0x31 + ModRM: XOR dst, src *)
  | Test_r8_r8 of reg8 * reg8          (* 0x84 + ModRM: AND without storing *)

  (* -- Register-immediate operations -- *)
  | Mov_r16_imm of reg16 * imm16       (* 0xB8+reg, LE16: load 16-bit value *)
  | Mov_r8_imm of reg8 * int           (* 0xB0+reg, byte: load 8-bit value *)
  | Mov_seg_r16 of seg_reg * reg16     (* 0x8E + ModRM: load segment register *)

  (* -- Interrupts -- *)
  | Int of int                          (* 0xCD n: software interrupt (BIOS calls!) *)

  (* -- Control flow (all reference labels) -- *)
  | Jz of string                        (* 0x74 rel8: jump if zero flag set *)
  | Jmp of string                       (* 0xEB rel8: unconditional short jump *)
  | Call of string                      (* 0xE8 rel16: near call *)

  (* -- Assembler directives (not real instructions) -- *)
  | Org of int                          (* set origin address *)
  | Label_def of string                 (* define a label at this position *)
  | Db of int list                      (* raw bytes *)
  | Dstring of string                   (* null-terminated string data *)

(* ---- Register encoding functions ----
   These return the 3-bit register code used in x86 ModRM bytes.
   The register order is baked into the x86 ISA -- can't change it. *)

let reg16_code = function
  | AX -> 0 | CX -> 1 | DX -> 2 | BX -> 3
  | SP -> 4 | BP -> 5 | SI -> 6 | DI -> 7

let reg8_code = function
  | AL -> 0 | CL -> 1 | DL -> 2 | BL -> 3
  | AH -> 4 | CH -> 5 | DH -> 6 | BH -> 7

let seg_reg_code = function
  | ES -> 0 | CS -> 1 | SS -> 2 | DS -> 3

(* ---- String representations (for debugging/error messages) ---- *)

let string_of_reg16 = function
  | AX -> "ax" | CX -> "cx" | DX -> "dx" | BX -> "bx"
  | SP -> "sp" | BP -> "bp" | SI -> "si" | DI -> "di"

let string_of_reg8 = function
  | AL -> "al" | CL -> "cl" | DL -> "dl" | BL -> "bl"
  | AH -> "ah" | CH -> "ch" | DH -> "dh" | BH -> "bh"

let string_of_seg_reg = function
  | ES -> "es" | CS -> "cs" | SS -> "ss" | DS -> "ds"

let string_of_imm16 = function
  | Imm16 n -> Printf.sprintf "0x%04X" n
  | Label s -> s

let string_of_instruction = function
  | Cli -> "cli"
  | Sti -> "sti"
  | Hlt -> "hlt"
  | Ret -> "ret"
  | Lodsb -> "lodsb"
  | Xor_r16_r16 (dst, src) ->
    Printf.sprintf "xor %s, %s" (string_of_reg16 dst) (string_of_reg16 src)
  | Test_r8_r8 (a, b) ->
    Printf.sprintf "test %s, %s" (string_of_reg8 a) (string_of_reg8 b)
  | Mov_r16_imm (r, v) ->
    Printf.sprintf "mov %s, %s" (string_of_reg16 r) (string_of_imm16 v)
  | Mov_r8_imm (r, v) ->
    Printf.sprintf "mov %s, 0x%02X" (string_of_reg8 r) v
  | Mov_seg_r16 (seg, r) ->
    Printf.sprintf "mov %s, %s" (string_of_seg_reg seg) (string_of_reg16 r)
  | Int n -> Printf.sprintf "int 0x%02X" n
  | Jz lbl -> Printf.sprintf "jz %s" lbl
  | Jmp lbl -> Printf.sprintf "jmp %s" lbl
  | Call lbl -> Printf.sprintf "call %s" lbl
  | Org n -> Printf.sprintf "org 0x%04X" n
  | Label_def name -> Printf.sprintf "%s:" name
  | Db bytes ->
    Printf.sprintf "db %s"
      (String.concat ", " (List.map (Printf.sprintf "0x%02X") bytes))
  | Dstring s -> Printf.sprintf "db \"%s\", 0" s

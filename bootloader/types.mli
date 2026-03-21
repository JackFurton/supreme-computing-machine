(* types.mli -- Public interface for x86 real-mode types.

   Exposes all types and their constructors so users can build
   instruction lists. Register encoding functions are also public
   since the encoder needs them. *)

(** 16-bit general-purpose registers.
    Order matches x86 encoding: AX=0, CX=1, DX=2, BX=3, SP=4, BP=5, SI=6, DI=7. *)
type reg16 =
  | AX | CX | DX | BX | SP | BP | SI | DI

(** 8-bit registers (low/high halves of 16-bit registers).
    AL=0, CL=1, DL=2, BL=3, AH=4, CH=5, DH=6, BH=7. *)
type reg8 =
  | AL | CL | DL | BL | AH | CH | DH | BH

(** Segment registers. ES=0, CS=1, SS=2, DS=3. *)
type seg_reg =
  | ES | CS | SS | DS

(** 16-bit immediate: either a literal value or a label reference. *)
type imm16 =
  | Imm16 of int
  | Label of string

(** x86 real-mode instructions and assembler directives. *)
type instruction =
  | Cli
  | Sti
  | Hlt
  | Ret
  | Lodsb
  | Stosb
  | Push_r16 of reg16
  | Pop_r16 of reg16
  | Out_dx_al
  | In_al_dx
  | Xor_r16_r16 of reg16 * reg16
  | Test_r8_r8 of reg8 * reg8
  | Test_al_imm of int
  | Cmp_al_imm of int
  | Mov_r16_imm of reg16 * imm16
  | Mov_r8_imm of reg8 * int
  | Mov_seg_r16 of seg_reg * reg16
  | Int of int
  | Jz of string
  | Jnz of string
  | Jmp of string
  | Call of string
  | Org of int
  | Label_def of string
  | Db of int list
  | Dstring of string

(** 3-bit register encoding for ModRM byte *)
val reg16_code : reg16 -> int
val reg8_code : reg8 -> int
val seg_reg_code : seg_reg -> int

(** String representations for debugging *)
val string_of_reg16 : reg16 -> string
val string_of_reg8 : reg8 -> string
val string_of_seg_reg : seg_reg -> string
val string_of_imm16 : imm16 -> string
val string_of_instruction : instruction -> string

(* encoder.mli -- Interface for x86 instruction encoding.

   Two-phase design: compute sizes first (pass 1), then emit bytes (pass 2).
   This is how real assemblers work -- NASM, GAS, all of them. *)

(** Assembly errors *)
type error =
  | Undefined_label of string
  | Relative_jump_out_of_range of string * int

val string_of_error : error -> string

(** Compute the size in bytes of an instruction.
    Used in pass 1 to build label offset tables. *)
val instruction_size : Types.instruction -> int

(** Encode a single instruction into the emitter buffer.
    Requires the label table (from pass 1) and the current
    absolute offset for computing relative jumps. *)
val encode_instruction :
  Emitter.t ->
  labels:(string, int) Hashtbl.t ->
  offset:int ->
  Types.instruction ->
  (unit, error) result

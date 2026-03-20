(* assembler.mli -- Two-pass x86 assembler interface.

   Takes a list of instructions, resolves all labels,
   returns the assembled machine code as a byte string. *)

(** Assembly errors *)
type error =
  | Duplicate_label of string
  | Encode_error of Encoder.error

val string_of_error : error -> string

(** Assemble a list of instructions into machine code.
    Performs two passes: label resolution then byte emission.
    Returns the raw bytes on success, or an error. *)
val assemble : Types.instruction list -> (string, error) result

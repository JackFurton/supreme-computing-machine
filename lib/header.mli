(* header.mli -- DNS header parser interface *)

(** Parse the 12-byte DNS header from a buffer *)
val parse : Read_buffer.t -> (Types.header, Read_buffer.error) result

(* packet.mli -- Top-level DNS packet parser interface *)

(** Parse a raw DNS packet (bytes) into structured data *)
val parse : string -> (Types.packet, Read_buffer.error) result

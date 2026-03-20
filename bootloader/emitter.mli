(* emitter.mli -- Interface for the little-endian x86 byte emitter.

   Compare with lib/write_buffer.mli -- same abstraction (opaque
   mutable buffer), different byte order. *)

(** Opaque byte buffer for emitting x86 machine code *)
type t

(** Create a new empty emitter *)
val create : unit -> t

(** Emit a single byte *)
val emit_uint8 : t -> int -> unit

(** Emit a 16-bit value in little-endian order *)
val emit_uint16_le : t -> int -> unit

(** Emit a signed 16-bit value in little-endian order (for relative offsets) *)
val emit_int16_le : t -> int -> unit

(** Emit a signed 8-bit value (for relative jump offsets) *)
val emit_int8 : t -> int -> unit

(** Emit a list of bytes *)
val emit_bytes : t -> int list -> unit

(** Emit a raw string *)
val emit_string : t -> string -> unit

(** Get the assembled bytes as a string *)
val contents : t -> string

(** Current length in bytes *)
val length : t -> int

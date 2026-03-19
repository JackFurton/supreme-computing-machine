(* write_buffer.mli -- Interface for building DNS packets byte-by-byte.
   
   This is the inverse of Read_buffer: instead of reading bytes from
   a packet, we WRITE bytes to construct one.
   
   We use a Buffer (growable byte array) internally, then convert
   to a string at the end. *)

(** The write buffer type (opaque) *)
type t

(** Create a new empty write buffer *)
val create : unit -> t

(** Write a single byte (8 bits) *)
val write_uint8 : t -> int -> unit

(** Write two bytes as big-endian 16-bit unsigned int *)
val write_uint16 : t -> int -> unit

(** Write a raw string of bytes *)
val write_bytes : t -> string -> unit

(** Write a DNS domain name as length-prefixed labels *)
val write_name : t -> string list -> unit

(** Get the final packet as a byte string *)
val contents : t -> string

(** Current length of the buffer *)
val length : t -> int

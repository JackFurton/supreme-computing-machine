(* read_buffer.mli -- Interface for our byte buffer reader.
   
   This is a cursor over a byte string. We use it to read through
   a DNS packet byte by byte (or word by word).
   
   Notice the `t` type is ABSTRACT -- we declare it exists but don't
   say what it is. Outside code can't construct or inspect it directly.
   This is OCaml's version of encapsulation. *)

(** The buffer type (opaque) *)
type t

(** Parse errors *)
type error =
  | Unexpected_end of { needed : int; available : int }
  | Invalid_label_length of int
  | Label_too_long of int
  | Name_too_long of int

(** Human-readable error description *)
val string_of_error : error -> string

(** Create a buffer from raw bytes *)
val of_string : string -> t

(** Current read position *)
val position : t -> int

(** Total length of the underlying data *)
val length : t -> int

(** Remaining bytes available to read *)
val remaining : t -> int

(** Read a single byte (8 bits), advancing the cursor *)
val read_uint8 : t -> (int, error) result

(** Read two bytes as a big-endian 16-bit unsigned int *)
val read_uint16 : t -> (int, error) result

(** Read n bytes as a raw string *)
val read_bytes : t -> int -> (string, error) result

(** Read a DNS domain name (sequence of length-prefixed labels) *)
val read_name : t -> (string list, error) result

(** Monadic bind for chaining fallible operations.
    [read_uint8 buf >>= fun byte -> ...] short-circuits on error. *)
val ( >>= ) : ('a, error) result -> ('a -> ('b, error) result) -> ('b, error) result

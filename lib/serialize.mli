(* serialize.mli -- Convert DNS types back to wire format bytes. *)

(** Encode a DNS header into wire format *)
val encode_header : Types.header -> string

(** Encode a DNS question into wire format *)
val encode_question : Types.question -> string

(** Encode a record type to its wire format integer *)
val encode_rr_type : Types.rr_type -> int

(** Encode a record class to its wire format integer *)
val encode_rr_class : Types.rr_class -> int

(** Build a complete DNS query packet for a given domain name and record type.
    Generates a random ID and sets standard query flags. *)
val build_query : string list -> Types.rr_type -> string

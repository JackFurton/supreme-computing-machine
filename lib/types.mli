(* types.mli -- The MODULE INTERFACE file for types.
   
   .mli files in OCaml are like header files in C, or trait definitions
   in Rust. They declare what a module exposes publicly.
   
   If a type/function is in the .ml but NOT in the .mli, it's private.
   This is how OCaml does encapsulation -- no "public/private" keywords. *)

(** DNS query/response type *)
type qr =
  | Query     (** This is a query *)
  | Response  (** This is a response *)

(** DNS operation code *)
type opcode =
  | Standard_query   (** QUERY - standard query *)
  | Inverse_query    (** IQUERY - inverse query (obsolete) *)
  | Status           (** STATUS - server status request *)
  | Unknown_opcode of int  (** Something we don't recognize *)

(** DNS response code *)
type rcode =
  | No_error         (** Everything is fine *)
  | Format_error     (** The server couldn't understand the query *)
  | Server_failure   (** The server failed internally *)
  | Name_error       (** NXDOMAIN -- the domain doesn't exist *)
  | Not_implemented  (** The server doesn't support this query type *)
  | Refused          (** The server refuses to answer *)
  | Unknown_rcode of int

(** DNS record types (there are many, we support the common ones) *)
type rr_type =
  | A          (** IPv4 address *)
  | AAAA       (** IPv6 address *)
  | CNAME      (** Canonical name (alias) *)
  | MX         (** Mail exchange *)
  | NS         (** Name server *)
  | PTR        (** Pointer (reverse DNS) *)
  | SOA        (** Start of authority *)
  | TXT        (** Text record *)
  | SRV        (** Service locator *)
  | Unknown_type of int

(** DNS record class *)
type rr_class =
  | IN           (** Internet -- almost always this *)
  | Unknown_class of int

(** The 12-byte DNS header *)
type header = {
  id : int;                  (** 16-bit query ID *)
  qr : qr;                  (** Query or Response *)
  opcode : opcode;           (** Operation type *)
  authoritative : bool;      (** Is the server authoritative for this domain? *)
  truncated : bool;          (** Was the response truncated? *)
  recursion_desired : bool;  (** Client wants recursive resolution *)
  recursion_available : bool;(** Server supports recursion *)
  rcode : rcode;             (** Response code *)
  question_count : int;      (** Number of questions *)
  answer_count : int;        (** Number of answer records *)
  authority_count : int;     (** Number of authority records *)
  additional_count : int;    (** Number of additional records *)
}

(** A DNS question: "what is the A record for example.com?" *)
type question = {
  qname : string list;  (** Domain name as labels: ["www"; "example"; "com"] *)
  qtype : rr_type;      (** What record type are we asking for? *)
  qclass : rr_class;    (** What class? (almost always IN) *)
}

(** A parsed DNS packet (header + questions for now) *)
type packet = {
  header : header;
  questions : question list;
}

(** Human-readable string representations *)

val string_of_qr : qr -> string
val string_of_opcode : opcode -> string
val string_of_rcode : rcode -> string
val string_of_rr_type : rr_type -> string
val string_of_rr_class : rr_class -> string
val string_of_header : header -> string
val string_of_question : question -> string
val string_of_packet : packet -> string

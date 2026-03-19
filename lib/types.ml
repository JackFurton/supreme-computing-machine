(* types.ml -- All the types for our DNS parser.
   
   OCaml VARIANT TYPES are the star here. If you've used enums in
   Rust or TypeScript, variants are similar but more powerful --
   each variant can carry different data.
   
   The compiler FORCES you to handle every case. If you add a new
   variant and forget to update a match expression somewhere, it's
   a compile error. This is why OCaml is great for protocol parsing. *)

(* ---- Query/Response flag ---- *)

type qr =
  | Query
  | Response

(* ---- Operation code (4 bits) ---- *)

type opcode =
  | Standard_query
  | Inverse_query
  | Status
  | Unknown_opcode of int
  (* `Unknown_opcode of int` means this variant CARRIES data.
     So you can have `Unknown_opcode 7` -- it's like a tagged union in C. *)

(* ---- Response code (4 bits) ---- *)

type rcode =
  | No_error
  | Format_error
  | Server_failure
  | Name_error          (* NXDOMAIN *)
  | Not_implemented
  | Refused
  | Unknown_rcode of int

(* ---- Record types ---- *)

type rr_type =
  | A
  | AAAA
  | CNAME
  | MX
  | NS
  | PTR
  | SOA
  | TXT
  | SRV
  | Unknown_type of int

(* ---- Record classes ---- *)

type rr_class =
  | IN
  | Unknown_class of int

(* ---- DNS Header (12 bytes) ---- *)
(* RECORD TYPES in OCaml are like structs in C/Rust.
   Fields are immutable by default (functional style). *)

type header = {
  id : int;
  qr : qr;
  opcode : opcode;
  authoritative : bool;
  truncated : bool;
  recursion_desired : bool;
  recursion_available : bool;
  rcode : rcode;
  question_count : int;
  answer_count : int;
  authority_count : int;
  additional_count : int;
}

(* ---- DNS Question ---- *)

type question = {
  qname : string list;    (* e.g. ["www"; "example"; "com"] *)
  qtype : rr_type;
  qclass : rr_class;
}

(* ---- Full DNS Packet ---- *)

type packet = {
  header : header;
  questions : question list;
}

(* ---- String conversion functions ---- *)
(* These use PATTERN MATCHING -- OCaml's most powerful feature.
   It's like a switch statement, but:
   - The compiler checks you covered every case
   - You can destructure data inline
   - You can match on nested structures *)

let string_of_qr = function
  (* `function` is shorthand for `fun x -> match x with` *)
  | Query -> "QUERY"
  | Response -> "RESPONSE"

let string_of_opcode = function
  | Standard_query -> "QUERY"
  | Inverse_query -> "IQUERY"
  | Status -> "STATUS"
  | Unknown_opcode n -> Printf.sprintf "UNKNOWN(%d)" n

let string_of_rcode = function
  | No_error -> "NOERROR"
  | Format_error -> "FORMERR"
  | Server_failure -> "SERVFAIL"
  | Name_error -> "NXDOMAIN"
  | Not_implemented -> "NOTIMP"
  | Refused -> "REFUSED"
  | Unknown_rcode n -> Printf.sprintf "UNKNOWN(%d)" n

let string_of_rr_type = function
  | A -> "A"
  | AAAA -> "AAAA"
  | CNAME -> "CNAME"
  | MX -> "MX"
  | NS -> "NS"
  | PTR -> "PTR"
  | SOA -> "SOA"
  | TXT -> "TXT"
  | SRV -> "SRV"
  | Unknown_type n -> Printf.sprintf "TYPE%d" n

let string_of_rr_class = function
  | IN -> "IN"
  | Unknown_class n -> Printf.sprintf "CLASS%d" n

let string_of_header h =
  Printf.sprintf
    ";; %s, opcode: %s, status: %s, id: %d\n\
     ;; flags: %s%s%s%s; QUERY: %d, ANSWER: %d, AUTHORITY: %d, ADDITIONAL: %d"
    (string_of_qr h.qr)
    (string_of_opcode h.opcode)
    (string_of_rcode h.rcode)
    h.id
    (if h.qr = Response then "qr " else "")
    (if h.authoritative then "aa " else "")
    (if h.truncated then "tc " else "")
    (if h.recursion_desired then "rd " else "")
    h.question_count
    h.answer_count
    h.authority_count
    h.additional_count

let string_of_question q =
  Printf.sprintf ";%s\t\t\t%s\t%s"
    (String.concat "." q.qname)
    (string_of_rr_class q.qclass)
    (string_of_rr_type q.qtype)

let string_of_packet p =
  let header_str = string_of_header p.header in
  let questions_str =
    if p.questions = [] then ""
    else
      "\n;; QUESTION SECTION:\n"
      ^ String.concat "\n" (List.map string_of_question p.questions)
  in
  header_str ^ questions_str

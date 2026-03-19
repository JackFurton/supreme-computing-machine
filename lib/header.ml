(* header.ml -- Parse the 12-byte DNS header.
   
   DNS Header format (RFC 1035):
   
     0  1  2  3  4  5  6  7  8  9  10 11 12 13 14 15
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   |                      ID                         |
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   |QR|   Opcode  |AA|TC|RD|RA|   Z    |   RCODE    |
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   |                    QDCOUNT                       |
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   |                    ANCOUNT                       |
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   |                    NSCOUNT                       |
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   |                    ARCOUNT                       |
   +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
   
   That's 6 x 16-bit values = 12 bytes total. *)

(* Bring the >>= operator into scope *)
let ( >>= ) = Read_buffer.( >>= )

(* ---- Decoding helpers ---- *)
(* These convert raw integers into our typed variants.
   PATTERN MATCHING makes this clean and exhaustive. *)

let decode_qr bit =
  if bit = 0 then Types.Query else Types.Response

let decode_opcode n =
  (* `match` is OCaml's pattern matching -- like switch but better *)
  match n with
  | 0 -> Types.Standard_query
  | 1 -> Types.Inverse_query
  | 2 -> Types.Status
  | n -> Types.Unknown_opcode n

let decode_rcode n =
  match n with
  | 0 -> Types.No_error
  | 1 -> Types.Format_error
  | 2 -> Types.Server_failure
  | 3 -> Types.Name_error
  | 4 -> Types.Not_implemented
  | 5 -> Types.Refused
  | n -> Types.Unknown_rcode n

(* ---- The main parse function ---- *)

let parse buf =
  (* Read the 6 sixteen-bit values that make up the header.
     Each >>= chains to the next read, short-circuiting on error.
     
     This is the "railway-oriented programming" pattern:
     success flows right, errors derail immediately. *)

  Read_buffer.read_uint16 buf >>= fun id ->
  Read_buffer.read_uint16 buf >>= fun flags ->
  Read_buffer.read_uint16 buf >>= fun question_count ->
  Read_buffer.read_uint16 buf >>= fun answer_count ->
  Read_buffer.read_uint16 buf >>= fun authority_count ->
  Read_buffer.read_uint16 buf >>= fun additional_count ->

  (* Now unpack the flags word. This is bit twiddling --
     same as you'd do in C, just with OCaml operators.
     
     `land` = bitwise AND   (& in C)
     `lsr`  = logical shift right (>> in C)
     `<> 0` = not-equal-to-zero (converts int to bool) *)

  let qr =          decode_qr    ((flags lsr 15) land 1) in
  let opcode =      decode_opcode ((flags lsr 11) land 0xF) in
  let authoritative =             ((flags lsr 10) land 1) <> 0 in
  let truncated =                 ((flags lsr 9)  land 1) <> 0 in
  let recursion_desired =         ((flags lsr 8)  land 1) <> 0 in
  let recursion_available =       ((flags lsr 7)  land 1) <> 0 in
  let rcode =       decode_rcode  (flags land 0xF) in

  (* Construct the header record.
     In OCaml, record construction looks like JSON: *)
  Ok Types.{
    id;
    qr;
    opcode;
    authoritative;
    truncated;
    recursion_desired;
    recursion_available;
    rcode;
    question_count;
    answer_count;
    authority_count;
    additional_count;
  }

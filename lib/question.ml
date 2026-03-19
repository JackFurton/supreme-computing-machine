(* question.ml -- Parse DNS question section.
   
   After the 12-byte header, a DNS packet contains QDCOUNT questions.
   Each question is:
     - A domain name (variable length, label-encoded)
     - QTYPE  (16 bits) -- what record type are we asking about?
     - QCLASS (16 bits) -- what class? (almost always IN = Internet)
*)

let ( >>= ) = Read_buffer.( >>= )

(* ---- Decode helpers ---- *)

let decode_rr_type n =
  match n with
  | 1   -> Types.A
  | 28  -> Types.AAAA
  | 5   -> Types.CNAME
  | 15  -> Types.MX
  | 2   -> Types.NS
  | 12  -> Types.PTR
  | 6   -> Types.SOA
  | 16  -> Types.TXT
  | 33  -> Types.SRV
  | n   -> Types.Unknown_type n

let decode_rr_class n =
  match n with
  | 1 -> Types.IN
  | n -> Types.Unknown_class n

(* ---- Parse one question ---- *)

let parse_one buf =
  Read_buffer.read_name buf >>= fun qname ->
  Read_buffer.read_uint16 buf >>= fun qtype_raw ->
  Read_buffer.read_uint16 buf >>= fun qclass_raw ->

  Ok Types.{
    qname;
    qtype = decode_rr_type qtype_raw;
    qclass = decode_rr_class qclass_raw;
  }

(* ---- Parse n questions ---- *)
(* Note the recursive approach. In functional programming we use
   recursion instead of for-loops. The compiler optimizes tail
   recursion so there's no stack overflow risk. *)

let parse buf count =
  let rec loop acc remaining =
    if remaining = 0 then
      Ok (List.rev acc)
    else
      parse_one buf >>= fun question ->
      loop (question :: acc) (remaining - 1)
  in
  loop [] count

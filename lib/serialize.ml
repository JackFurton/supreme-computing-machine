(* serialize.ml -- Encode DNS types to wire format.
   
   This is the inverse of our parsers. Given a Types.header or
   Types.question, produce the raw bytes.
   
   KEY OCAML CONCEPT: pattern matching for encoding.
   Same match expressions we used for decoding, but in reverse --
   convert variants to integers. The compiler still checks exhaustiveness. *)

(* ---- Encoding helpers ---- *)

let encode_qr = function
  | Types.Query -> 0
  | Types.Response -> 1

let encode_opcode = function
  | Types.Standard_query -> 0
  | Types.Inverse_query -> 1
  | Types.Status -> 2
  | Types.Unknown_opcode n -> n

let encode_rcode = function
  | Types.No_error -> 0
  | Types.Format_error -> 1
  | Types.Server_failure -> 2
  | Types.Name_error -> 3
  | Types.Not_implemented -> 4
  | Types.Refused -> 5
  | Types.Unknown_rcode n -> n

let encode_rr_type = function
  | Types.A -> 1
  | Types.AAAA -> 28
  | Types.CNAME -> 5
  | Types.MX -> 15
  | Types.NS -> 2
  | Types.PTR -> 12
  | Types.SOA -> 6
  | Types.TXT -> 16
  | Types.SRV -> 33
  | Types.Unknown_type n -> n

let encode_rr_class = function
  | Types.IN -> 1
  | Types.Unknown_class n -> n

let bool_to_bit b = if b then 1 else 0

(* ---- Header encoding ---- *)

let encode_header h =
  let buf = Write_buffer.create () in

  Write_buffer.write_uint16 buf h.Types.id;

  (* Pack the flags back into a 16-bit word.
     This is the exact reverse of the bit unpacking in header.ml *)
  let flags =
    (encode_qr h.qr             lsl 15)
    lor (encode_opcode h.opcode  lsl 11)
    lor (bool_to_bit h.authoritative lsl 10)
    lor (bool_to_bit h.truncated     lsl 9)
    lor (bool_to_bit h.recursion_desired   lsl 8)
    lor (bool_to_bit h.recursion_available lsl 7)
    lor (encode_rcode h.rcode)
  in
  Write_buffer.write_uint16 buf flags;
  Write_buffer.write_uint16 buf h.question_count;
  Write_buffer.write_uint16 buf h.answer_count;
  Write_buffer.write_uint16 buf h.authority_count;
  Write_buffer.write_uint16 buf h.additional_count;

  Write_buffer.contents buf

(* ---- Question encoding ---- *)

let encode_question q =
  let buf = Write_buffer.create () in
  Write_buffer.write_name buf q.Types.qname;
  Write_buffer.write_uint16 buf (encode_rr_type q.qtype);
  Write_buffer.write_uint16 buf (encode_rr_class q.qclass);
  Write_buffer.contents buf

(* ---- Build a complete query ---- *)

let build_query name qtype =
  (* Random-ish query ID. In production you'd use a CSPRNG.
     For learning purposes, this is fine. *)
  let id = Random.bits () land 0xFFFF in

  let header = Types.{
    id;
    qr = Query;
    opcode = Standard_query;
    authoritative = false;
    truncated = false;
    recursion_desired = true;    (* We want the server to recurse for us *)
    recursion_available = false; (* We're the client, this field is for servers *)
    rcode = No_error;
    question_count = 1;
    answer_count = 0;
    authority_count = 0;
    additional_count = 0;
  } in

  let question = Types.{
    qname = name;
    qtype;
    qclass = IN;
  } in

  encode_header header ^ encode_question question

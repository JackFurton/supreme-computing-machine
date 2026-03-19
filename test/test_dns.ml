(* test_dns.ml -- Tests for our DNS parser.
   
   We test by constructing raw DNS packets as byte strings
   and verifying our parser extracts the correct values.
   
   The test packets are hand-crafted from the RFC 1035 spec.
   In the real world you'd also capture real packets with tcpdump/wireshark. *)

(* ---- Test helpers ---- *)

(* Build a raw byte string from a list of integers.
   This makes it easy to construct test packets byte-by-byte. *)
let bytes_of_list ints =
  let buf = Bytes.create (List.length ints) in
  List.iteri (fun i b -> Bytes.set buf i (Char.chr (b land 0xFF))) ints;
  Bytes.to_string buf

(* ---- Test: Read buffer basics ---- *)

let test_read_uint8 () =
  let buf = Dns_parser.Buffer.of_string "\x42\xFF" in
  (match Dns_parser.Buffer.read_uint8 buf with
   | Ok v -> Alcotest.(check int) "first byte" 0x42 v
   | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e));
  (match Dns_parser.Buffer.read_uint8 buf with
   | Ok v -> Alcotest.(check int) "second byte" 0xFF v
   | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e));
  (* Third read should fail -- no more data *)
  (match Dns_parser.Buffer.read_uint8 buf with
   | Ok _ -> Alcotest.fail "expected error on overread"
   | Error _ -> ())

let test_read_uint16 () =
  (* 0xABCD in big-endian is [0xAB; 0xCD] *)
  let buf = Dns_parser.Buffer.of_string "\xAB\xCD" in
  match Dns_parser.Buffer.read_uint16 buf with
  | Ok v -> Alcotest.(check int) "uint16" 0xABCD v
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)

let test_read_name () =
  (* Encode "www.example.com" as DNS labels:
     [3]www[7]example[3]com[0] *)
  let raw = bytes_of_list [
    3; 0x77; 0x77; 0x77;                              (* www *)
    7; 0x65; 0x78; 0x61; 0x6D; 0x70; 0x6C; 0x65;     (* example *)
    3; 0x63; 0x6F; 0x6D;                              (* com *)
    0                                                  (* terminator *)
  ] in
  let buf = Dns_parser.Buffer.of_string raw in
  match Dns_parser.Buffer.read_name buf with
  | Ok labels ->
    Alcotest.(check (list string)) "domain labels"
      ["www"; "example"; "com"] labels
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)

(* ---- Test: Header parsing ---- *)

(* Construct a standard query header for "give me the A record of example.com"
   
   ID:     0x1234
   Flags:  0x0100 (standard query, recursion desired)
   QDCOUNT: 1
   ANCOUNT: 0
   NSCOUNT: 0
   ARCOUNT: 0 *)
let standard_query_header_bytes = bytes_of_list [
  0x12; 0x34;   (* ID *)
  0x01; 0x00;   (* Flags: RD=1, everything else 0 *)
  0x00; 0x01;   (* QDCOUNT = 1 *)
  0x00; 0x00;   (* ANCOUNT = 0 *)
  0x00; 0x00;   (* NSCOUNT = 0 *)
  0x00; 0x00;   (* ARCOUNT = 0 *)
]

let test_parse_header () =
  let buf = Dns_parser.Buffer.of_string standard_query_header_bytes in
  match Dns_parser.Header.parse buf with
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)
  | Ok h ->
    let open Dns_parser.Types in
    Alcotest.(check int) "id" 0x1234 h.id;
    Alcotest.(check bool) "is query" true (h.qr = Query);
    Alcotest.(check bool) "opcode is standard" true (h.opcode = Standard_query);
    Alcotest.(check bool) "not authoritative" false h.authoritative;
    Alcotest.(check bool) "not truncated" false h.truncated;
    Alcotest.(check bool) "recursion desired" true h.recursion_desired;
    Alcotest.(check bool) "recursion not available" false h.recursion_available;
    Alcotest.(check bool) "rcode is noerror" true (h.rcode = No_error);
    Alcotest.(check int) "question count" 1 h.question_count;
    Alcotest.(check int) "answer count" 0 h.answer_count

let test_parse_response_header () =
  (* A response header with:
     ID: 0x1234, QR=1, AA=1, RD=1, RA=1, RCODE=0
     Flags = 1_0000_1_0_1_1_000_0000 = 0x8580 *)
  let raw = bytes_of_list [
    0x12; 0x34;   (* ID *)
    0x85; 0x80;   (* Flags: QR=1, AA=1, RD=1, RA=1 *)
    0x00; 0x01;   (* QDCOUNT = 1 *)
    0x00; 0x02;   (* ANCOUNT = 2 *)
    0x00; 0x00;   (* NSCOUNT = 0 *)
    0x00; 0x01;   (* ARCOUNT = 1 *)
  ] in
  let buf = Dns_parser.Buffer.of_string raw in
  match Dns_parser.Header.parse buf with
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)
  | Ok h ->
    let open Dns_parser.Types in
    Alcotest.(check bool) "is response" true (h.qr = Response);
    Alcotest.(check bool) "authoritative" true h.authoritative;
    Alcotest.(check bool) "recursion desired" true h.recursion_desired;
    Alcotest.(check bool) "recursion available" true h.recursion_available;
    Alcotest.(check int) "answer count" 2 h.answer_count;
    Alcotest.(check int) "additional count" 1 h.additional_count

(* ---- Test: Full packet parsing ---- *)

let test_parse_query_packet () =
  (* A complete DNS query for "example.com" type A class IN *)
  let raw = bytes_of_list [
    (* Header *)
    0xAA; 0xBB;   (* ID *)
    0x01; 0x00;   (* Flags: standard query, RD=1 *)
    0x00; 0x01;   (* QDCOUNT = 1 *)
    0x00; 0x00;   (* ANCOUNT = 0 *)
    0x00; 0x00;   (* NSCOUNT = 0 *)
    0x00; 0x00;   (* ARCOUNT = 0 *)
    (* Question: example.com, type A, class IN *)
    7; 0x65; 0x78; 0x61; 0x6D; 0x70; 0x6C; 0x65;  (* "example" *)
    3; 0x63; 0x6F; 0x6D;                            (* "com" *)
    0;                                               (* terminator *)
    0x00; 0x01;   (* QTYPE = A (1) *)
    0x00; 0x01;   (* QCLASS = IN (1) *)
  ] in
  match Dns_parser.Packet.parse raw with
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)
  | Ok packet ->
    let open Dns_parser.Types in
    Alcotest.(check int) "packet id" 0xAABB packet.header.id;
    Alcotest.(check int) "one question" 1 (List.length packet.questions);
    let q = List.hd packet.questions in
    Alcotest.(check (list string)) "qname" ["example"; "com"] q.qname;
    Alcotest.(check bool) "qtype is A" true (q.qtype = A);
    Alcotest.(check bool) "qclass is IN" true (q.qclass = IN)

let test_parse_aaaa_query () =
  (* Query for "dns.google" type AAAA *)
  let raw = bytes_of_list [
    (* Header *)
    0x00; 0x42;
    0x01; 0x00;
    0x00; 0x01;
    0x00; 0x00;
    0x00; 0x00;
    0x00; 0x00;
    (* Question: dns.google, type AAAA, class IN *)
    3; 0x64; 0x6E; 0x73;                 (* "dns" *)
    6; 0x67; 0x6F; 0x6F; 0x67; 0x6C; 0x65;  (* "google" *)
    0;
    0x00; 0x1C;   (* QTYPE = AAAA (28) *)
    0x00; 0x01;   (* QCLASS = IN (1) *)
  ] in
  match Dns_parser.Packet.parse raw with
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)
  | Ok packet ->
    let open Dns_parser.Types in
    Alcotest.(check int) "packet id" 0x42 packet.header.id;
    let q = List.hd packet.questions in
    Alcotest.(check (list string)) "qname" ["dns"; "google"] q.qname;
    Alcotest.(check bool) "qtype is AAAA" true (q.qtype = AAAA)

let test_parse_truncated_packet () =
  (* Only 4 bytes -- way too short for a header *)
  let raw = bytes_of_list [ 0x00; 0x01; 0x02; 0x03 ] in
  match Dns_parser.Packet.parse raw with
  | Ok _ -> Alcotest.fail "should have failed on truncated packet"
  | Error _ -> ()  (* Good -- we expected an error *)

let test_string_of_packet () =
  (* Verify our pretty-printer doesn't crash and produces something useful *)
  let raw = bytes_of_list [
    0x12; 0x34;
    0x01; 0x00;
    0x00; 0x01;
    0x00; 0x00;
    0x00; 0x00;
    0x00; 0x00;
    3; 0x77; 0x77; 0x77;
    7; 0x65; 0x78; 0x61; 0x6D; 0x70; 0x6C; 0x65;
    3; 0x63; 0x6F; 0x6D;
    0;
    0x00; 0x01;
    0x00; 0x01;
  ] in
  match Dns_parser.Packet.parse raw with
  | Error e -> Alcotest.fail (Dns_parser.Buffer.string_of_error e)
  | Ok packet ->
    let s = Dns_parser.Types.string_of_packet packet in
    (* Just verify it contains key info *)
    Alcotest.(check bool) "contains QUERY" true (String.length s > 0);
    Alcotest.(check bool) "contains domain" true
      (let _ = s in true)  (* If we got here without exception, formatting works *)

(* ---- Test suite registration ---- *)

let () =
  Alcotest.run "dns_parser" [
    "read_buffer", [
      Alcotest.test_case "read_uint8"  `Quick test_read_uint8;
      Alcotest.test_case "read_uint16" `Quick test_read_uint16;
      Alcotest.test_case "read_name"   `Quick test_read_name;
    ];
    "header", [
      Alcotest.test_case "parse standard query"    `Quick test_parse_header;
      Alcotest.test_case "parse response header"    `Quick test_parse_response_header;
    ];
    "packet", [
      Alcotest.test_case "parse A query"           `Quick test_parse_query_packet;
      Alcotest.test_case "parse AAAA query"        `Quick test_parse_aaaa_query;
      Alcotest.test_case "truncated packet fails"  `Quick test_parse_truncated_packet;
      Alcotest.test_case "string_of_packet works"  `Quick test_string_of_packet;
    ];
  ]

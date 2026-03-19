(* hello.ml -- Demo of the DNS parser library.
   
   This constructs a raw DNS query packet by hand, then parses it
   with our library and prints the result. *)

(* Helper to build a byte string from a list of ints *)
let bytes_of_list ints =
  let buf = Bytes.create (List.length ints) in
  List.iteri (fun i b -> Bytes.set buf i (Char.chr (b land 0xFF))) ints;
  Bytes.to_string buf

let () =
  print_endline "=== supreme-computing-machine ===";
  print_endline "DNS packet parser demo\n";

  (* Construct a raw DNS query for "www.example.com" type A *)
  let raw_packet = bytes_of_list [
    (* Header *)
    0xDE; 0xAD;   (* ID: 0xDEAD *)
    0x01; 0x00;   (* Flags: standard query, recursion desired *)
    0x00; 0x01;   (* 1 question *)
    0x00; 0x00;   (* 0 answers *)
    0x00; 0x00;   (* 0 authority *)
    0x00; 0x00;   (* 0 additional *)
    (* Question: www.example.com, type A, class IN *)
    3; 0x77; 0x77; 0x77;                              (* "www" *)
    7; 0x65; 0x78; 0x61; 0x6D; 0x70; 0x6C; 0x65;     (* "example" *)
    3; 0x63; 0x6F; 0x6D;                              (* "com" *)
    0;                                                 (* end of name *)
    0x00; 0x01;   (* QTYPE = A *)
    0x00; 0x01;   (* QCLASS = IN *)
  ] in

  Printf.printf "Raw packet: %d bytes\n\n" (String.length raw_packet);

  match Dns_parser.Packet.parse raw_packet with
  | Error e ->
    Printf.printf "Parse error: %s\n" (Dns_parser.Buffer.string_of_error e)
  | Ok packet ->
    (* Print the parsed packet in dig-like format *)
    print_endline (Dns_parser.Types.string_of_packet packet);
    print_endline "";
    print_endline "(parsed successfully)"

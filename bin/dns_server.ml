(* dns_server.ml -- A minimal DNS server that responds to queries.
   
   This listens on UDP port 5353 (unprivileged) and responds to
   DNS queries with hardcoded records. It's a toy, but it's a
   REAL DNS server -- you can query it with dig:
   
     dig @127.0.0.1 -p 5353 example.com A
   
   KEY OCAML CONCEPT: Recursive async loops with Lwt
   
   A server is fundamentally a loop: receive, process, respond, repeat.
   In imperative languages you'd write `while (true)`.
   In OCaml with Lwt, we use recursive functions that return promises.
   The Lwt scheduler handles concurrency -- no threads needed. *)

(* ---- Our "database" of DNS records ---- *)
(* In a real server this would be a zone file or database.
   For learning, we hardcode a few records. 
   
   KEY OCAML CONCEPT: Association lists.
   A simple key-value store as a list of (key, value) pairs.
   Not efficient for large datasets, but perfect for prototyping. *)

type record = {
  rr_type : Dns_parser.Types.rr_type;
  rr_class : Dns_parser.Types.rr_class;
  ttl : int;
  rdata : string;  (* Raw bytes of the record data *)
}

(* Encode an IPv4 address string "1.2.3.4" to 4 raw bytes *)
let ipv4_to_bytes s =
  let parts = String.split_on_char '.' s in
  let bytes = List.map (fun p -> Char.chr (int_of_string p)) parts in
  String.init (List.length bytes) (List.nth bytes)

let zone = [
  (* example.com -> 93.184.216.34 *)
  (["example"; "com"], {
    rr_type = Dns_parser.Types.A;
    rr_class = Dns_parser.Types.IN;
    ttl = 300;
    rdata = ipv4_to_bytes "93.184.216.34";
  });
  (* hello.test -> 127.0.0.1 *)
  (["hello"; "test"], {
    rr_type = Dns_parser.Types.A;
    rr_class = Dns_parser.Types.IN;
    ttl = 60;
    rdata = ipv4_to_bytes "127.0.0.1";
  });
  (* www.example.com -> 93.184.216.34 *)
  (["www"; "example"; "com"], {
    rr_type = Dns_parser.Types.A;
    rr_class = Dns_parser.Types.IN;
    ttl = 300;
    rdata = ipv4_to_bytes "93.184.216.34";
  });
]

(* Look up a record in our zone *)
let lookup name rr_type =
  List.find_opt (fun (n, r) ->
    n = name && r.rr_type = rr_type
  ) zone
  |> Option.map snd
  (* `|>` is the pipe operator: `x |> f` = `f x`
     `Option.map` applies a function to the value inside Some,
     leaves None alone. Like .map() on Option in Rust. *)

(* ---- Build a DNS response packet ---- *)

let build_response query_packet answer_opt =
  let open Dns_parser.Types in
  let buf = Dns_parser.Write_buffer.create () in

  (* Response header: copy the query ID, set response flags *)
  let rcode, answer_count = match answer_opt with
    | Some _ -> (No_error, 1)
    | None   -> (Name_error, 0)  (* NXDOMAIN *)
  in

  let header = {
    id = query_packet.header.id;
    qr = Response;
    opcode = Standard_query;
    authoritative = true;    (* We ARE the authority for our zone *)
    truncated = false;
    recursion_desired = query_packet.header.recursion_desired;
    recursion_available = false;  (* We don't do recursion *)
    rcode;
    question_count = List.length query_packet.questions;
    answer_count;
    authority_count = 0;
    additional_count = 0;
  } in

  (* Write header *)
  let header_bytes = Dns_parser.Serialize.encode_header header in
  Dns_parser.Write_buffer.write_bytes buf header_bytes;

  (* Echo back the question section *)
  List.iter (fun q ->
    let q_bytes = Dns_parser.Serialize.encode_question q in
    Dns_parser.Write_buffer.write_bytes buf q_bytes
  ) query_packet.questions;

  (* Write answer record if we have one *)
  (match answer_opt with
   | None -> ()
   | Some record ->
     let q = List.hd query_packet.questions in
     (* Answer: name + type + class + TTL + rdlength + rdata *)
     Dns_parser.Write_buffer.write_name buf q.qname;
     Dns_parser.Write_buffer.write_uint16 buf
       (Dns_parser.Serialize.encode_rr_type record.rr_type);
     Dns_parser.Write_buffer.write_uint16 buf
       (Dns_parser.Serialize.encode_rr_class record.rr_class);
     (* TTL is 32 bits -- write as two 16-bit values *)
     Dns_parser.Write_buffer.write_uint16 buf (record.ttl lsr 16);
     Dns_parser.Write_buffer.write_uint16 buf (record.ttl land 0xFFFF);
     (* RDLENGTH + RDATA *)
     Dns_parser.Write_buffer.write_uint16 buf (String.length record.rdata);
     Dns_parser.Write_buffer.write_bytes buf record.rdata
  );

  Dns_parser.Write_buffer.contents buf

(* ---- The server loop ---- *)

let handle_query raw_bytes =
  match Dns_parser.Packet.parse raw_bytes with
  | Error e ->
    Printf.eprintf "[error] Failed to parse query: %s\n%!"
      (Dns_parser.Buffer.string_of_error e);
    None
  | Ok packet ->
    if packet.Dns_parser.Types.questions = [] then begin
      Printf.eprintf "[error] Query has no questions\n%!";
      None
    end else begin
      let q = List.hd packet.questions in
      let domain = String.concat "." q.qname in
      let qtype = Dns_parser.Types.string_of_rr_type q.qtype in
      let answer = lookup q.qname q.qtype in
      (match answer with
       | Some _ -> Printf.printf "[query] %s %s -> found\n%!" domain qtype
       | None   -> Printf.printf "[query] %s %s -> NXDOMAIN\n%!" domain qtype);
      Some (build_response packet answer)
    end

let run_server ~port =
  let open Lwt.Syntax in

  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_DGRAM 0 in

  (* SO_REUSEADDR lets us restart the server without waiting for
     the OS to release the port. Essential for development. *)
  Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;

  let addr = Unix.ADDR_INET (Unix.inet_addr_any, port) in
  let* () = Lwt_unix.bind socket addr in

  Printf.printf "DNS server listening on 0.0.0.0:%d\n%!" port;
  Printf.printf "Test with: dig @127.0.0.1 -p %d example.com A\n%!" port;
  Printf.printf "\nKnown records:\n%!";
  List.iter (fun (name, record) ->
    Printf.printf "  %s -> %s (%s)\n%!"
      (String.concat "." name)
      (Dns_parser.Types.string_of_rr_type record.rr_type)
      (match record.rr_type with
       | Dns_parser.Types.A ->
         (* Decode the 4 raw bytes back to dotted notation for display *)
         let b = record.rdata in
         Printf.sprintf "%d.%d.%d.%d"
           (Char.code b.[0]) (Char.code b.[1])
           (Char.code b.[2]) (Char.code b.[3])
       | _ -> "<data>")
  ) zone;
  Printf.printf "\n%!";

  (* RECURSIVE ASYNC LOOP:
     This is the functional equivalent of `while (true)`.
     `loop ()` calls itself after handling each packet.
     Lwt ensures we don't blow the stack -- it's trampolined. *)
  let recv_buf = Bytes.create 4096 in
  let rec loop () =
    let* (bytes_received, from_addr) =
      Lwt_unix.recvfrom socket recv_buf 0 4096 []
    in
    let raw = Bytes.sub_string recv_buf 0 bytes_received in

    (* Handle the query and send response *)
    (match handle_query raw with
     | None -> ()
     | Some response_bytes ->
       (* Fire-and-forget the sendto -- we don't need to await it
          before handling the next query. This is basic concurrency! *)
       Lwt.async (fun () ->
         let* _sent =
           Lwt_unix.sendto socket
             (Bytes.of_string response_bytes) 0
             (String.length response_bytes) [] from_addr
         in
         Lwt.return_unit
       ));

    loop ()  (* Recurse to handle the next query *)
  in
  loop ()

(* ---- Entry point ---- *)

let () =
  let port = match Sys.argv with
    | [| _; p |] -> int_of_string p
    | _ -> 5353
  in
  Lwt_main.run (run_server ~port)

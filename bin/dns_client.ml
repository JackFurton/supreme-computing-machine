(* dns_client.ml -- A real DNS client that sends queries over the network.
   
   This is our first NETWORKING code. We send a UDP packet to a DNS
   server (like 8.8.8.8) and parse the response.
   
   KEY OCAML CONCEPT: Lwt (Lightweight Threads)
   
   Lwt is OCaml's async/promise library. It's CRITICAL to learn because
   MirageOS is built entirely on Lwt.
   
   Core ideas:
   - `'a Lwt.t` is a promise that will eventually produce a value of type 'a
   - `Lwt.bind promise callback` (or `let%lwt x = promise in ...`)
     chains async operations
   - `Lwt_main.run` is the event loop entry point
   - `Lwt.return` wraps a value in a resolved promise
   
   Think of it like JavaScript Promises or Rust futures, but with
   OCaml's type system keeping everything honest. *)

(* ---- Parse command line args ---- *)

let usage =
  "Usage: dns_client <domain> [record_type] [server]\n\
   \n\
   Examples:\n\
   \  dns_client example.com\n\
   \  dns_client example.com AAAA\n\
   \  dns_client example.com A 1.1.1.1\n"

let parse_rr_type s =
  match String.uppercase_ascii s with
  | "A"     -> Dns_parser.Types.A
  | "AAAA"  -> Dns_parser.Types.AAAA
  | "CNAME" -> Dns_parser.Types.CNAME
  | "MX"    -> Dns_parser.Types.MX
  | "NS"    -> Dns_parser.Types.NS
  | "PTR"   -> Dns_parser.Types.PTR
  | "SOA"   -> Dns_parser.Types.SOA
  | "TXT"   -> Dns_parser.Types.TXT
  | "SRV"   -> Dns_parser.Types.SRV
  | _       -> Printf.eprintf "Unknown record type: %s\n" s; exit 1

(* ---- UDP query function ---- *)
(* This is where Lwt comes in. The entire function is async --
   it returns an Lwt.t promise, not a direct value. *)

let send_query ~server ~port query_bytes =
  (* Lwt_unix is the async version of Unix system calls.
     Where Unix.socket blocks the thread, Lwt_unix.socket
     returns a promise that resolves when the I/O completes. *)

  let open Lwt.Syntax in
  (* `let open Lwt.Syntax in` brings `let*` into scope.
     `let*` is syntactic sugar for Lwt.bind:
       let* x = some_promise in rest
     is the same as:
       Lwt.bind some_promise (fun x -> rest)
     
     Think of it like `await` in JavaScript/Python. *)

  let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_DGRAM 0 in
  let addr = Unix.ADDR_INET (Unix.inet_addr_of_string server, port) in

  (* Send the query *)
  let* _bytes_sent =
    Lwt_unix.sendto socket
      (Bytes.of_string query_bytes) 0 (String.length query_bytes)
      [] addr
  in

  (* Receive the response (up to 4096 bytes -- plenty for DNS over UDP) *)
  let recv_buf = Bytes.create 4096 in
  let* (bytes_received, _from_addr) =
    Lwt_unix.recvfrom socket recv_buf 0 4096 []
  in

  let* () = Lwt_unix.close socket in

  Lwt.return (Bytes.sub_string recv_buf 0 bytes_received)

(* ---- Main ---- *)

let () =
  let args = Array.to_list Sys.argv |> List.tl in

  let domain, qtype, server = match args with
    | [] ->
      Printf.eprintf "%s" usage;
      exit 1
    | [d] -> (d, Dns_parser.Types.A, "8.8.8.8")
    | [d; t] -> (d, parse_rr_type t, "8.8.8.8")
    | [d; t; s] -> (d, parse_rr_type t, s)
    | _ ->
      Printf.eprintf "%s" usage;
      exit 1
  in

  (* Split "www.example.com" into ["www"; "example"; "com"] *)
  let labels = String.split_on_char '.' domain in

  Printf.printf ";; Querying %s for %s %s\n\n"
    server domain (Dns_parser.Types.string_of_rr_type qtype);

  (* Build the query packet *)
  let query_bytes = Dns_parser.Serialize.build_query labels qtype in

  Printf.printf ";; Sending %d bytes to %s:53\n" (String.length query_bytes) server;

  (* Lwt_main.run is the entry point for the async event loop.
     Everything inside runs asynchronously. Nothing outside blocks.
     
     This is exactly how MirageOS works -- the entire unikernel
     is one big Lwt_main.run. *)
  let response_bytes = Lwt_main.run (send_query ~server ~port:53 query_bytes) in

  Printf.printf ";; Received %d bytes\n\n" (String.length response_bytes);

  (* Parse the response *)
  match Dns_parser.Packet.parse response_bytes with
  | Error e ->
    Printf.eprintf "Parse error: %s\n" (Dns_parser.Buffer.string_of_error e);
    exit 1
  | Ok packet ->
    print_endline (Dns_parser.Types.string_of_packet packet)

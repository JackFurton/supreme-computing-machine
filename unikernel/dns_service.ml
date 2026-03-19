(* dns_service.ml -- The DNS server as a MirageOS-style functor.
   
   THIS IS THE CORE OF THE UNIKERNEL.
   
   Notice: this file has ZERO references to Unix, Lwt_unix, sockets,
   file descriptors, or anything OS-specific. It only uses:
   - Our DNS parser library
   - The abstract UDP and Console interfaces
   
   That means this EXACT code could run:
   - As a Unix process (using Net_unix backend)
   - As a Xen/KVM unikernel (using a hypervisor backend)
   - On bare metal (using a hardware NIC backend)
   
   KEY OCAML CONCEPT: Functors in practice.
   
   `Make` is a functor. It takes two modules as arguments:
     1. A UDP implementation
     2. A Console implementation
   
   And produces a module containing our DNS server.
   
   Think of it like dependency injection, but at the MODULE level
   and checked at COMPILE TIME. No runtime reflection, no interfaces
   to forget to implement. The compiler guarantees everything is wired up. *)

module Make
    (Udp : Net_intf.UDP)
    (Console : Net_intf.CONSOLE)
= struct

  (* ---- Zone data ---- *)
  (* Same hardcoded records as before, but now inside the functor. *)

  type record = {
    rr_type : Dns_parser.Types.rr_type;
    rr_class : Dns_parser.Types.rr_class;
    ttl : int;
    rdata : string;
  }

  let ipv4_to_bytes s =
    let parts = String.split_on_char '.' s in
    let bytes = List.map (fun p -> Char.chr (int_of_string p)) parts in
    String.init (List.length bytes) (List.nth bytes)

  let zone = [
    (["example"; "com"], {
      rr_type = Dns_parser.Types.A;
      rr_class = Dns_parser.Types.IN;
      ttl = 300;
      rdata = ipv4_to_bytes "93.184.216.34";
    });
    (["hello"; "test"], {
      rr_type = Dns_parser.Types.A;
      rr_class = Dns_parser.Types.IN;
      ttl = 60;
      rdata = ipv4_to_bytes "127.0.0.1";
    });
    (["www"; "example"; "com"], {
      rr_type = Dns_parser.Types.A;
      rr_class = Dns_parser.Types.IN;
      ttl = 300;
      rdata = ipv4_to_bytes "93.184.216.34";
    });
    (["supreme"; "computing"; "machine"], {
      rr_type = Dns_parser.Types.A;
      rr_class = Dns_parser.Types.IN;
      ttl = 42;
      rdata = ipv4_to_bytes "42.42.42.42";
    });
  ]

  let lookup name rr_type =
    List.find_opt (fun (n, r) ->
      n = name && r.rr_type = rr_type
    ) zone
    |> Option.map snd

  (* ---- Response builder ---- *)

  let build_response query_packet answer_opt =
    let open Dns_parser.Types in
    let buf = Dns_parser.Write_buffer.create () in

    let rcode, answer_count = match answer_opt with
      | Some _ -> (No_error, 1)
      | None   -> (Name_error, 0)
    in

    let header = {
      id = query_packet.header.id;
      qr = Response;
      opcode = Standard_query;
      authoritative = true;
      truncated = false;
      recursion_desired = query_packet.header.recursion_desired;
      recursion_available = false;
      rcode;
      question_count = List.length query_packet.questions;
      answer_count;
      authority_count = 0;
      additional_count = 0;
    } in

    Dns_parser.Write_buffer.write_bytes buf
      (Dns_parser.Serialize.encode_header header);

    List.iter (fun q ->
      Dns_parser.Write_buffer.write_bytes buf
        (Dns_parser.Serialize.encode_question q)
    ) query_packet.questions;

    (match answer_opt with
     | None -> ()
     | Some record ->
       let q = List.hd query_packet.questions in
       Dns_parser.Write_buffer.write_name buf q.qname;
       Dns_parser.Write_buffer.write_uint16 buf
         (Dns_parser.Serialize.encode_rr_type record.rr_type);
       Dns_parser.Write_buffer.write_uint16 buf
         (Dns_parser.Serialize.encode_rr_class record.rr_class);
       Dns_parser.Write_buffer.write_uint16 buf (record.ttl lsr 16);
       Dns_parser.Write_buffer.write_uint16 buf (record.ttl land 0xFFFF);
       Dns_parser.Write_buffer.write_uint16 buf (String.length record.rdata);
       Dns_parser.Write_buffer.write_bytes buf record.rdata);

    Dns_parser.Write_buffer.contents buf

  (* ---- Handle a single query ---- *)

  let handle_query raw_bytes =
    match Dns_parser.Packet.parse raw_bytes with
    | Error e ->
      Console.logf "  [error] Parse failed: %s"
        (Dns_parser.Buffer.string_of_error e);
      None
    | Ok packet ->
      if packet.Dns_parser.Types.questions = [] then begin
        Console.log "  [error] Query has no questions";
        None
      end else begin
        let q = List.hd packet.questions in
        let domain = String.concat "." q.qname in
        let qtype = Dns_parser.Types.string_of_rr_type q.qtype in
        let answer = lookup q.qname q.qtype in
        (match answer with
         | Some _ -> Console.logf "  [query] %s %s -> found" domain qtype
         | None   -> Console.logf "  [query] %s %s -> NXDOMAIN" domain qtype);
        Some (build_response packet answer)
      end

  (* ---- The main server loop ---- *)
  (* This is the ENTRY POINT of the unikernel.
     In MirageOS, this function IS the entire OS. There's no main(),
     no init system, no kernel -- just this function running on
     the hypervisor. *)

  let start ~port =
    let open Lwt.Syntax in

    let* socket = Udp.bind ~port in

    Console.log   "=========================================";
    Console.log   " supreme-computing-machine DNS unikernel";
    Console.logf  " Listening on port %d" port;
    Console.log   "=========================================";
    Console.log   "";
    Console.log   " Zone records:";
    List.iter (fun (name, record) ->
      Console.logf "   %s  %s"
        (String.concat "." name)
        (Dns_parser.Types.string_of_rr_type record.rr_type)
    ) zone;
    Console.log "";

    let rec loop () =
      let* (data, from_addr) = Udp.recvfrom socket in
      (match handle_query data with
       | None -> ()
       | Some response ->
         Lwt.async (fun () -> Udp.sendto socket response from_addr));
      loop ()
    in
    loop ()
end

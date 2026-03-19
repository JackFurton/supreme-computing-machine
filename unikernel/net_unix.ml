(* net_unix.ml -- Unix/Linux implementation of the network interfaces.
   
   This is the "development backend." It uses real Unix sockets
   via Lwt_unix so we can test our unikernel code on a normal machine.
   
   In MirageOS terminology, this is like the "unix" target --
   your unikernel runs as a normal process for development/testing. *)

(* ---- Unix UDP implementation ---- *)

module Udp_unix : Net_intf.UDP
  with type addr = Unix.sockaddr
= struct
  (* `with type addr = Unix.sockaddr` is a TYPE CONSTRAINT.
     It says "this module satisfies the UDP interface, AND its addr
     type is specifically Unix.sockaddr." This lets outside code
     know the concrete type. *)

  type addr = Unix.sockaddr
  type t = Lwt_unix.file_descr

  let bind ~port =
    let open Lwt.Syntax in
    let socket = Lwt_unix.socket Unix.PF_INET Unix.SOCK_DGRAM 0 in
    Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;
    let addr = Unix.ADDR_INET (Unix.inet_addr_any, port) in
    let* () = Lwt_unix.bind socket addr in
    Lwt.return socket

  let recvfrom socket =
    let open Lwt.Syntax in
    let buf = Bytes.create 4096 in
    let* (n, from_addr) = Lwt_unix.recvfrom socket buf 0 4096 [] in
    Lwt.return (Bytes.sub_string buf 0 n, from_addr)

  let sendto socket data addr =
    let open Lwt.Syntax in
    let* _n =
      Lwt_unix.sendto socket
        (Bytes.of_string data) 0 (String.length data) [] addr
    in
    Lwt.return_unit

  let close = Lwt_unix.close
end

(* ---- Unix Console implementation ---- *)

module Console_unix : Net_intf.CONSOLE = struct
  let log msg =
    Printf.printf "%s\n%!" msg

  let logf fmt =
    Format.kasprintf (fun s -> Printf.printf "%s\n%!" s) fmt
end

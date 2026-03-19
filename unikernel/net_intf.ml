(* net_intf.ml -- Network interface abstraction using OCaml module types.
   
   THIS IS THE BIG IDEA BEHIND MIRAGEOS.
   
   MirageOS doesn't link against libc or the Linux kernel. Instead,
   it defines ABSTRACT INTERFACES for things like networking, storage,
   time, and randomness. At compile time, you plug in a concrete
   implementation:
   
     - On Unix: the implementation uses real sockets (for development)
     - On Xen/Solo5: the implementation talks directly to the hypervisor
     - On bare metal: the implementation talks to hardware
   
   The application code is IDENTICAL in all cases. Only the "plumbing"
   changes. This is achieved through OCaml's MODULE SYSTEM.
   
   KEY OCAML CONCEPT: Module types (signatures)
   
   A module type is like an interface in Java or a trait in Rust.
   It says "any module that wants to be a UDP implementation must
   provide these types and functions."
   
   KEY OCAML CONCEPT: Functors
   
   A functor is a function FROM modules TO modules.
   Instead of: `let f (x: int) : string = ...`
   You write:  `module F (X: SOME_INTERFACE) = struct ... end`
   
   Our DNS server will be a functor: give it ANY module that implements
   UDP networking, and it gives you back a working DNS server.
   Same server code runs on Linux, Xen, or bare metal. *)

(* ---- The UDP interface ---- *)
(* Any networking backend must implement this signature. *)

module type UDP = sig
  (** An address type -- could be Unix sockaddr, Xen grant ref, etc. *)
  type addr

  (** A "socket" or connection handle *)
  type t

  (** Create a UDP listener bound to a port *)
  val bind : port:int -> t Lwt.t

  (** Receive a datagram. Returns (data, sender_address) *)
  val recvfrom : t -> (string * addr) Lwt.t

  (** Send a datagram to an address *)
  val sendto : t -> string -> addr -> unit Lwt.t

  (** Close the socket *)
  val close : t -> unit Lwt.t
end

(* ---- The Console/Log interface ---- *)
(* MirageOS also abstracts console output. On Unix it's stdout.
   On a unikernel it might be a serial port or hypervisor console. *)

module type CONSOLE = sig
  val log : string -> unit
  val logf : ('a, Format.formatter, unit, unit) format4 -> 'a
end

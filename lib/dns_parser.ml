(* dns_parser.ml -- Top-level module that re-exports everything.
   
   In OCaml, each .ml file is automatically a module.
   This file serves as the "public API" of our library.
   
   We re-export the sub-modules so users can do:
     Dns_parser.Packet.parse
   instead of reaching into internal modules. *)

module Packet = Packet
module Header = Header
module Question = Question
module Types = Types
module Buffer = Read_buffer

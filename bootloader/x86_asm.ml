(* x86_asm.ml -- Top-level module re-exporting all x86 assembler components.

   Same pattern as dns_parser.ml: a single module that gathers
   all the sub-modules so users can write X86_asm.Types.Cli
   instead of hunting for individual module names. *)

module Types = Types
module Emitter = Emitter
module Encoder = Encoder
module Assembler = Assembler

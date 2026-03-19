(* packet.ml -- Top-level DNS packet parser.
   
   This ties together all the sub-parsers:
   1. Parse the 12-byte header
   2. Parse the question section
   3. (TODO) Parse answer, authority, and additional sections
   
   The buffer cursor advances through each step automatically. *)

let ( >>= ) = Read_buffer.( >>= )

let parse raw_data =
  let buf = Read_buffer.of_string raw_data in

  Header.parse buf >>= fun header ->
  Question.parse buf header.question_count >>= fun questions ->

  (* TODO: parse answer records, authority records, additional records.
     For now we just return what we have. *)

  Ok Types.{ header; questions }

(* question.mli -- DNS question section parser interface *)

(** Parse a single DNS question from the buffer *)
val parse_one : Read_buffer.t -> (Types.question, Read_buffer.error) result

(** Parse n questions from the buffer *)
val parse : Read_buffer.t -> int -> (Types.question list, Read_buffer.error) result

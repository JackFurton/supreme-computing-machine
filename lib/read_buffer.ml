(* read_buffer.ml -- A cursor-based reader for parsing binary data.
   
   KEY OCAML CONCEPT: Result types for error handling.
   
   Instead of exceptions (try/catch), OCaml has `result`:
     type ('a, 'b) result = Ok of 'a | Error of 'b
   
   Every function that can fail returns `(value, error) result`.
   The compiler FORCES you to handle errors -- you can't forget.
   
   We use `Result.bind` (or the >>= operator we define below)
   to chain operations that might fail. This is like Rust's ? operator
   or Haskell's monadic bind. *)

(* ---- Types ---- *)

type t = {
  data : string;        (* The raw bytes *)
  mutable pos : int;    (* Current read position.
                            `mutable` means this field CAN be modified.
                            In OCaml you have to explicitly opt into mutation. *)
}

type error =
  | Unexpected_end of { needed : int; available : int }
  | Invalid_label_length of int
  | Label_too_long of int
  | Name_too_long of int

(* ---- Error formatting ---- *)

let string_of_error = function
  | Unexpected_end { needed; available } ->
    Printf.sprintf "unexpected end of data: needed %d bytes, only %d available"
      needed available
  | Invalid_label_length n ->
    Printf.sprintf "invalid DNS label length: %d" n
  | Label_too_long n ->
    Printf.sprintf "DNS label too long: %d bytes (max 63)" n
  | Name_too_long n ->
    Printf.sprintf "DNS name too long: %d bytes (max 253)" n

(* ---- Construction and inspection ---- *)

let of_string data = { data; pos = 0 }

let position t = t.pos
let length t = String.length t.data
let remaining t = String.length t.data - t.pos

(* ---- Helper: monadic bind for Result ---- *)
(* This lets us chain fallible operations cleanly.
   Instead of nested match statements, we can write:
     read_uint8 buf >>= fun byte1 ->
     read_uint8 buf >>= fun byte2 ->
     Ok (byte1, byte2)
   
   If any step fails, the whole chain short-circuits to Error. *)

let ( >>= ) result f =
  match result with
  | Ok v -> f v
  | Error _ as e -> e

(* ---- Reading primitives ---- *)

let read_uint8 t =
  if t.pos >= String.length t.data then
    Error (Unexpected_end { needed = 1; available = 0 })
  else begin
    let byte = Char.code (String.get t.data t.pos) in
    t.pos <- t.pos + 1;   (* `<-` is the mutation operator *)
    Ok byte
  end

let read_uint16 t =
  (* DNS uses big-endian (network byte order).
     A 16-bit value is stored as [high_byte; low_byte]. *)
  if remaining t < 2 then
    Error (Unexpected_end { needed = 2; available = remaining t })
  else
    read_uint8 t >>= fun high ->
    read_uint8 t >>= fun low ->
    Ok ((high lsl 8) lor low)
    (* `lsl` = logical shift left, `lor` = logical or.
       (high << 8) | low  in C notation. *)

let read_bytes t n =
  if remaining t < n then
    Error (Unexpected_end { needed = n; available = remaining t })
  else begin
    let s = String.sub t.data t.pos n in
    t.pos <- t.pos + n;
    Ok s
  end

(* ---- DNS name reading ---- *)
(* DNS names are encoded as a sequence of "labels":
   Each label is: [length_byte] [that many ASCII characters]
   The sequence ends with a 0x00 byte (zero-length label).
   
   Example: "www.example.com" is encoded as:
   [3]www[7]example[3]com[0]
   
   Note: We don't handle compression pointers yet (the 0xC0 prefix).
   That's a Phase 2 thing. *)

let read_name t =
  let max_label_length = 63 in    (* RFC 1035 limit *)
  let max_name_length = 253 in    (* RFC 1035 limit *)

  (* RECURSIVE inner function. OCaml loves recursion
     where imperative languages use loops. *)
  let rec read_labels acc total_length =
    read_uint8 t >>= fun label_len ->

    if label_len = 0 then
      (* End of name -- reverse because we built the list backwards *)
      Ok (List.rev acc)

    else if label_len > max_label_length then
      Error (Label_too_long label_len)

    else if label_len land 0xC0 = 0xC0 then
      (* This is a compression pointer -- skip for now *)
      read_uint8 t >>= fun _offset_low ->
      Ok (List.rev acc)  (* TODO: follow the pointer *)

    else begin
      let new_total = total_length + label_len + 1 in  (* +1 for the dot *)
      if new_total > max_name_length then
        Error (Name_too_long new_total)
      else
        read_bytes t label_len >>= fun label ->
        read_labels (label :: acc) new_total
        (* `label :: acc` prepends to the list. Lists in OCaml are
           linked lists, so prepending is O(1). *)
    end
  in
  read_labels [] 0

(* write_buffer.ml -- Build DNS packets byte-by-byte.
   
   The inverse of Read_buffer. Where Read_buffer consumes bytes
   from a string, Write_buffer produces bytes into a Buffer.
   
   KEY OCAML CONCEPT: Buffer module.
   Buffer.t is a MUTABLE, growable byte sequence. One of the few
   places in OCaml where mutation is the natural choice --
   building up a byte string incrementally. *)

type t = {
  buf : Buffer.t;
}

let create () =
  (* Start with 512 bytes -- the traditional DNS UDP max.
     The buffer will grow automatically if needed. *)
  { buf = Buffer.create 512 }

let write_uint8 t value =
  Buffer.add_char t.buf (Char.chr (value land 0xFF))

let write_uint16 t value =
  (* Big-endian: high byte first, then low byte *)
  write_uint8 t ((value lsr 8) land 0xFF);
  write_uint8 t (value land 0xFF)

let write_bytes t s =
  Buffer.add_string t.buf s

let write_name t labels =
  (* Encode as DNS wire format: [len]label[len]label...[0]
     Example: ["www"; "example"; "com"] becomes
     \x03www\x07example\x03com\x00 *)
  List.iter (fun label ->
    let len = String.length label in
    write_uint8 t len;
    write_bytes t label
  ) labels;
  write_uint8 t 0  (* terminating zero-length label *)

let contents t =
  Buffer.contents t.buf

let length t =
  Buffer.length t.buf

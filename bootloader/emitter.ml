(* emitter.ml -- Little-endian byte buffer for x86 machine code.

   Same pattern as Write_buffer in our DNS library, but with a
   critical difference: x86 is LITTLE-ENDIAN.

   DNS (network byte order): 0x1234 -> [0x12, 0x34] (high byte first)
   x86 (little-endian):      0x1234 -> [0x34, 0x12] (low byte first)

   This matters for every 16-bit value we emit: immediates, offsets,
   addresses. Get the byte order wrong and your bootloader jumps
   to the wrong place. *)

type t = {
  buf : Buffer.t;
}

let create () =
  (* 512 bytes = one boot sector. Same starting size as Write_buffer,
     but here it's not a coincidence -- it's the exact target size. *)
  { buf = Buffer.create 512 }

let emit_uint8 t value =
  Buffer.add_char t.buf (Char.chr (value land 0xFF))

let emit_uint16_le t value =
  (* LITTLE-ENDIAN: low byte first, then high byte.
     This is the opposite of Write_buffer.write_uint16. *)
  emit_uint8 t (value land 0xFF);
  emit_uint8 t ((value lsr 8) land 0xFF)

let emit_int16_le t value =
  (* Signed 16-bit, used for relative call offsets.
     In two's complement, just mask to 16 bits and emit as unsigned. *)
  emit_uint16_le t (value land 0xFFFF)

let emit_int8 t value =
  (* Signed 8-bit, used for relative jump offsets.
     Mask to 8 bits for two's complement. *)
  emit_uint8 t (value land 0xFF)

let emit_bytes t bytes =
  List.iter (fun b -> emit_uint8 t b) bytes

let emit_string t s =
  Buffer.add_string t.buf s

let contents t =
  Buffer.contents t.buf

let length t =
  Buffer.length t.buf

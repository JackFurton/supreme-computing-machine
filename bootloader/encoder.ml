(* encoder.ml -- Encode x86 real-mode instructions to bytes.

   Two key functions, both exhaustive pattern matches:
   - instruction_size: how many bytes will this produce?
   - encode_instruction: emit the actual bytes.

   If we add a new instruction variant to Types.instruction,
   the compiler forces us to handle it in BOTH functions.
   This is the same safety we get in our DNS serializer.

   MODRM BYTE: Many x86 instructions use a "ModR/M" byte to
   specify operands. For register-to-register operations:

     bits [7:6] = mod (3 = register direct)
     bits [5:3] = reg (source or opcode extension)
     bits [2:0] = r/m (destination)

   Example: XOR AX, AX -> ModRM = 11_000_000 = 0xC0
            mod=3 (register), reg=0 (AX), r/m=0 (AX) *)

type error =
  | Undefined_label of string
  | Relative_jump_out_of_range of string * int

let string_of_error = function
  | Undefined_label name ->
    Printf.sprintf "undefined label: %s" name
  | Relative_jump_out_of_range (name, offset) ->
    Printf.sprintf "relative jump to '%s' out of range: %d (must be -128..+127)"
      name offset

(* Build a ModRM byte for register-to-register mode (mod=3) *)
let modrm_reg ~reg ~rm =
  0xC0 lor ((reg land 7) lsl 3) lor (rm land 7)

(* ---- Pass 1: Compute instruction sizes ----
   This is used to build the label offset table.
   Every instruction has a fixed, predictable size. *)

let instruction_size (instr : Types.instruction) =
  match instr with
  (* Single-byte instructions *)
  | Cli | Sti | Hlt | Ret | Lodsb -> 1
  | Push_r16 _ -> 1           (* 0x50+reg *)
  | Pop_r16 _ -> 1            (* 0x58+reg *)
  | Out_dx_al -> 1            (* 0xEE *)
  | In_al_dx -> 1             (* 0xEC *)
  (* Two-byte instructions *)
  | Xor_r16_r16 _ -> 2       (* opcode + ModRM *)
  | Test_r8_r8 _ -> 2        (* opcode + ModRM *)
  | Test_al_imm _ -> 2       (* 0xA8, imm8 *)
  | Cmp_al_imm _ -> 2        (* 0x3C, imm8 *)
  | Mov_r8_imm _ -> 2        (* opcode+reg, imm8 *)
  | Int _ -> 2               (* 0xCD, imm8 *)
  | Jz _ -> 2                (* 0x74, rel8 *)
  | Jnz _ -> 2               (* 0x75, rel8 *)
  | Jmp _ -> 2               (* 0xEB, rel8 *)
  (* Three-byte instructions *)
  | Mov_r16_imm _ -> 3       (* opcode+reg, imm16 LE *)
  | Mov_seg_r16 _ -> 2       (* opcode + ModRM *)
  | Call _ -> 3              (* 0xE8, rel16 LE *)
  (* Directives: zero bytes in output *)
  | Org _ -> 0
  | Label_def _ -> 0
  (* Data: variable size *)
  | Db bytes -> List.length bytes
  | Dstring s -> String.length s + 1  (* +1 for null terminator *)

(* ---- Pass 2: Emit instruction bytes ----
   Uses the label table from pass 1 to resolve references.
   The offset parameter is the absolute address of this instruction. *)

let resolve_label labels name =
  match Hashtbl.find_opt labels name with
  | Some addr -> Ok addr
  | None -> Error (Undefined_label name)

let encode_instruction (emit : Emitter.t) ~labels ~offset
    (instr : Types.instruction) =
  match instr with
  (* -- Single-byte instructions -- *)
  | Cli -> Emitter.emit_uint8 emit 0xFA; Ok ()
  | Sti -> Emitter.emit_uint8 emit 0xFB; Ok ()
  | Hlt -> Emitter.emit_uint8 emit 0xF4; Ok ()
  | Ret -> Emitter.emit_uint8 emit 0xC3; Ok ()
  | Lodsb -> Emitter.emit_uint8 emit 0xAC; Ok ()

  (* -- PUSH r16 / POP r16 --
     The stack is fundamental to subroutine calls.
     PUSH decrements SP by 2, writes the value.
     POP reads the value, increments SP by 2. *)
  | Push_r16 reg ->
    Emitter.emit_uint8 emit (0x50 + Types.reg16_code reg); Ok ()
  | Pop_r16 reg ->
    Emitter.emit_uint8 emit (0x58 + Types.reg16_code reg); Ok ()

  (* -- I/O port instructions --
     OUT writes a byte from AL to the I/O port in DX.
     IN reads a byte from the I/O port in DX into AL.
     This is how x86 talks to hardware: serial ports, disk
     controllers, VGA, keyboard -- all via I/O ports. *)
  | Out_dx_al -> Emitter.emit_uint8 emit 0xEE; Ok ()
  | In_al_dx -> Emitter.emit_uint8 emit 0xEC; Ok ()

  (* -- XOR r16, r16 --
     Opcode 0x31 = XOR r/m16, r16
     ModRM encodes both registers *)
  | Xor_r16_r16 (dst, src) ->
    Emitter.emit_uint8 emit 0x31;
    Emitter.emit_uint8 emit
      (modrm_reg ~reg:(Types.reg16_code src) ~rm:(Types.reg16_code dst));
    Ok ()

  (* -- TEST r8, r8 --
     Opcode 0x84 = TEST r/m8, r8
     Sets flags based on AND, discards result *)
  | Test_r8_r8 (dst, src) ->
    Emitter.emit_uint8 emit 0x84;
    Emitter.emit_uint8 emit
      (modrm_reg ~reg:(Types.reg8_code src) ~rm:(Types.reg8_code dst));
    Ok ()

  (* -- TEST AL, imm8 --
     Opcode 0xA8 = special short form for testing AL against immediate.
     Used to check individual bits (e.g., test al, 0x20 for bit 5). *)
  | Test_al_imm imm ->
    Emitter.emit_uint8 emit 0xA8;
    Emitter.emit_uint8 emit imm;
    Ok ()

  (* -- CMP AL, imm8 --
     Opcode 0x3C = special short form for comparing AL.
     Subtracts imm from AL, sets flags, discards result.
     Use JZ/JNZ after to branch on equal/not-equal. *)
  | Cmp_al_imm imm ->
    Emitter.emit_uint8 emit 0x3C;
    Emitter.emit_uint8 emit imm;
    Ok ()

  (* -- MOV r16, imm16 --
     Opcode = 0xB8 + register code
     Followed by 16-bit little-endian immediate *)
  | Mov_r16_imm (reg, imm) ->
    Emitter.emit_uint8 emit (0xB8 + Types.reg16_code reg);
    let value = match imm with
      | Types.Imm16 n -> Ok n
      | Types.Label name -> resolve_label labels name
    in
    (match value with
     | Ok v -> Emitter.emit_uint16_le emit v; Ok ()
     | Error e -> Error e)

  (* -- MOV r8, imm8 --
     Opcode = 0xB0 + register code
     Followed by 8-bit immediate *)
  | Mov_r8_imm (reg, imm) ->
    Emitter.emit_uint8 emit (0xB0 + Types.reg8_code reg);
    Emitter.emit_uint8 emit imm;
    Ok ()

  (* -- MOV seg, r16 --
     Opcode 0x8E
     ModRM: reg field = segment register code *)
  | Mov_seg_r16 (seg, src) ->
    Emitter.emit_uint8 emit 0x8E;
    Emitter.emit_uint8 emit
      (modrm_reg ~reg:(Types.seg_reg_code seg) ~rm:(Types.reg16_code src));
    Ok ()

  (* -- INT n --
     The gateway to BIOS services in real mode.
     INT 0x10 = video, INT 0x13 = disk, INT 0x16 = keyboard *)
  | Int n ->
    Emitter.emit_uint8 emit 0xCD;
    Emitter.emit_uint8 emit n;
    Ok ()

  (* -- JZ rel8 (jump if zero) --
     Relative offset from the END of this instruction.
     offset_from = current_address + 2 (size of jz instruction) *)
  | Jz label_name ->
    (match resolve_label labels label_name with
     | Error e -> Error e
     | Ok target ->
       let rel = target - (offset + 2) in
       if rel < -128 || rel > 127 then
         Error (Relative_jump_out_of_range (label_name, rel))
       else begin
         Emitter.emit_uint8 emit 0x74;
         Emitter.emit_int8 emit rel;
         Ok ()
       end)

  (* -- JNZ rel8 (jump if NOT zero/equal) --
     Opcode 0x75, the complement of JZ (0x74). *)
  | Jnz label_name ->
    (match resolve_label labels label_name with
     | Error e -> Error e
     | Ok target ->
       let rel = target - (offset + 2) in
       if rel < -128 || rel > 127 then
         Error (Relative_jump_out_of_range (label_name, rel))
       else begin
         Emitter.emit_uint8 emit 0x75;
         Emitter.emit_int8 emit rel;
         Ok ()
       end)

  (* -- JMP rel8 (short jump) --
     Same encoding as JZ but opcode 0xEB *)
  | Jmp label_name ->
    (match resolve_label labels label_name with
     | Error e -> Error e
     | Ok target ->
       let rel = target - (offset + 2) in
       if rel < -128 || rel > 127 then
         Error (Relative_jump_out_of_range (label_name, rel))
       else begin
         Emitter.emit_uint8 emit 0xEB;
         Emitter.emit_int8 emit rel;
         Ok ()
       end)

  (* -- CALL rel16 (near call) --
     Pushes return address, jumps to target.
     Relative offset from END of instruction (3 bytes). *)
  | Call label_name ->
    (match resolve_label labels label_name with
     | Error e -> Error e
     | Ok target ->
       let rel = target - (offset + 3) in
       Emitter.emit_uint8 emit 0xE8;
       Emitter.emit_int16_le emit rel;
       Ok ())

  (* -- Directives: no bytes emitted -- *)
  | Org _ -> Ok ()
  | Label_def _ -> Ok ()

  (* -- Raw data -- *)
  | Db bytes ->
    Emitter.emit_bytes emit bytes;
    Ok ()

  | Dstring s ->
    Emitter.emit_string emit s;
    Emitter.emit_uint8 emit 0;  (* null terminator *)
    Ok ()

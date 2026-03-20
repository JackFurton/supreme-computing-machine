(* assembler.ml -- Two-pass assembler for x86 real-mode.

   PASS 1: Walk the instruction list, accumulate byte offsets,
           record every label's absolute address in a hash table.

   PASS 2: Walk again with all labels resolved. Emit actual bytes
           using the encoder. Forward references work because pass 1
           already found every label.

   This is the same algorithm real assemblers use. NASM, GAS, and
   even the original Intel 8086 assembler all do two passes.

   WHY TWO PASSES?
   Consider:  jmp skip    ; we need skip's address...
              hlt
   skip:                  ; ...but it's defined LATER

   Pass 1 discovers that "skip" is at offset N.
   Pass 2 encodes "jmp skip" as "jmp (N - current - 2)".
   Without pass 1, we'd have to guess or backpatch. *)

type error =
  | Duplicate_label of string
  | Encode_error of Encoder.error

let string_of_error = function
  | Duplicate_label name ->
    Printf.sprintf "duplicate label: %s" name
  | Encode_error e ->
    Encoder.string_of_error e

(* ---- Pass 1: Build label table ---- *)

let build_label_table (instructions : Types.instruction list) =
  let labels = Hashtbl.create 32 in
  let origin = ref 0 in
  let offset = ref 0 in
  let error = ref None in
  List.iter (fun (instr : Types.instruction) ->
    if !error = None then
      match instr with
      | Org addr ->
        origin := addr;
        offset := 0
      | Label_def name ->
        if Hashtbl.mem labels name then
          error := Some (Duplicate_label name)
        else
          Hashtbl.add labels name (!origin + !offset)
      | _ ->
        offset := !offset + Encoder.instruction_size instr
  ) instructions;
  match !error with
  | Some e -> Error e
  | None -> Ok labels

(* ---- Pass 2: Emit bytes ---- *)

let emit_instructions (emit : Emitter.t) ~labels
    (instructions : Types.instruction list) =
  let origin = ref 0 in
  let offset = ref 0 in
  let result = ref (Ok ()) in
  List.iter (fun (instr : Types.instruction) ->
    if !result = Ok () then begin
      let abs_offset = !origin + !offset in
      match instr with
      | Org addr ->
        origin := addr;
        offset := 0
      | Label_def _ ->
        ()  (* labels don't emit bytes *)
      | _ ->
        let size = Encoder.instruction_size instr in
        (match Encoder.encode_instruction emit ~labels ~offset:abs_offset instr with
         | Ok () -> offset := !offset + size
         | Error e -> result := Error (Encode_error e))
    end
  ) instructions;
  !result

(* ---- Public API ---- *)

let assemble (instructions : Types.instruction list) =
  match build_label_table instructions with
  | Error e -> Error e
  | Ok labels ->
    let emit = Emitter.create () in
    match emit_instructions emit ~labels instructions with
    | Error e -> Error e
    | Ok () -> Ok (Emitter.contents emit)

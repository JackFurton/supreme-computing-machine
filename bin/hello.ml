(* hello.ml -- Your first OCaml program.

   OCaml syntax crash course:
   - (* ... *)           comments (they nest!)
   - let x = 5           variable binding
   - let f x y = x + y   function definition
   - Printf.printf       module access (like Module.function)
   - |>                   pipe operator (like Unix |)
   - ;;                   end of top-level expression (in scripts/REPL)

   OCaml is:
   - Statically typed (like Rust/Go, unlike Python)
   - But with TYPE INFERENCE -- you rarely write types manually
   - Functional first, but has mutation when you want it
   - Compiled to native code (fast!)
*)

let () =
  (* `let () =` is OCaml's "main function" idiom.
     () is the "unit" type -- like void in C.
     This says: "run this expression for its side effects." *)

  print_endline "hello from supreme-computing-machine";

  (* Let's do something slightly more interesting --
     demonstrate some OCaml features *)

  let languages = ["Nix"; "OCaml"; "C"; "Assembly"] in
  let count = List.length languages in

  Printf.printf "we're going to learn %d languages on this journey:\n" count;

  (* List.iteri iterates with an index. The function takes (index, element).
     `fun` is an anonymous function (like a lambda). *)
  List.iteri (fun i lang ->
    Printf.printf "  %d. %s\n" (i + 1) lang
  ) languages;

  print_endline "\nnext up: build a unikernel."

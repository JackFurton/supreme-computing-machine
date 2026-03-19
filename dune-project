; dune-project -- Project-level configuration for dune.
;
; This is the root of our OCaml project. It tells dune:
; - What version of dune we need
; - What packages we produce
; - What our dependencies are

(lang dune 3.0)
(name supreme-computing-machine)

(package
 (name supreme-computing-machine)
 (synopsis "Learning Nix + OCaml: a DNS packet parser heading toward MirageOS")
 (depends
  (ocaml (>= 4.14))
  (dune (>= 3.0))
  (alcotest :with-test)))

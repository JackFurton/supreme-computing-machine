# flake.nix -- This is the entry point for our entire project.
#
# A "flake" is Nix's way of defining a self-contained, reproducible project.
# Think of it like a package.json + Dockerfile + Makefile all in one,
# but declarative and functional.
#
# SYNTAX CRASH COURSE:
#   { ... }          -- an "attribute set" (like a JSON object / Python dict)
#   x: body          -- a function that takes x and returns body
#   x: y: body       -- a curried function (takes x, returns a function that takes y)
#   inputs.thing     -- dot access, like inputs["thing"]
#   let x = 1; in x  -- local variable binding
#   [ a b c ]        -- a list (no commas!)
#   ''text''         -- multi-line string
#   "${expr}"        -- string interpolation
#
{
  # INPUTS: These are the dependencies of our flake.
  # Nix will fetch these automatically. Think of them like
  # "dependencies" in package.json, but for your entire toolchain.

  description = "supreme-computing-machine: learning Nix + OCaml + MirageOS";

  inputs = {
    # nixpkgs is THE package repository -- ~100,000 packages.
    # We pin to a specific branch so builds are reproducible.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    # flake-utils gives us helper functions so we don't have to
    # write boilerplate for each CPU architecture (x86, arm, etc.)
    flake-utils.url = "github:numtide/flake-utils";
  };

  # OUTPUTS: This is a function that takes our resolved inputs
  # and returns what our flake "provides" to the world.
  #
  # The `{ self, nixpkgs, flake-utils }` syntax is "destructuring" --
  # it pulls those names out of the inputs attribute set.

  outputs = { self, nixpkgs, flake-utils }:

    # eachDefaultSystem runs our function once for each platform
    # (x86_64-linux, aarch64-linux, x86_64-darwin, aarch64-darwin)
    # and merges the results. This means our flake works on any machine.
    flake-utils.lib.eachDefaultSystem (system:

      let
        # `pkgs` is now the full Nix package set for our specific system.
        # This is where all 100,000+ packages live.
        pkgs = import nixpkgs { inherit system; };

        # OCaml packages -- Nix has a complete set of opam packages.
        ocamlPkgs = pkgs.ocamlPackages;

      in
      {
        # DEV SHELL: This is what you get when you run `nix develop`.
        # It drops you into a shell with all these tools available,
        # without installing anything globally on your system.
        #
        # When you leave the shell, it's like nothing was ever installed.

        devShells.default = pkgs.mkShell {
          name = "supreme-computing-machine";

          # Packages available in the dev shell
          buildInputs = [
            # -- OCaml toolchain --
            ocamlPkgs.ocaml           # the compiler
            ocamlPkgs.dune_3          # build system (like cargo/make for OCaml)
            ocamlPkgs.ocaml-lsp       # editor support
            ocamlPkgs.ocamlformat     # code formatter
            ocamlPkgs.utop            # interactive REPL (great for learning!)
            ocamlPkgs.findlib         # library manager
            ocamlPkgs.alcotest       # testing framework

            # -- System tools --
            pkgs.qemu                 # VM emulator (for booting our kernel later)
            pkgs.git                  # you know this one

            # -- Later we'll add MirageOS tools here --
          ];

          # This runs when you enter the dev shell
          shellHook = ''
            echo "================================================="
            echo " supreme-computing-machine dev shell"
            echo " OCaml $(ocaml --version)"
            echo " QEMU $(qemu-system-aarch64 --version | head -1)"
            echo "================================================="
            echo ""
            echo " Quick start:"
            echo "   utop          -- OCaml REPL (interactive playground)"
            echo "   dune build    -- compile the project"
            echo "   dune exec hello  -- run the hello program"
            echo ""
          '';
        };

        # PACKAGES: Things our flake can build.
        # `nix build` will build the default package.
        # We'll add our actual kernel/unikernel build here later.

        packages.default = ocamlPkgs.buildDunePackage {
          pname = "supreme-computing-machine";
          version = "0.1.0";
          src = ./.;

          # Runtime dependencies of our library/binary
          propagatedBuildInputs = [ ];

          # Test dependencies (only needed during `dune runtest`)
          checkInputs = [
            ocamlPkgs.alcotest
          ];

          # Enable tests during the Nix build
          doCheck = true;
        };
      }
    );
}

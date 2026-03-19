# Getting Started

## Step 1: Install Nix

We use the Determinate Systems installer (better than the official one --
it enables flakes by default and has a clean uninstall).

```bash
curl --proto '=https' --tlsv1.2 -sSf -L \
  https://install.determinate.systems/nix | sh -s -- install
```

After installing, **open a new terminal** (or `source /etc/profile`).

Verify it works:

```bash
nix --version
```

## Step 2: Enter the dev shell

From the project root:

```bash
nix develop
```

This will:
- Download the exact OCaml compiler, dune, QEMU, and all other tools
- Drop you into a shell where everything is available
- First run takes a few minutes (it's downloading/building packages)
- Subsequent runs are instant (everything is cached)

## Step 3: Build and run

Inside the dev shell:

```bash
dune build          # compile everything
dune exec hello     # run the hello program
```

You should see output listing the languages we're going to learn.

## Step 4: Play with OCaml

```bash
utop                # interactive OCaml REPL
```

Try typing these in utop:

```ocaml
1 + 1;;
List.map (fun x -> x * 2) [1; 2; 3; 4; 5];;
let greet name = Printf.printf "hello %s!\n" name;;
greet "world";;
```

Type `#quit;;` to exit.

## Project Structure

```
.
├── flake.nix          # Nix flake -- defines the entire build environment
├── flake.lock         # Pinned dependency versions (auto-generated)
├── dune-project       # OCaml project definition
├── bin/
│   ├── dune           # Build config for executables
│   └── hello.ml       # Our first OCaml program
└── GETTING_STARTED.md # You are here
```

## What's Next

Phase 1 (current): Learn Nix + OCaml basics
Phase 2: Build a MirageOS unikernel (network appliance that boots on bare metal)

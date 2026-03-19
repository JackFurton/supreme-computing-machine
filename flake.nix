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

        # SOURCE FILTERING:
        # When Nix builds a package, it copies the source into the
        # Nix store (/nix/store/...). We filter out files that aren't
        # needed for the build -- otherwise changes to .git/ or _build/
        # would invalidate the cache and trigger a rebuild.
        #
        # This is a KEY Nix concept: the build is a PURE FUNCTION of
        # its inputs. If the inputs don't change, the output is cached.
        # Filtering source = fewer spurious rebuilds.
        filteredSrc = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let
              baseName = builtins.baseNameOf path;
              # `builtins` is Nix's standard library -- always available.
              # baseNameOf "/foo/bar/baz.ml" => "baz.ml"
            in
            # Keep only files needed for the OCaml build
            !( baseName == "_build"
            || baseName == ".git"
            || baseName == "result"
            || baseName == ".github"
            || builtins.match ".*\\.md" baseName != null
            );
            # `builtins.match` does regex matching.
            # != null means "did it match?"
        };

        # THE PACKAGE DERIVATION:
        # This is the core concept of Nix. A "derivation" is a
        # recipe for building something. It specifies:
        #   - Source code (inputs)
        #   - Build tools (dependencies)
        #   - Build commands
        #   - Output paths
        #
        # Nix builds derivations in a SANDBOX:
        #   - No network access
        #   - No access to $HOME
        #   - No access to /tmp (gets its own)
        #   - Only declared dependencies are available
        #
        # This is what makes builds reproducible: if it builds in
        # the sandbox, it builds anywhere.

        supreme-computing-machine = ocamlPkgs.buildDunePackage {
          pname = "supreme-computing-machine";
          version = "0.1.0";

          # Use our filtered source (not raw ./. which includes .git etc.)
          src = filteredSrc;

          # DUNE BUILD FLAGS:
          # buildDunePackage calls `dune build` under the hood.
          # We can pass extra flags if needed.
          duneVersion = "3";

          # BUILD DEPENDENCIES:
          # These are OCaml libraries our code imports.
          # `buildInputs` = needed at build time only.
          # `propagatedBuildInputs` = needed by downstream consumers too.
          buildInputs = [
            ocamlPkgs.lwt          # Async/promise library (foundation of MirageOS)
          ];

          # TEST DEPENDENCIES:
          # `checkInputs` are only available when running tests.
          # They don't leak into the final package.
          checkInputs = [
            ocamlPkgs.alcotest
          ];

          # Run tests as part of `nix build`.
          # If tests fail, the build fails. No broken builds in the store.
          doCheck = true;
        };

        # DOCKER IMAGE:
        # Nix can build Docker/OCI images WITHOUT Docker installed.
        # No Dockerfile, no layer caching games, no base image --
        # Nix builds the image from scratch with ONLY what we need.
        #
        # This is another taste of the unikernel philosophy:
        # include only what your application needs, nothing else.
        # A typical Docker image has a full Linux userspace (100+ MB).
        # Ours has just our binary and its runtime deps (~30 MB).
        #
        # HOW IT WORKS:
        # `pkgs.dockerTools.buildLayeredImage` creates an OCI image
        # as a .tar.gz file. You can load it with `docker load`.
        #
        # No Docker daemon needed at build time. Pure Nix.

        dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "supreme-computing-machine";
          tag = "latest";

          contents = [
            supreme-computing-machine    # Our binaries
            pkgs.busybox                 # Minimal shell utilities
          ];

          config = {
            Cmd = [ "/bin/dns_unikernel" "53" ];
            ExposedPorts = { "53/udp" = {}; };
          };
        };

        # QEMU LAUNCH SCRIPT:
        # For the full "boot a VM" experience, this script runs our
        # DNS server in QEMU using Linux's direct-boot feature.
        #
        # We build a minimal initramfs (initial RAM filesystem) that
        # contains just our binary and a tiny init script.
        # The Linux kernel boots, unpacks the initramfs, runs init,
        # and our DNS server is live -- all in under 2 seconds.
        #
        # This is the closest thing to a real unikernel we can do
        # without MirageOS's Solo5 backend. The difference:
        #   - Real unikernel: OCaml code IS the kernel (no Linux)
        #   - Our version: Linux kernel + our binary as PID 1
        #   - Same result: a single-purpose VM running one application

        # Build the initramfs (initial RAM filesystem)
        initramfs = pkgs.makeInitrdNG {
          contents = [
            { object = "${supreme-computing-machine}/bin/dns_unikernel";
              symlink = "/bin/dns_unikernel"; }
            { object = "${pkgs.busybox}/bin/busybox";
              symlink = "/bin/busybox"; }
            { object = pkgs.writeScript "init" ''
                #!${pkgs.busybox}/bin/sh
                export PATH=/bin

                # Create minimal filesystem structure
                /bin/busybox mkdir -p /proc /sys /dev /tmp
                /bin/busybox mount -t proc proc /proc
                /bin/busybox mount -t sysfs sys /sys
                /bin/busybox mount -t devtmpfs dev /dev

                # Set up networking
                /bin/busybox ip link set lo up
                /bin/busybox ip link set eth0 up 2>/dev/null
                /bin/busybox ip addr add 10.0.2.15/24 dev eth0 2>/dev/null
                /bin/busybox ip route add default via 10.0.2.2 2>/dev/null

                echo ""
                echo "========================================="
                echo " supreme-computing-machine DNS appliance"
                echo " Running in QEMU -- this is a VM!"
                echo "========================================="
                echo ""

                # Run our DNS server as PID 1
                exec /bin/dns_unikernel 53
              '';
              symlink = "/init"; }
          ];
        };

        # Kernel image path differs by architecture
        kernelImage =
          if builtins.match ".*aarch64.*" system != null
          then "${pkgs.linuxPackages_minimal.kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target}"
          else "${pkgs.linuxPackages_minimal.kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target}";

        qemuBin =
          if builtins.match ".*aarch64.*" system != null
          then "${pkgs.qemu}/bin/qemu-system-aarch64"
          else "${pkgs.qemu}/bin/qemu-system-x86_64";

        qemuMachineFlags =
          if builtins.match ".*aarch64.*" system != null
          then "-machine virt -cpu cortex-a57"
          else "-machine q35";

        appliance = pkgs.writeShellScriptBin "dns-appliance" ''
          echo "=== supreme-computing-machine DNS appliance ==="
          echo ""
          echo "Booting a VM with our DNS server as the only process..."
          echo ""
          echo "  Test with:  dig @127.0.0.1 -p 5353 example.com A"
          echo "  Stop with:  Ctrl-A then X"
          echo ""

          ${qemuBin} \
            ${qemuMachineFlags} \
            -m 256M \
            -kernel ${kernelImage} \
            -initrd ${initramfs}/initrd \
            -append "console=ttyS0 quiet" \
            -nographic \
            -netdev user,id=net0,hostfwd=udp::5353-:53 \
            -device virtio-net-pci,netdev=net0
        '';

      in
      {
        # DEV SHELL: This is what you get when you run `nix develop`.
        # It drops you into a shell with all these tools available,
        # without installing anything globally on your system.
        #
        # KEY DIFFERENCE from packages:
        #   `nix develop`  = gives you tools to work with (interactive)
        #   `nix build`    = produces a built artifact (automated)
        #
        # The dev shell is for humans. The package build is for machines.

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
            ocamlPkgs.alcotest        # testing framework
            ocamlPkgs.lwt             # async/promises (MirageOS foundation)

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
            echo "================================================="
            echo ""
            echo " Commands:"
            echo "   dune build                            -- compile everything"
            echo "   dune exec hello                       -- DNS parser demo"
            echo "   dune exec dns_client -- example.com   -- query real DNS"
            echo "   dune exec dns_server                  -- run DNS server"
            echo "   dune exec -- unikernel/main.exe       -- run unikernel (Unix)"
            echo "   dune runtest                          -- run test suite"
            echo "   utop                                  -- OCaml REPL"
            echo ""
            echo " Nix commands:"
            echo "   nix run .#server                      -- run DNS server"
            echo "   nix run .#appliance                   -- boot DNS VM in QEMU"
            echo "   nix build .#docker                    -- build Docker image"
            echo ""
          '';
        };

        # PACKAGES: What `nix build` produces.
        #
        # After running `nix build`, you get a symlink called `result/`
        # pointing into the Nix store:
        #
        #   result/
        #   └── bin/
        #       └── hello    <-- our compiled binary
        #
        # You can also run it directly: `nix run`
        #
        # The binary is FULLY SELF-CONTAINED. Copy it anywhere and it works.
        # (Well, on the same OS/arch. Nix handles cross-compilation too,
        # but that's a topic for another day.)

        packages = {
          default = supreme-computing-machine;

          # `nix build .#docker` -- build the Docker image
          docker = dockerImage;

          # `nix build .#appliance` -- build the QEMU launcher
          vm-appliance = appliance;
        };

        # APPS: What `nix run` executes.
        #
        # Multiple apps! Each one is a different way to run the project:
        #   `nix run`             -- run the hello demo
        #   `nix run .#server`    -- run the DNS server natively
        #   `nix run .#client`    -- run the DNS client
        #   `nix run .#appliance` -- boot the DNS server in a QEMU VM

        apps = {
          default = {
            type = "app";
            program = "${supreme-computing-machine}/bin/hello";
          };
          server = {
            type = "app";
            program = "${supreme-computing-machine}/bin/dns_unikernel";
          };
          client = {
            type = "app";
            program = "${supreme-computing-machine}/bin/dns_client";
          };
          appliance = {
            type = "app";
            program = "${appliance}/bin/dns-appliance";
          };
        };

        # CHECKS: What `nix flake check` validates.
        # CI will run this to verify the flake is healthy.
        # We just re-use the package build (which includes tests).

        checks.default = supreme-computing-machine;
      }
    );
}

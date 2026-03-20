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
  description = "supreme-computing-machine: learning Nix + OCaml + MirageOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:

    flake-utils.lib.eachDefaultSystem (system:

      let
        pkgs = import nixpkgs { inherit system; };
        ocamlPkgs = pkgs.ocamlPackages;

        # Is this a Linux system? Docker images and QEMU VMs are Linux-only.
        isLinux = builtins.match ".*linux.*" system != null;

        # ── Source filtering ─────────────────────────────────────────
        # Filter out files that aren't needed for the build so that
        # changes to .git/ or .md files don't invalidate the Nix cache.

        filteredSrc = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            let baseName = builtins.baseNameOf path; in
            !( baseName == "_build"
            || baseName == ".git"
            || baseName == "result"
            || baseName == ".github"
            || builtins.match ".*\\.md" baseName != null
            );
        };

        # ── The main OCaml package ───────────────────────────────────

        supreme-computing-machine = ocamlPkgs.buildDunePackage {
          pname = "supreme-computing-machine";
          version = "0.1.0";
          src = filteredSrc;
          duneVersion = "3";
          buildInputs = [ ocamlPkgs.lwt ];
          checkInputs = [ ocamlPkgs.alcotest ];
          doCheck = true;
        };

        # ── Linux-only: Docker image ────────────────────────────────
        # Nix builds OCI images WITHOUT Docker. No Dockerfile needed.
        # The resulting image contains ONLY our binary + busybox (~30 MB).

        dockerImage = pkgs.dockerTools.buildLayeredImage {
          name = "supreme-computing-machine";
          tag = "latest";
          contents = [ supreme-computing-machine pkgs.busybox ];
          config = {
            Cmd = [ "/bin/dns_unikernel" "53" ];
            ExposedPorts = { "53/udp" = {}; };
          };
        };

        # ── Linux-only: QEMU VM appliance ───────────────────────────
        # Boots a minimal Linux VM with our DNS server as PID 1.
        # Builds a custom initramfs (cpio archive) with just our binary.

        initScript = pkgs.writeScript "init" ''
          #!/bin/sh
          export PATH=/bin:/usr/bin
          mkdir -p /proc /sys /dev /tmp
          mount -t proc proc /proc
          mount -t sysfs sys /sys
          mount -t devtmpfs dev /dev
          ip link set lo up
          ip link set eth0 up 2>/dev/null
          ip addr add 10.0.2.15/24 dev eth0 2>/dev/null
          ip route add default via 10.0.2.2 2>/dev/null
          echo ""
          echo "========================================="
          echo " supreme-computing-machine DNS appliance"
          echo " Running in QEMU -- this is a VM!"
          echo "========================================="
          echo ""
          exec /bin/dns_unikernel 53
        '';

        initramfs = pkgs.runCommand "dns-initramfs" {
          nativeBuildInputs = [ pkgs.cpio pkgs.gzip ];
        } ''
          mkdir -p root/bin root/lib root/lib64

          # Busybox for shell + networking commands
          cp ${pkgs.busybox}/bin/busybox root/bin/busybox
          for cmd in sh ip mount mkdir echo cat ls; do
            ln -s busybox root/bin/$cmd
          done

          # Our DNS server binary
          cp ${supreme-computing-machine}/bin/dns_unikernel root/bin/dns_unikernel

          # Init script
          cp ${initScript} root/init
          chmod +x root/init

          # Shared libraries needed by our dynamically-linked binary
          for lib in $(${pkgs.findutils}/bin/find \
            ${pkgs.glibc}/lib \
            ${pkgs.gcc.cc.lib}/lib \
            -maxdepth 1 \
            -name '*.so*' 2>/dev/null); do
            cp -n "$lib" root/lib/ 2>/dev/null || true
          done

          # Dynamic linker (may be in lib or lib64 depending on arch)
          cp ${pkgs.glibc}/lib/ld-linux-*.so.* root/lib/ 2>/dev/null || true
          cp ${pkgs.glibc}/lib/ld-linux-*.so.* root/lib64/ 2>/dev/null || true

          # Build compressed cpio archive
          (cd root && ${pkgs.findutils}/bin/find . | cpio -o -H newc | gzip > $out)
        '';

        qemuBin =
          if builtins.match ".*aarch64.*" system != null
          then "${pkgs.qemu}/bin/qemu-system-aarch64"
          else "${pkgs.qemu}/bin/qemu-system-x86_64";

        qemuMachineFlags =
          if builtins.match ".*aarch64.*" system != null
          then "-machine virt -cpu cortex-a57"
          else "-machine q35";

        # ── Boot sector image ──────────────────────────────────────
        # Assembles our x86 boot sector using the OCaml assembler.
        # No kernel, no OS -- just 512 bytes of raw machine code.

        bootImage = pkgs.runCommand "boot-image" {} ''
          ${supreme-computing-machine}/bin/boot_sector $out
        '';

        bootQemu = pkgs.writeShellScriptBin "boot-qemu" ''
          echo "=== supreme-computing-machine x86 bootloader ==="
          echo ""
          echo "Booting bare-metal boot sector in QEMU..."
          echo "  No kernel. No OS. Just 512 bytes assembled by OCaml."
          echo ""
          echo "  Close the QEMU window to exit."
          echo ""

          ${pkgs.qemu}/bin/qemu-system-i386 \
            -drive format=raw,file=${bootImage}
        '';

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
            -kernel ${pkgs.linuxPackages.kernel}/${pkgs.stdenv.hostPlatform.linux-kernel.target} \
            -initrd ${initramfs} \
            -append "console=ttyS0 quiet" \
            -nographic \
            -netdev user,id=net0,hostfwd=udp::5353-:53 \
            -device virtio-net-pci,netdev=net0
        '';

      in
      {
        # ── Dev shell ────────────────────────────────────────────────

        devShells.default = pkgs.mkShell {
          name = "supreme-computing-machine";
          buildInputs = [
            ocamlPkgs.ocaml
            ocamlPkgs.dune_3
            ocamlPkgs.ocaml-lsp
            ocamlPkgs.ocamlformat
            ocamlPkgs.utop
            ocamlPkgs.findlib
            ocamlPkgs.alcotest
            ocamlPkgs.lwt
            pkgs.qemu
            pkgs.git
          ];
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
            echo "   dune exec boot_sector                 -- assemble boot sector"
            echo "   dune runtest                          -- run test suite"
            echo "   utop                                  -- OCaml REPL"
            echo ""
            echo " Nix commands:"
            echo "   nix run .#server                      -- run DNS server"
            echo "   nix run .#boot                        -- boot x86 bootloader in QEMU"
            echo "   nix run .#appliance                   -- boot DNS VM in QEMU"
            echo "   nix build .#docker                    -- build Docker image"
            echo ""
          '';
        };

        # ── Packages ─────────────────────────────────────────────────
        # `nix build` builds the default. Linux gets docker + VM too.

        packages = {
          default = supreme-computing-machine;
          boot-image = bootImage;
        } // pkgs.lib.optionalAttrs isLinux {
          docker = dockerImage;
          vm-appliance = appliance;
        };

        # ── Apps ─────────────────────────────────────────────────────
        # `nix run .#name` runs these.

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
          boot = {
            type = "app";
            program = "${bootQemu}/bin/boot-qemu";
          };
        } // pkgs.lib.optionalAttrs isLinux {
          appliance = {
            type = "app";
            program = "${appliance}/bin/dns-appliance";
          };
        };

        # ── Checks ───────────────────────────────────────────────────
        checks.default = supreme-computing-machine;
      }
    );
}

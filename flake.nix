{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAll (system:
        let
          gituser = "git";
          githome = "/git1";

          pkgs = nixpkgs.legacyPackages.${system};
          pkggit = pkgs.gitMinimal;

          sshdConfig = pkgs.writeText "sshd_config" ''
            Port 22
            HostKey ${githome}/.hostkeys/ssh_host_ed25519_key
            #LogLevel ERROR
            PidFile none
            AllowUsers ${gituser}
            PasswordAuthentication no
            KbdInteractiveAuthentication no
            PermitRootLogin no
            PermitTTY no
            AllowTcpForwarding no
            X11Forwarding no
            SetEnv PATH=/bin
          '';

          entrypoint = pkgs.writeShellApplication {
            name = "entrypoint";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.openssh
              pkgs.gnugrep
              pkggit
            ];
            text = ''
              mkdir -p ${githome}/.ssh ${githome}/.hostkeys
              [ -f ${githome}/.hostkeys/ssh_host_ed25519_key ] || \
                ssh-keygen -q -t ed25519 -N "" \
                  -f ${githome}/.hostkeys/ssh_host_ed25519_key

              touch ${githome}/.ssh/authorized_keys
              printf '%s\n' "''${SSH_AUTHORIZED_KEYS:-}" | while IFS= read -r key; do
                [ -n "$key" ] || continue
                grep -qxF -- "$key" ${githome}/.ssh/authorized_keys || \
                  printf '%s\n' "$key" >> ${githome}/.ssh/authorized_keys
              done

              chown 1000:1000 ${githome} ${githome}/.ssh \
                ${githome}/.ssh/authorized_keys
              chmod 700 ${githome}/.ssh
              chmod 600 ${githome}/.ssh/authorized_keys \
                ${githome}/.hostkeys/ssh_host_ed25519_key

              [ -d ${githome}/git1.git ] ||
                git init --bare -b main ${githome}/git1.git
              chown -R 1000:1000 ${githome}/git1.git

              exec ${pkgs.openssh}/bin/sshd -D -e -f ${sshdConfig}
            '';
          };

          etc = pkgs.runCommand "etc" { } ''
            mkdir -p $out/etc
            cat > $out/etc/passwd <<EOF
            root:x:0:0:root:/root:/bin/false
            ${gituser}:*:1000:1000:${gituser}:${githome}:${pkggit}/bin/git-shell
            sshd:x:74:74:sshd privsep:/var/empty:/bin/false
            EOF
            cat > $out/etc/group <<EOF
            root:x:0:
            ${gituser}:x:1000:
            sshd:x:74:
            EOF
          '';
          
        in {
          default = pkgs.dockerTools.buildLayeredImage {
            name = "git1";
            tag = "latest";

            contents = [
              (pkgs.buildEnv {
                name = "root";
                paths = [ git pkgs.openssh pkgs.coreutils etc ];
                pathsToLink = [ "/bin" "/etc" ];
              })
            ];

            extraCommands = ''
              mkdir -p var/empty ${builtins.substring 1 (builtins.stringLength githome) githome} tmp
            '';

            config = {
              Entrypoint = [ "${entrypoint}/bin/entrypoint" ];
              ExposedPorts."22/tcp" = { };
              Volumes.${githome} = { };
            };
          };
        });
    };
}

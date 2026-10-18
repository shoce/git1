
{
  
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  
  outputs = { self, nixpkgs }:
    
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = nixpkgs.lib.genAttrs systems;
    
    in {
      
      packages = forAll (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          git = pkgs.gitMinimal;
          
          sshdConfig = pkgs.writeText "sshd_config" ''
            Port 22
            HostKey /git1/.hostkeys/ssh_host_ed25519_key
            #LogLevel ERROR
            PidFile none
            AllowUsers git
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
            runtimeInputs = [ pkgs.coreutils pkgs.openssh pkgs.gnugrep git ];
            text = ''
              mkdir -p /git1/.ssh /git1/.hostkeys
              [ -f /git1/.hostkeys/ssh_host_ed25519_key ] || \
                ssh-keygen -q -t ed25519 -N "" -f /git1/.hostkeys/ssh_host_ed25519_key
              touch /git1/.ssh/authorized_keys
              
              printf '%s\n' "''${SSH_AUTHORIZED_KEYS:-}" | while IFS= read -r key; do
                [ -n "$key" ] || continue
                grep -qxF -- "$key" /git1/.ssh/authorized_keys || \
                  printf '%s\n' "$key" >> /git1/.ssh/authorized_keys
              done
              
              chown 1000:1000 /git1 /git1/.ssh /git1/.ssh/authorized_keys
              chmod 700 /git1/.ssh
              chmod 600 /git1/.ssh/authorized_keys /git1/.hostkeys/ssh_host_ed25519_key
              
              [ -d /git1/git1.git ] || git init --bare -b main /git1/git1.git
              chown -R 1000:1000 /git1/git1.git
              
              exec ${pkgs.openssh}/bin/sshd -D -e -f ${sshdConfig}
            '';
          };
          
          etc = pkgs.runCommand "etc" { } ''
            mkdir -p $out/etc
            cat > $out/etc/passwd <<EOF
            root:x:0:0:root:/root:/bin/false
            git:*:1000:1000:git:/git1:${git}/bin/git-shell
            sshd:x:74:74:sshd privsep:/var/empty:/bin/false
            EOF
            cat > $out/etc/group <<EOF
            root:x:0:
            git:x:1000:
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
              mkdir -p var/empty git1 tmp
            '';
            config = {
              Entrypoint = [ "${entrypoint}/bin/entrypoint" ];
              ExposedPorts."22/tcp" = { };
              Volumes."/git1" = { };
              
            };
            
          };
          
        });
        
    };
}



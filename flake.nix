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
          git = pkgs.gitMinimal;   # swap to pkgs.git if git-shell is missing

          sshdConfig = pkgs.writeText "sshd_config" ''
            Port 22
            HostKey /data/.hostkeys/ssh_host_ed25519_key
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
            runtimeInputs = [ pkgs.coreutils pkgs.openssh ];
            text = ''
              mkdir -p /data/.ssh /data/.hostkeys
              [ -f /data/.hostkeys/ssh_host_ed25519_key ] || ssh-keygen -q -t ed25519 -N "" -f /data/.hostkeys/ssh_host_ed25519_key
              touch /data/.ssh/authorized_keys
              chown 1000:1000 /data /data/.ssh /data/.ssh/authorized_keys
              chmod 700 /data/.ssh
              chmod 600 /data/.ssh/authorized_keys /data/.hostkeys/ssh_host_ed25519_key
              exec ${pkgs.openssh}/bin/sshd -D -e -f ${sshdConfig}
            '';
          };

          etc = pkgs.runCommand "etc" { } ''
            mkdir -p $out/etc
            cat > $out/etc/passwd <<EOF
            root:x:0:0:root:/root:/bin/false
            git:*:1000:1000:git:/data:${git}/bin/git-shell
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
              mkdir -p var/empty data tmp
            '';
            config = {
              Entrypoint = [ "${entrypoint}/bin/entrypoint" ];
              ExposedPorts."22/tcp" = { };
              Volumes."/data" = { };
              
            };
            
          };
          
        });
        
    };
}



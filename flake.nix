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
          gituid = "1000";
          gitgid = "1000";
          githome = "/git1";
          gitrepos = "git1";
          dimagename = "git1";
          
          pkgs = nixpkgs.legacyPackages.${system};
          pkggit = pkgs.gitMinimal;
          
          pkgsshdconfig = pkgs.writeText "sshd_config" ''
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
          
          pkgentrypoint = pkgs.writeShellApplication {
            name = "entrypoint";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.openssh
              pkgs.gnugrep
              pkggit
            ];
            text = ''
              
              echo "git1 version [$GIT1VERSION]"
              echo "git user [${gituser}]"
              echo "git home dir [${githome}]"
              GIT_REPOS="''${GIT_REPOS:-${gitrepos}}"
              echo "git repos [''${GIT_REPOS}]"
              
              echo "/etc/passwd [-" ; cat "/etc/passwd" || true ; echo "-]" ; 
              echo "/etc/group [-" ; cat "/etc/group" || true ; echo "-]" ; 
              echo "/etc/shadow [-" ; cat "/etc/shadow" || true ; echo "-]" ; 
              
              mkdir -p ${githome}/.ssh ${githome}/.hostkeys
              [ -f ${githome}/.hostkeys/ssh_host_ed25519_key ] || \
                  ssh-keygen \
                      -q -t ed25519 -N "" \
                      -C "${gituser}" \
                      -f ${githome}/.hostkeys/ssh_host_ed25519_key
              for fpath in ${githome}/.hostkeys/* ; do
                  echo "$fpath [-" ; cat "$fpath" || true ; echo "-]" ; 
              done
              
              touch ${githome}/.ssh/authorized_keys
              printf '%s\n' "''${SSH_AUTHORIZED_KEYS:-}" | while IFS= read -r key; do
                [ -n "$key" ] || continue
                grep -qxF -- "$key" ${githome}/.ssh/authorized_keys || \
                  printf '%s\n' "$key" >> ${githome}/.ssh/authorized_keys
              done
              echo "${githome}/.ssh/authorized_keys [-" ; cat "${githome}/.ssh/authorized_keys" ; echo "-]" ;
              
              chown ${gituid}:${gitgid} ${githome} ${githome}/.ssh \
                ${githome}/.ssh/authorized_keys
              chmod 700 ${githome}/.ssh
              chmod 600 ${githome}/.ssh/authorized_keys \
                ${githome}/.hostkeys/ssh_host_ed25519_key
              
              for repo in $GIT_REPOS ; do
                echo "repo [$repo]"
                repodir="${githome}/$repo.git"
                [ -d "$repodir" ] || {
                  echo "[$repodir] creating repo"
                  git init --bare -b main "$repodir"
                }
                echo "[$repodir] du -sk"
                du -sk "$repodir"
                echo "[$repodir] git config"
                git -C "$repodir" config receive.denyNonFastForwards true || sleep 1
                git -C "$repodir" config receive.denyDeletes true || sleep 1
                echo "[$repodir] chown ${gituid}:${gitgid}"
                chown -R ${gituid}:${gitgid} "$repodir"
              done
              
              for repo in $GIT_REPOS ; do
                echo "[$repodir] git remote add git1-$repo ssh://${gituser}@HOSTNAME:22/${githome}/$repo.git"
              done
              echo "${pkgsshdconfig} [-" ; cat "${pkgsshdconfig}" ; echo "-]" ;
              echo "starting sshd server"
              exec ${pkgs.openssh}/bin/sshd -D -e -f ${pkgsshdconfig}
              
            '';
          };

          pkgetc = pkgs.runCommand "etc" { } ''
            mkdir -p $out/etc
            cat > $out/etc/passwd <<EOF
            root:x:0:0:root:/root:/bin/false
            ${gituser}:*:${gituid}:${gitgid}:${gituser}:${githome}:${pkggit}/bin/git-shell
            sshd:x:74:74:sshd privsep:/var/empty:/bin/false
            EOF
            cat > $out/etc/group <<EOF
            root:x:0:
            ${gituser}:x:${gitgid}:
            sshd:x:74:
            EOF
          '';
          
        in {
          default = pkgs.dockerTools.buildLayeredImage {
            name = "${dimagename}";
            tag = "latest";

            contents = [
              (pkgs.buildEnv {
                name = "root";
                paths = [ pkggit pkgs.openssh pkgs.coreutils pkgetc ];
                pathsToLink = [ "/bin" "/etc" ];
              })
            ];

            extraCommands = ''
              mkdir -p var/empty ${builtins.substring 1 (builtins.stringLength githome) githome} tmp
            '';

            config = {
              Entrypoint = [ "${pkgentrypoint}/bin/entrypoint" ];
              ExposedPorts."22/tcp" = { };
              Volumes.${githome} = { };
            };
          };
        });
    };
}




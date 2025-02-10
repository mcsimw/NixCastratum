{ flake, ... }:
{
  config,
  lib,
  inputs,
  withSystem,
  ...
}:
let
  modulesPath = "${inputs.nixpkgs.outPath}/nixos/modules";

  # Retrieve the base path from options.
  compootuersPath = builtins.toString (config.compootuers.path or "");

  # Scan the compootuers directory using lib.optional.
  computedCompootuers =
    builtins.concatLists (
      lib.optional (compootuersPath != "")
        (map (arch:
          let
            archPath = compootuersPath + "/" + arch;
            hostNames = builtins.attrNames (builtins.readDir archPath);
          in
            map (host: {
              hostname = host;
              system = arch;
              src = builtins.toPath (archPath + "/" + host);
            }) hostNames
        ) (builtins.attrNames (builtins.readDir compootuersPath)))
    );

  # Build a NixOS configuration for a given host record (sub).
  configForSub =
    { sub,
      iso ? false,
    }:
    withSystem sub.system (
      {
        config,
        inputs',
        self',
        system,
        ...
      }:
      let
        baseModules =
          [
            { networking.hostName = sub.hostname; }
            flake.self.nixosModules.sane
            flake.self.nixosModules.nix-conf
          ]
          ++ lib.optional (sub.src != null &&
                          builtins.pathExists (builtins.toString sub.src + "/both.nix"))
               (import (builtins.toString sub.src + "/both.nix"));
        isoModules =
          [
            {
              imports = [ "${modulesPath}/installer/cd-dvd/installation-cd-base.nix" ];
              boot.initrd.systemd.enable = lib.mkForce false;
              isoImage.squashfsCompression = "lz4";
              networking.wireless.enable = lib.mkForce false;
              systemd.targets = {
                sleep.enable = lib.mkForce false;
                suspend.enable = lib.mkForce false;
                hibernate.enable = lib.mkForce false;
                hybrid-sleep.enable = lib.mkForce false;
              };
              users.users.nixos = {
                initialPassword = "iso";
                hashedPasswordFile = null;
                hashedPassword = null;
              };
            }
          ]
          ++ lib.optional (sub.src != null &&
                          builtins.pathExists (builtins.toString sub.src + "/iso.nix"))
               (import (builtins.toString sub.src + "/iso.nix"));
        nonIsoModules =
          [
            flake.self.nixosModules.fakeFileSystems
          ]
          ++ lib.optional (sub.src != null &&
                          builtins.pathExists (builtins.toString sub.src + "/default.nix"))
               (import (builtins.toString sub.src + "/default.nix"));
      in
      inputs.nixpkgs.lib.nixosSystem {
        specialArgs = {
          inherit (config) packages;
          inherit inputs inputs' self' system;
          withSystemArch = withSystem system;
        };
        modules = baseModules
          ++ lib.optionals iso isoModules
          ++ lib.optionals (!iso) nonIsoModules;
      }
    );

in
{
  # Declare the compootuers option as an attribute set with a "path" key.
  options.compootuers = {
    path = lib.mkOption {
      type = lib.types.path;
      default = null;
    };
  };

  config = {
    flake = {
      nixosConfigurations = builtins.listToAttrs (
        builtins.concatLists (
          lib.concatMap (
            sub:
            lib.optional (sub.hostname != null)
              [
                {
                  name = sub.hostname;
                  value = configForSub { inherit sub; iso = false; };
                }
                {
                  name = "${sub.hostname}-iso";
                  value = configForSub { inherit sub; iso = true; };
                }
              ]
          ) computedCompootuers
        )
      );
    };
    systems = lib.unique (
      builtins.filter (s: s != null)
        (map (sub: sub.system) computedCompootuers)
    );
  };
}

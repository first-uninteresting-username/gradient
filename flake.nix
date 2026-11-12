{
  description = "GRADIENT - an original endless downhill ball-runner (Godot 4)";

  # Pinned to a nixos-unstable snapshot that ships Godot 4.7.2 and matching export templates.
  inputs.nixpkgs.url = "https://releases.nixos.org/nixos/unstable/nixos-26.11pre1107793.1d060086d60c/nixexprs.tar.zst";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAll (pkgs:
        let
          godot = pkgs.godot_4_7;
          templates = pkgs.godot_4_7-export-templates-bin;
          script = name: text: pkgs.writeShellApplication {
            inherit name;
            runtimeInputs = [ godot pkgs.coreutils ];
            inherit text;
          };
        in
        {
          inherit godot;
          # Opens the project in the Godot editor.
          editor = script "gradient-editor" ''godot --editor --path "''${1:-.}"'';
          # Runs the game from source.
          play = script "gradient-play" ''godot --path "''${1:-.}"'';
          # Imports assets and runs the headless test suite (tests/run_tests.gd).
          test = script "gradient-test" ''
            dir="''${1:-.}"
            shift || true
            godot --headless --path "$dir" --import
            godot --headless --path "$dir" --fixed-fps 120 res://tests/test_runner.tscn -- --no-save "$@"
          '';
          # Exports Linux, Windows and Web builds into ./build.
          export = script "gradient-export" ''
            dir="$(realpath "''${1:-.}")"
            version="${builtins.replaceStrings [ "-" ] [ "." ] godot.version}"
            home="$(mktemp -d)"
            mkdir -p "$home/.local/share/godot/export_templates"
            ln -s ${templates}/share/godot/export_templates/* "$home/.local/share/godot/export_templates/" 2>/dev/null \
              || ln -s ${templates} "$home/.local/share/godot/export_templates/$version"
            export HOME="$home" XDG_DATA_HOME="$home/.local/share"
            mkdir -p "$dir/build/linux" "$dir/build/windows" "$dir/build/web"
            godot --headless --path "$dir" --import
            godot --headless --path "$dir" --export-release "Linux" "$dir/build/linux/gradient.x86_64"
            godot --headless --path "$dir" --export-release "Windows" "$dir/build/windows/gradient.exe"
            godot --headless --path "$dir" --export-release "Web" "$dir/build/web/index.html"
          '';
          default = self.packages.${pkgs.stdenv.hostPlatform.system}.play;
        });

      devShells = forAll (pkgs: {
        default = pkgs.mkShell { packages = [ pkgs.godot_4_7 pkgs.python3 ]; };
      });
    };
}

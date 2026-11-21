# The `kirin` command (cli/): installs and manages the checkout in ~/.kirin.
{ python3Packages, src }:
python3Packages.buildPythonApplication {
  pname = "kirin-cli";
  version = "0.1.0";
  pyproject = true;
  inherit src;

  build-system = [ python3Packages.hatchling ];
  dependencies = [ python3Packages.rich ];
}

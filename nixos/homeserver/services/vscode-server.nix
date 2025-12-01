{ inputs, ... }:
{
  imports = [
    inputs.vscode-server.nixosModule.default
  ];
  services.vscode-server.enable = true;
}


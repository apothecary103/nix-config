{
  flake.modules.homeManager.base = {
    services.espanso = {
      enable = true;

      matches = {
        default = {
          matches = [
            {
              trigger = "!caps";
              replace = "⇪";
            }
            {
              trigger = "!clear";
              replace = "⌧";
            }
            {
              trigger = "!cmd";
              replace = "⌘";
            }
            {
              trigger = "!control";
              replace = "⌃";
            }
            {
              trigger = "!delete";
              replace = "⌫";
            }
            {
              trigger = "!down";
              replace = "↓";
            }
            {
              trigger = "!enter";
              replace = "↩";
            }
            {
              trigger = "!esc";
              replace = "⎋";
            }
            {
              trigger = "!fndelete";
              replace = "⌦";
            }
            {
              trigger = "!left";
              replace = "←";
            }
            {
              trigger = "!option";
              replace = "⌥";
            }
            {
              trigger = "!right";
              replace = "→";
            }
            {
              trigger = "!shift";
              replace = "⇧";
            }
            {
              trigger = "!space";
              replace = "␣";
            }
            {
              trigger = "!tab";
              replace = "⇥";
            }
            {
              trigger = "!up";
              replace = "↑";
            }
            {
              trigger = "omw";
              replace = "On my way!";
            }
          ];
        };
      };
    };
  };
}

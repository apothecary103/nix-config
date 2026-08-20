{
  flake.modules.nixos.base =
    { pkgs, ... }:
    {
      services.gvfs.enable = true;
      services.udisks2.enable = true;
      services.gnome.sushi.enable = true;

      # Registers a .thumbnailer so Nautilus shows video previews; images work
      # out of the box via gdk-pixbuf.
      environment.systemPackages = [ pkgs.ffmpegthumbnailer ];

      programs.dconf.profiles.user.databases = [
        {
          settings = {
            "org/gnome/nautilus/preferences" = {
              default-folder-viewer = "list-view";
              show-hidden-files = false;
              show-delete-permanently = true;
              click-policy = "double";
            };

            "org/gnome/nautilus/list-view" = {
              use-tree-view = true;
              default-zoom-level = "small";
              default-visible-columns = [
                "name"
                "size"
                "date_modified"
              ];
            };

            "org/gnome/nautilus/icon-view".default-zoom-level = "large";

            "org/gtk/settings/file-chooser".sort-directories-first = true;
            "org/gtk/gtk4/settings/file-chooser".sort-directories-first = true;
          };
        }
      ];
    };

  flake.modules.hjem.linux =
    { pkgs, ... }:
    {
      packages = [ pkgs.nautilus ];

      # Without these, "open containing folder" and image previews route to
      # whatever registers first.
      xdg.mime-apps.default-applications = {
        "inode/directory" = "org.gnome.Nautilus.desktop";
        "image/png" = "org.gnome.Loupe.desktop";
        "image/jpeg" = "org.gnome.Loupe.desktop";
        "image/gif" = "org.gnome.Loupe.desktop";
        "image/webp" = "org.gnome.Loupe.desktop";
        "image/tiff" = "org.gnome.Loupe.desktop";
        "image/bmp" = "org.gnome.Loupe.desktop";
        "image/svg+xml" = "org.gnome.Loupe.desktop";
        "image/heif" = "org.gnome.Loupe.desktop";
        "image/avif" = "org.gnome.Loupe.desktop";
      };
    };
}

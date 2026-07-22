{
  # GNOME Files (Nautilus) as the graphical file manager, set up to feel and
  # look like it does under GNOME: gvfs for mounting/trash/network, udisks for
  # removable media, sushi for spacebar quick-preview, and video thumbnails.
  flake.modules.nixos.base = { pkgs, ... }: {
    services.gvfs.enable = true;
    services.udisks2.enable = true;
    services.gnome.sushi.enable = true;

    # Registers a .thumbnailer so Nautilus shows video previews (images work
    # out of the box via gdk-pixbuf).
    environment.systemPackages = [ pkgs.ffmpegthumbnailer ];
  };

  flake.modules.homeManager.linux = { pkgs, ... }: {
    home.packages = [ pkgs.nautilus ];

    # Open folders in Nautilus and images in Loupe (GNOME's viewer), matching
    # the GNOME defaults so "open containing folder" and image previews route
    # to the polished apps rather than whatever registers first.
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
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

    dconf.settings = {
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

      # Directories first in Nautilus and in GTK open/save dialogs, matching
      # GNOME's tidy default ordering.
      "org/gtk/settings/file-chooser".sort-directories-first = true;
      "org/gtk/gtk4/settings/file-chooser".sort-directories-first = true;
    };
  };
}

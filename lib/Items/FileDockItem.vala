//
// Copyright (C) 2011 Robert Dyer, Rico Tzschichholz
//
// This file is part of Plank.
//
// Plank is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Plank is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

namespace Plank {
  /**
   * A dock item for files or folders on the dock.
   *
   * Folders act like stacks and display the contents of the folder in the
   * popup menu. Files just open the associated file.
   */
  public class FileDockItem : DockItem {
    const string DEFAULT_ICONS = "inode-directory;;folder";

    FanWindow? fan = null;
    StackWindow? stack = null;

    public File OwnedFile { get; protected construct set; }

    FileMonitor? dir_monitor;

    public FileDockItem.with_file (GLib.File file)
    {
      var prefs = new DockItemPreferences ();
      prefs.Launcher = file.get_uri ();

      GLib.Object (Prefs : prefs, OwnedFile: file);
    }

    public FileDockItem.with_dockitem_file (GLib.File file)
    {
      var prefs = new DockItemPreferences.with_file (file);

      GLib.Object (Prefs: prefs, OwnedFile: File.new_for_uri (prefs.Launcher));
    }

    public FileDockItem.with_dockitem_filename (string filename)
    {
      var prefs = new DockItemPreferences.with_filename (filename);

      GLib.Object (Prefs: prefs, OwnedFile: File.new_for_uri (prefs.Launcher));
    }

    construct
    {
      load_from_launcher ();
    }

    ~FileDockItem () {
      stop_monitor ();

      if (fan != null)
        fan.destroy ();
      if (stack != null)
        stack.destroy ();
    }

    protected override void load_from_launcher () {
      stop_monitor ();

      if (Prefs.Launcher == "")
        return;

      OwnedFile = File.new_for_uri (Prefs.Launcher);
      Icon = DrawingService.get_icon_from_file (OwnedFile) ?? DEFAULT_ICONS;

      if (!OwnedFile.is_native ()) {
        Text = OwnedFile.get_uri ();
        return;
      }

      Text = get_display_name (OwnedFile);

      if (OwnedFile.query_file_type (0) == FileType.DIRECTORY) {
        setup_buttons ();

        try {
          dir_monitor = OwnedFile.monitor_directory (0);
          dir_monitor.changed.connect (handle_dir_changed);
        } catch {
          critical ("Unable to watch the stack directory '%s'.", OwnedFile.get_path () ?? "");
        }
      }
    }

    void stop_monitor () {
      if (dir_monitor != null) {
        dir_monitor.changed.disconnect (handle_dir_changed);
        dir_monitor.cancel ();
        dir_monitor = null;
      }
    }

    [CCode (instance_pos = -1)]
    void handle_dir_changed (File f, File? other, FileMonitorEvent event) {
      reset_icon_buffer ();
    }

    bool has_default_icon_match () {
      if (Icon == DEFAULT_ICONS)
        return true;

      var default_icons = DEFAULT_ICONS.split (";;");
      foreach (unowned string icon in Icon.split (";;"))
        if (icon in default_icons)
          return true;

      return false;
    }

    // A list is the item's menu, which a left click then shows as well
    void setup_buttons () {
      if (Prefs.StackStyle == StackView.LIST)
        Button = PopupButton.RIGHT | PopupButton.LEFT;
      else
        Button = PopupButton.RIGHT;
    }

    protected override void draw_icon_fast (Surface surface) {
      unowned Cairo.Context cr = surface.Context;
      var width = surface.Width;
      var height = surface.Height;
      var radius = 3 + 6 * height / (128 - 48);
      double x_scale = 1.0, y_scale = 1.0;
      surface.Internal.get_device_scale (out x_scale, out y_scale);
      var line_width_half = 0.5 * (int) double.max (x_scale, y_scale);

      cr.move_to (radius, line_width_half);
      cr.arc (width - radius - line_width_half, radius + line_width_half, radius, -Math.PI_2, 0);
      cr.arc (width - radius - line_width_half, height - radius - line_width_half, radius, 0, Math.PI_2);
      cr.arc (radius + line_width_half, height - radius - line_width_half, radius, Math.PI_2, Math.PI);
      cr.arc (radius + line_width_half, radius + line_width_half, radius, Math.PI, -Math.PI_2);
      cr.close_path ();

      cr.set_source_rgba (1, 1, 1, 0.6);
      cr.set_line_width (2 * line_width_half);
      cr.stroke_preserve ();

      var rg = new Cairo.Pattern.radial (width / 2, height, height / 8, width / 2, height, height);
      rg.add_color_stop_rgba (0, 0, 0, 0, 1);
      rg.add_color_stop_rgba (1, 0, 0, 0, 0.6);

      cr.set_source (rg);
      cr.fill ();
    }

    protected override void draw_icon (Surface surface) {
      if (Prefs.DirectoryStyle == DirStyle.SIMPLE) {
        base.draw_icon (surface);
        return;
      }

      if (!is_valid () || !has_default_icon_match ()) {
        base.draw_icon (surface);
        return;
      }

      unowned Cairo.Context cr = surface.Context;
      var width = surface.Width;
      var height = surface.Height;
      var radius = 3 + 6 * height / (128 - 48);

      draw_icon_fast (surface);

      var icons = new Gee.HashMap<string, string> ();
      var keys = new Gee.ArrayList<string> ();

      get_files (OwnedFile).map_iterator ().foreach ((display_name, file) => {
        string icon, text;
        var uri = file.get_uri ();
        if (uri.has_suffix (".desktop")) {
          ApplicationDockItem.parse_launcher (uri, out icon, out text);
        } else {
          icon = DrawingService.get_icon_from_file (file) ?? "";
          text = display_name ?? "";
        }

        var key = "%s%s".printf (text, uri);
        icons.set (key, icon);
        keys.add (key);

        return true;
      });

      var pos = 0;
      var icon_width = (int) ((width - 80 * radius / 33.0) / 2.0);
      var icon_height = (int) ((height - 80 * radius / 33.0) / 2.0);
      var offset = (int) ((width - 2 * icon_width) / 3.0);

      keys.sort ();
      foreach (var s in keys) {
        var x = pos % 2;
        int y = pos / 2;

        if (++pos > 4)
          break;

        var pbuf = DrawingService.load_icon (icons.get (s), icon_width, icon_height);
        Gdk.cairo_set_source_pixbuf (cr, pbuf,
                                     x * (icon_width + offset) + offset + (icon_width - pbuf.width) / 2,
                                     y * (icon_height + offset) + offset + (icon_height - pbuf.height) / 2);
        cr.paint ();
      }
    }

    void launch () {
      System.get_default ().open (OwnedFile);
      ClickedAnimation = AnimationType.BOUNCE;
      LastClicked = GLib.get_monotonic_time ();
    }

    protected override AnimationType on_clicked (PopupButton button, Gdk.ModifierType mod, uint32 event_time) {
      if (button == PopupButton.LEFT && show_stack ())
        return AnimationType.NONE;

      if (button == PopupButton.LEFT || button == PopupButton.MIDDLE) {
        launch ();
        return AnimationType.BOUNCE;
      }

      return AnimationType.NONE;
    }

    /**
     * Shows a directory's entries next to the item, as a fan or a grid,
     * if the item is set to and the directory has any.
     *
     * @return whether they were shown
     */
    bool show_stack () {
      if (Prefs.StackStyle == StackView.FOLDER || Prefs.StackStyle == StackView.LIST)
        return false;

      if (OwnedFile.query_file_type (0) != FileType.DIRECTORY)
        return false;

      unowned DockController? controller = get_dock ();
      if (controller == null)
        return false;

      var entries = get_stack_entries (OwnedFile);
      if (entries.is_empty)
        return false;

      unowned PositionManager position_manager = controller.position_manager;
      var area = position_manager.get_monitor_geometry ();

      int x, y;
      position_manager.get_hover_position (this, out x, out y);

      // A fan has its entries and one more, which opens the directory
      var fan_count = int.min (entries.size, STACK_FAN_MAX_ENTRIES) + 1;
      var fan_wanted = (Prefs.StackStyle == StackView.FAN);

      if (Prefs.StackStyle != StackView.GRID
          && stack_shows_fan (fan_wanted, position_manager.Position, entries.size)
          && FanWindow.fits (fan_count, x, y, area))
        show_fan (controller, entries, x, y);
      else
        show_grid (controller, x, y, area);

      return true;
    }

    void show_fan (DockController controller, Gee.ArrayList<StackEntry> entries, int x, int y) {
      var shown = new Gee.ArrayList<StackEntry> ();
      foreach (var entry in entries) {
        if (shown.size >= STACK_FAN_MAX_ENTRIES)
          break;
        shown.add (entry);
      }

      var remaining = entries.size - shown.size;
      var open_text = remaining > 0
        ? ngettext ("%d More in File Browser", "%d More in File Browser", remaining).printf (remaining)
        : _("Open in File Browser");
      shown.add (new StackEntry (OwnedFile, open_text, "folder-open", false, false));

      if (fan == null) {
        fan = new FanWindow ();
        fan.activated.connect (open_stack_entry);
        track_popup (fan);
      }

      fan.show_fan (shown, x, y);
    }

    void show_grid (DockController controller, int x, int y, Gdk.Rectangle area) {
      if (stack == null) {
        stack = new StackWindow ();
        stack.activated.connect (open_stack_entry);
        stack.open_requested.connect (open_stack_directory);
        track_popup (stack);
      }

      stack.show_stack (OwnedFile, get_stack_entries, Prefs.LargeIcons, controller.position_manager.Position, x, y, area);
    }

    // While a stack shows, the dock stays as it is, as with a menu
    void track_popup (Gtk.Window popup) {
      popup.show.connect (popup_shown);
      popup.hide.connect (popup_hidden);
    }

    void popup_shown () {
      unowned DockController? controller = get_dock ();
      if (controller != null)
        controller.window.set_popup_visible (true);
    }

    void popup_hidden () {
      unowned DockController? controller = get_dock ();
      if (controller != null)
        controller.window.set_popup_visible (false);
    }

    void open_stack_directory (File directory) {
      System.get_default ().open (directory);

      ClickedAnimation = AnimationType.BOUNCE;
      LastClicked = GLib.get_monotonic_time ();
    }

    void open_stack_entry (StackEntry entry) {
      if (entry.is_launcher)
        System.get_default ().launch (entry.file);
      else
        System.get_default ().open (entry.file);

      ClickedAnimation = AnimationType.BOUNCE;
      LastClicked = GLib.get_monotonic_time ();
    }

    public override bool can_be_removed () {
      return Prefs.DirectoryStyle == DirStyle.SIMPLE;
    }

    public class FileSortData {
      public string creation_date { get; private set; }
      public string modified_date { get; private set; }
      public string display_name { get; private set; }
      public string content_type { get; private set; }
      public int64 size { get; private set; }
      public Gtk.MenuItem menu_item { get; private set; }

      public FileSortData (string creation_date, string modified_date, string display_name,
        string content_type, int64 size, Gtk.MenuItem menu_item) {
        this.creation_date = creation_date;
        this.modified_date = modified_date;
        this.display_name = display_name;
        this.content_type = content_type;
        this.size = size;
        this.menu_item = menu_item;
      }
    }

    /**
     * {@inheritDoc}
     */
    public override Gee.ArrayList<Gtk.MenuItem> get_menu_items () {
      if (OwnedFile.query_file_type (0) == FileType.DIRECTORY)
        return get_dir_menu_items ();

      return get_file_menu_items ();
    }

    // The directory's own entries come first, where they are found
    // however many files follow them
    Gee.ArrayList<Gtk.MenuItem> get_dir_menu_items () {
      var items = new Gee.ArrayList<Gtk.MenuItem> ();

      var item = create_menu_item (_("_Open in File Browser"), "gtk-open");
      item.activate.connect (() => {
        launch ();
      });
      items.add (item);

      if (OwnedFile.is_native ()) {
        item = create_menu_item (_("Open in _Terminal"), "utilities-terminal");
        item.activate.connect (() => {
          open_terminal (OwnedFile);
        });
        items.add (item);
      }

      var view_options_item = new Gtk.MenuItem.with_mnemonic (_("_View Options"));
      view_options_item.activate.connect (() => {
        show_view_options_dialog ();
      });
      items.add (view_options_item);

      unowned DefaultApplicationDockItemProvider? default_provider = (Container as DefaultApplicationDockItemProvider);
      if (default_provider != null
          && !default_provider.Prefs.LockItems) {
        var delete_item = new Gtk.CheckMenuItem.with_mnemonic (_("_Keep in Dock"));
        delete_item.active = true;
        delete_item.activate.connect (() => delete ());
        items.add (delete_item);
      }

      items.add (new Gtk.SeparatorMenuItem ());

      var sorted_items = create_file_menu_items (OwnedFile);

      foreach (var data in sorted_items) {
        items.add (data.menu_item);
      }

      return items;
    }

    void show_view_options_dialog () {
      var dialog = new Gtk.Dialog.with_buttons (
        _("View Options"),
        null,
        Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
        _("_Cancel"), Gtk.ResponseType.CANCEL,
        _("_OK"), Gtk.ResponseType.OK
      );

      dialog.set_resizable (false);

      var content_area = dialog.get_content_area ();
      content_area.spacing = 12;
      content_area.border_width = 12;

      var grid = new Gtk.Grid ();
      grid.set_row_spacing (12);
      grid.set_column_spacing (12);
      grid.set_hexpand (true);

      var sort_label = new Gtk.Label (_("Sort By:"));
      sort_label.set_halign (Gtk.Align.START);

      var sort_combo = new Gtk.ComboBoxText ();
      sort_combo.append ("name", _("Name"));
      sort_combo.append ("kind", _("Kind"));
      sort_combo.append ("size", _("Size"));
      sort_combo.append ("date-created", _("Date Created"));
      sort_combo.append ("date-modified", _("Date Modified"));
      sort_combo.active_id = Prefs.SortBy;
      sort_combo.set_hexpand (true);

      var style_label = new Gtk.Label (_("Style:"));
      style_label.set_halign (Gtk.Align.START);

      var style_combo = new Gtk.ComboBoxText ();
      style_combo.append ("simple", _("Simple"));
      style_combo.append ("tile", _("Tile"));
      style_combo.active_id = (Prefs.DirectoryStyle == DirStyle.SIMPLE) ? "simple" : "tile";
      style_combo.set_hexpand (true);

      var stack_label = new Gtk.Label (_("View Content As:"));
      stack_label.set_halign (Gtk.Align.START);

      var stack_combo = new Gtk.ComboBoxText ();
      stack_combo.append ("automatic", _("Automatic"));
      stack_combo.append ("fan", _("Fan"));
      stack_combo.append ("grid", _("Grid"));
      stack_combo.append ("list", _("List"));
      stack_combo.append ("folder", _("Folder"));
      stack_combo.active_id = stack_style_id (Prefs.StackStyle);
      stack_combo.set_hexpand (true);

      var large_icons_label = new Gtk.Label (_("Large Icons:"));
      large_icons_label.set_halign (Gtk.Align.START);

      var large_icons_switch = new Gtk.Switch ();
      large_icons_switch.set_active (Prefs.LargeIcons);
      large_icons_switch.set_halign (Gtk.Align.START);

      var hidden_label = new Gtk.Label (_("Show Hidden Files:"));
      hidden_label.set_halign (Gtk.Align.START);

      var hidden_switch = new Gtk.Switch ();
      hidden_switch.set_active (Prefs.ShowHiddenFiles);
      hidden_switch.set_halign (Gtk.Align.START);

      grid.attach (sort_label, 0, 0, 1, 1);
      grid.attach (sort_combo, 1, 0, 1, 1);
      grid.attach (style_label, 0, 1, 1, 1);
      grid.attach (style_combo, 1, 1, 1, 1);
      grid.attach (stack_label, 0, 2, 1, 1);
      grid.attach (stack_combo, 1, 2, 1, 1);
      grid.attach (large_icons_label, 0, 3, 1, 1);
      grid.attach (large_icons_switch, 1, 3, 1, 1);
      grid.attach (hidden_label, 0, 4, 1, 1);
      grid.attach (hidden_switch, 1, 4, 1, 1);

      content_area.pack_start (grid, true, true, 0);

      dialog.show_all ();

      dialog.response.connect ((response_id) => {
        if (response_id == Gtk.ResponseType.OK) {
          var new_sort = sort_combo.active_id;
          if (new_sort != null && new_sort != Prefs.SortBy) {
            Prefs.SortBy = new_sort;
          }

          var new_style = style_combo.active_id;
          if (new_style != null) {
            var new_dir_style = (new_style == "simple") ? DirStyle.SIMPLE : DirStyle.TILE;
            if (new_dir_style != Prefs.DirectoryStyle) {
              Prefs.DirectoryStyle = new_dir_style;
              setup_buttons ();
              reset_icon_buffer ();
            }
          }

          var new_stack = stack_combo.active_id;
          if (new_stack != null && stack_style_from_id (new_stack) != Prefs.StackStyle) {
            Prefs.StackStyle = stack_style_from_id (new_stack);
            setup_buttons ();
          }

          var new_large_icons = large_icons_switch.get_active ();
          if (new_large_icons != Prefs.LargeIcons) {
            Prefs.LargeIcons = new_large_icons;
          }

          var new_hidden = hidden_switch.get_active ();
          if (new_hidden != Prefs.ShowHiddenFiles) {
            Prefs.ShowHiddenFiles = new_hidden;
          }
        }
        dialog.destroy ();
      });
    }

    static string stack_style_id (StackView style) {
      switch (style) {
      default:
      case StackView.AUTOMATIC:
        return "automatic";
      case StackView.FAN:
        return "fan";
      case StackView.GRID:
        return "grid";
      case StackView.LIST:
        return "list";
      case StackView.FOLDER:
        return "folder";
      }
    }

    static StackView stack_style_from_id (string id) {
      switch (id) {
      default:
      case "automatic":
        return StackView.AUTOMATIC;
      case "fan":
        return StackView.FAN;
      case "grid":
        return StackView.GRID;
      case "list":
        return StackView.LIST;
      case "folder":
        return StackView.FOLDER;
      }
    }

    Gee.ArrayList<Gtk.MenuItem> get_file_menu_items () {
      var items = new Gee.ArrayList<Gtk.MenuItem> ();

      unowned DefaultApplicationDockItemProvider? default_provider = (Container as DefaultApplicationDockItemProvider);
      if (default_provider != null
          && !default_provider.Prefs.LockItems) {
        var delete_item = new Gtk.CheckMenuItem.with_mnemonic (_("_Keep in Dock"));
        delete_item.active = true;
        delete_item.activate.connect (() => delete ());
        items.add (delete_item);
      }

      var item = create_menu_item (_("_Open"), "gtk-open");
      item.activate.connect (launch);
      items.add (item);

      item = create_menu_item (_("Open _With…"), "");
      item.activate.connect (() => show_open_with_dialog (OwnedFile));
      items.add (item);

      item = create_menu_item (_("Open Containing _Folder"), "folder");
      item.activate.connect (() => {
        System.get_default ().open (OwnedFile.get_parent ());
        ClickedAnimation = AnimationType.BOUNCE;
        LastClicked = GLib.get_monotonic_time ();
      });
      items.add (item);

      return items;
    }

    /**
     * Lists a directory's entries, sorted as the item is set to.
     *
     * @param directory the item's directory or one below it
     * @return the entries
     */
    internal Gee.ArrayList<StackEntry> get_stack_entries (File directory) {
      var entries = new Gee.ArrayList<StackEntry> ();

      get_files (directory).map_iterator ().foreach ((display_name, file) => {
        string content_type = "", creation_date = "", modified_date = "", icon, text;
        int64 size = 0;
        var uri = file.get_uri ();

        try {
          var fileInfo = file.query_info (GLib.FileAttribute.TIME_CREATED + ","
                                          + GLib.FileAttribute.TIME_MODIFIED + ","
                                          + GLib.FileAttribute.STANDARD_CONTENT_TYPE + ","
                                          + GLib.FileAttribute.STANDARD_SIZE + ","
                                          + GLib.FileAttribute.STANDARD_TYPE, 0);

          var creation_datetime = fileInfo.get_creation_date_time ();
          if (creation_datetime != null) {
            creation_date = creation_datetime.to_string ();
          }

          var modified_datetime = fileInfo.get_modification_date_time ();
          if (modified_datetime != null) {
            modified_date = modified_datetime.to_string ();
          }

          content_type = fileInfo.get_content_type () ?? "";
          size = fileInfo.get_size ();

          if (fileInfo.get_file_type () == GLib.FileType.DIRECTORY) {
            content_type = "directory";
          }
        } catch (GLib.Error e) {
          // Use default values if information can't be determined
        }

        var is_launcher = uri.has_suffix (".desktop");
        if (is_launcher) {
          ApplicationDockItem.parse_launcher (uri, out icon, out text);
        } else {
          icon = DrawingService.get_icon_from_file (file) ?? "";
          text = display_name ?? "";
        }

        entries.add (new StackEntry (file, text ?? "", icon ?? "", !is_launcher && content_type == "directory", is_launcher,
                                     content_type, creation_date, modified_date, size));

        return true;
      });

      entries.sort ((a, b) => {
        bool a_is_dir = (a.content_type == "directory");
        bool b_is_dir = (b.content_type == "directory");

        if (Prefs.SortBy == "kind" && a_is_dir != b_is_dir) {
          return a_is_dir ? -1 : 1;
        }

        switch (Prefs.SortBy) {
          case "name":
            return compare_names (a.text, b.text);
          case "date-created":
            string date_a = a.creation_date;
            string date_b = b.creation_date;

            if (date_a == date_b || date_a == "" || date_b == "") {
              return compare_names (a.text, b.text);
            }

            return date_b.collate (date_a);
          case "date-modified":
            string date_a = a.modified_date;
            string date_b = b.modified_date;

            if (date_a == date_b || date_a == "" || date_b == "") {
              return compare_names (a.text, b.text);
            }

            return date_b.collate (date_a);
          case "kind":
            int type_compare = a.content_type.collate (b.content_type);
            if (type_compare != 0) {
              return type_compare;
            }

            return compare_names (a.text, b.text);
          case "size":
            if (a.size == b.size) {
              return compare_names (a.text, b.text);
            }

            return (b.size > a.size) ? 1 : -1;
          default:
            return compare_names (a.text, b.text);
        }
      });

      return entries;
    }

    // Names in the order file managers list them, with "file 2" before
    // "file 10"
    static int compare_names (string a, string b) {
      return strcmp (a.collate_key_for_filename (), b.collate_key_for_filename ());
    }

    Gee.ArrayList<FileSortData> create_file_menu_items (File directory) {
      var sorted_items = new Gee.ArrayList<FileSortData> ();

      foreach (var entry in get_stack_entries (directory)) {
        Gtk.MenuItem item;
        var file = entry.file;

        if (entry.is_launcher) {
          item = create_file_menu_item (entry.text, entry.icon, true, true);
          item.activate.connect (() => {
            System.get_default ().launch (file);
            ClickedAnimation = AnimationType.BOUNCE;
            LastClicked = GLib.get_monotonic_time ();
          });
        } else {
          item = create_file_menu_item (entry.text, entry.icon, true, false);

          if (entry.is_directory) {
            var nested_submenu = new Gtk.Menu ();
            item.set_submenu (nested_submenu);

            bool nested_submenu_populated = false;

            nested_submenu.show.connect (() => {
              if (!nested_submenu_populated) {
                populate_directory_submenu (file, nested_submenu);
                nested_submenu_populated = true;
              }
            });
          } else {
            item.activate.connect (() => {
              System.get_default ().open (file);
              ClickedAnimation = AnimationType.BOUNCE;
              LastClicked = GLib.get_monotonic_time ();
            });
          }
        }

        sorted_items.add (new FileSortData (entry.creation_date, entry.modified_date, entry.text, entry.content_type,
                                            entry.size, item));
      }

      if (sorted_items.size == 0) {
        var empty_item = new Gtk.MenuItem.with_label (_("Empty Directory"));
        empty_item.sensitive = false;
        var empty_data = new FileSortData ("", "", _("Empty Directory"), "", 0, empty_item);
        sorted_items.add (empty_data);
      }

      return sorted_items;
    }

    // A subdirectory's own entries come first, next to where its submenu
    // opens, however many files follow them
    void populate_directory_submenu (File directory, Gtk.Menu submenu) {
      var open_item = create_menu_item (_("_Open in File Browser"), "gtk-open");
      open_item.activate.connect (() => {
        System.get_default ().open (directory);
        ClickedAnimation = AnimationType.BOUNCE;
        LastClicked = GLib.get_monotonic_time ();
      });
      submenu.append (open_item);

      if (directory.is_native ()) {
        var terminal_item = create_menu_item (_("Open in _Terminal"), "utilities-terminal");
        terminal_item.activate.connect (() => {
          open_terminal (directory);
        });
        submenu.append (terminal_item);
      }

      submenu.append (new Gtk.SeparatorMenuItem ());

      foreach (var data in create_file_menu_items (directory)) {
        submenu.append (data.menu_item);
      }

      submenu.show_all ();
    }

    Gtk.MenuItem create_file_menu_item (string title, string? icon, bool force_show_icon = true, bool mnemonics = true) {
      if (icon == null || icon == "")
        return new Gtk.MenuItem.with_label (title);

      int width, height;
      if (Prefs.LargeIcons) {
        Gtk.icon_size_lookup (Gtk.IconSize.LARGE_TOOLBAR, out width, out height);
      } else {
        Gtk.icon_size_lookup (Gtk.IconSize.MENU, out width, out height);
      }

      var pixbuf = DrawingService.load_icon (icon, width, height);

      var item = new Gtk.MenuItem ();
      var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);

      var image = new Gtk.Image.from_pixbuf (pixbuf);
      var label = mnemonics ? new Gtk.Label.with_mnemonic (title) : new Gtk.Label (title);

      label.halign = Gtk.Align.START;
      label.valign = Gtk.Align.CENTER;

      if (force_show_icon) {
        box.pack_start (image, false, false, 0);
      }
      box.pack_start (label, true, true, 0);

      item.add (box);
      item.show_all ();

      return item;
    }

    Gee.HashMap<string, File> get_files (File file) {
      var files = new Gee.HashMap<string, File> ();
      var count = 0U;

      try {
        var enumerator = file.enumerate_children (FileAttribute.STANDARD_NAME + ","
                                                  + FileAttribute.STANDARD_DISPLAY_NAME + ","
                                                  + FileAttribute.STANDARD_IS_HIDDEN + ","
                                                  + FileAttribute.ACCESS_CAN_READ, 0);

        FileInfo info;

        while ((info = enumerator.next_file ()) != null) {
          if (!Prefs.ShowHiddenFiles && info.get_is_hidden ())
            continue;

          if (count++ >= FOLDER_MAX_FILE_COUNT) {
            critical ("There are way too many files (%u+) in '%s'.", FOLDER_MAX_FILE_COUNT, file.get_path ());
            break;
          }

          unowned string name = info.get_name ();
          files.set (info.get_display_name () ?? name, file.get_child (name));
        }
      } catch {}

      return files;
    }

    static string get_display_name (File file) {
      try {
        var info = file.query_info (FileAttribute.STANDARD_NAME + "," + FileAttribute.STANDARD_DISPLAY_NAME, 0);
        return info.get_display_name () ?? info.get_name ();
      } catch {}

      debug ("Could not get display-name for '%s'", file.get_path () ?? "");

      return "Unknown";
    }
  }
}

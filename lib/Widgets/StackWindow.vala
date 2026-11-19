//
// Copyright (C) 2026 Plank Reloaded Developers
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
   * One entry of a directory item's stack: a file, a directory or a
   * launcher in the directory.
   */
  internal class StackEntry : GLib.Object {
    public File file { get; construct; }
    public string text { get; construct; }
    public string icon { get; construct; }
    public bool is_directory { get; construct; }
    public bool is_launcher { get; construct; }

    // What the entries are sorted by
    public string content_type { get; construct; }
    public string creation_date { get; construct; }
    public string modified_date { get; construct; }
    public int64 size { get; construct; }

    public StackEntry (File file, string text, string icon, bool is_directory, bool is_launcher,
                       string content_type = "", string creation_date = "", string modified_date = "", int64 size = 0) {
      GLib.Object (file: file, text: text, icon: icon, is_directory: is_directory, is_launcher: is_launcher,
                   content_type: content_type, creation_date: creation_date, modified_date: modified_date, size: size);
    }
  }

  /**
   * Lists a directory's entries for a stack, sorted as its item is set to.
   */
  internal delegate Gee.ArrayList<StackEntry> StackLoader (File directory);

  /**
   * Asks which application to open a file with, and opens it with the one
   * chosen.
   *
   * @param file the file
   */
  internal void show_open_with_dialog (File file) {
    var dialog = new Gtk.AppChooserDialog (null, Gtk.DialogFlags.MODAL, file);
    dialog.set_position (Gtk.WindowPosition.CENTER);
    dialog.set_keep_above (true);

    dialog.response.connect ((response_id) => {
      if (response_id == Gtk.ResponseType.OK) {
        var info = dialog.get_app_info ();
        if (info != null) {
          var files = new GLib.List<File> ();
          files.append (file);

          try {
            info.launch (files, System.get_default ().context);
          } catch (Error e) {
            warning ("Could not open '%s' with '%s': %s", file.get_uri (), info.get_name (), e.message);
          }
        }
      }

      dialog.destroy ();
    });

    dialog.show ();
  }

  /**
   * A popup that shows a directory's entries as a grid of icons next to
   * its dock item. Directories among them open in place, with a way back,
   * so the whole tree below the item's directory can be browsed.
   */
  internal class StackWindow : Gtk.Window {
    // The space between the dock item and the popup, as for tooltips
    const int GAP = 10;
    const int PADDING = 8;
    const int TILE_SPACING = 4;
    const int TILE_PADDING = 6;
    const int TILE_WIDTH = 104;
    const int ICON_SIZE = 48;
    const int LARGE_ICON_SIZE = 64;
    const int LABEL_LINES = 2;

    static construct
    {
      set_accessible_role (Atk.Role.POPUP_MENU);
      set_css_name ("tooltip");
    }

    /**
     * Emitted when a file or a launcher was chosen, after the popup closed.
     */
    public signal void activated (StackEntry entry);

    /**
     * Emitted when a directory is to open in the file manager, after the
     * popup closed.
     */
    public signal void open_requested (File directory);

    Gtk.Button back_button;
    Gtk.Label title_label;
    Gtk.ScrolledWindow scroller;
    Gtk.FlowBox grid;
    Gtk.Menu? menu = null;

    unowned StackLoader? loader = null;
    File? current = null;
    Gee.ArrayList<File> history = new Gee.ArrayList<File> ();
    Gee.ArrayList<StackEntry?> shown = new Gee.ArrayList<StackEntry?> ();
    int columns = 1;
    int cursor = -1;
    bool large_icons = false;
    bool grabbed = false;

    Gtk.PositionType position;
    int anchor_x;
    int anchor_y;
    Gdk.Rectangle area;

    public StackWindow () {
      GLib.Object (type: Gtk.WindowType.POPUP, type_hint: Gdk.WindowTypeHint.POPUP_MENU);
    }

    construct
    {
      init_tooltip_window (this);

      add_events (Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.KEY_PRESS_MASK);

      var provider = new Gtk.CssProvider ();
      try {
        provider.load_from_data ("""
          .plank-stack flowboxchild { border-radius: 6px; }
          .plank-stack flowboxchild:hover { background-color: alpha(currentColor, 0.12); }
          .plank-stack flowboxchild:selected { background-color: alpha(currentColor, 0.24); color: inherit; }
          .plank-stack scrolledwindow, .plank-stack viewport, .plank-stack flowbox { background-color: transparent; }
          .plank-stack button { color: inherit; }
        """);
        Gtk.StyleContext.add_provider_for_screen (get_screen (), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
      } catch (Error e) {
        warning ("Could not load the stack's style: %s", e.message);
      }
      get_style_context ().add_class ("plank-stack");

      var box = new Gtk.Box (Gtk.Orientation.VERTICAL, TILE_SPACING);
      box.margin = PADDING;

      var header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, TILE_SPACING);

      back_button = create_header_button ("go-previous-symbolic", _("Back"));
      back_button.clicked.connect (go_back);
      back_button.no_show_all = true;
      header.pack_start (back_button, false, false, 0);

      title_label = new Gtk.Label (null);
      title_label.ellipsize = Pango.EllipsizeMode.MIDDLE;
      title_label.max_width_chars = 1;
      title_label.hexpand = true;
      var attributes = new Pango.AttrList ();
      attributes.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
      title_label.set_attributes (attributes);
      header.pack_start (title_label, true, true, 0);

      var open_button = create_header_button ("folder-open-symbolic", _("Open in File Browser"));
      open_button.clicked.connect (() => {
        var directory = current;
        close_stack ();
        if (directory != null)
          open_requested (directory);
      });
      header.pack_end (open_button, false, false, 0);

      box.pack_start (header, false, false, 0);

      grid = new Gtk.FlowBox ();
      grid.homogeneous = true;
      grid.selection_mode = Gtk.SelectionMode.SINGLE;
      grid.activate_on_single_click = true;
      grid.row_spacing = TILE_SPACING;
      grid.column_spacing = TILE_SPACING;
      grid.valign = Gtk.Align.START;
      grid.child_activated.connect ((child) => activate_index (child.get_index ()));
      grid.button_press_event.connect (grid_button_pressed);

      scroller = new Gtk.ScrolledWindow (null, null);
      scroller.hscrollbar_policy = Gtk.PolicyType.NEVER;
      scroller.vscrollbar_policy = Gtk.PolicyType.AUTOMATIC;
      scroller.propagate_natural_width = true;
      scroller.overlay_scrolling = true;
      scroller.add (grid);
      box.pack_start (scroller, true, true, 0);

      add (box);
      box.show_all ();
    }

    static Gtk.Button create_header_button (string icon, string tooltip) {
      var button = new Gtk.Button.from_icon_name (icon, Gtk.IconSize.MENU);
      button.relief = Gtk.ReliefStyle.NONE;
      button.can_focus = false;
      button.tooltip_text = tooltip;
      button.get_accessible ().set_name (tooltip);

      return button;
    }

    /**
     * Shows a directory's entries next to a dock item. All geometry is in
     * logical pixels.
     *
     * @param directory the directory
     * @param loader lists a directory's entries, which has to stay valid while the popup shows
     * @param large_icons whether to show large icons
     * @param position the dock's position
     * @param anchor_x the x coordinate of the item's tooltip anchor
     * @param anchor_y the y coordinate of the item's tooltip anchor
     * @param area the dock's area, the monitor or its work area
     */
    public void show_stack (File directory, StackLoader loader, bool large_icons, Gtk.PositionType position,
                            int anchor_x, int anchor_y, Gdk.Rectangle area) {
      this.loader = loader;
      this.large_icons = large_icons;
      this.position = position;
      this.anchor_x = anchor_x;
      this.anchor_y = anchor_y;
      this.area = area;

      history.clear ();
      show_directory (directory);

      if (!grabbed) {
        grab_popup (this);
        grabbed = true;
      }
    }

    /**
     * Closes the popup if it is showing, and drops its tiles.
     */
    public void close_stack () {
      if (menu != null) {
        menu.destroy ();
        menu = null;
      }

      if (grabbed) {
        ungrab_popup (this);
        grabbed = false;
      }

      hide ();
      clear_tiles ();
      history.clear ();
      current = null;
      loader = null;
    }

    void clear_tiles () {
      grid.foreach ((child) => child.destroy ());
      shown.clear ();
      cursor = -1;
    }

    void show_directory (File directory) {
      current = directory;
      clear_tiles ();

      var entries = (loader != null ? loader (directory) : new Gee.ArrayList<StackEntry> ());

      title_label.set_text (directory_title (directory));
      back_button.visible = !history.is_empty;

      // Without tiles, the popup's size is what it adds around them: the
      // header, the padding and the theme's frame. GTK measures hidden
      // widgets as empty
      scroller.hide ();
      Gtk.Requisition empty;
      get_preferred_size (null, out empty);
      scroller.show ();

      int width, height;
      compute_preview_space (out width, out height, position, anchor_x, anchor_y, GAP, area);

      var icon_size = (large_icons ? LARGE_ICON_SIZE : ICON_SIZE);
      var tile_width = int.max (TILE_WIDTH, icon_size + 2 * TILE_PADDING + 24);

      // More entries than a grid holds are counted on a last tile
      var count = int.min (entries.size, STACK_GRID_MAX_ENTRIES);
      var rest = entries.size - count;

      for (var i = 0; i < count; i++) {
        shown.add (entries[i]);
        grid.add (create_tile (entries[i].text, entries[i].icon, icon_size, tile_width));
      }

      if (entries.is_empty) {
        shown.add (null);
        var tile = create_tile (_("Empty Directory"), "folder-open", icon_size, tile_width);
        tile.sensitive = false;
        grid.add (tile);
      } else if (rest > 0) {
        shown.add (null);
        grid.add (create_tile (ngettext ("%d More in File Browser", "%d More in File Browser", rest).printf (rest),
                               "folder-open", icon_size, tile_width));
      }

      grid.show_all ();

      // Tiles are all as wide and as tall as the largest, which the theme
      // may pad
      var tile_height = 0;
      grid.foreach ((child) => {
        int natural_width, natural_height;
        child.get_preferred_width (null, out natural_width);
        child.get_preferred_height (null, out natural_height);
        tile_width = int.max (tile_width, natural_width);
        tile_height = int.max (tile_height, natural_height);
      });

      int rows, visible_rows;
      compute_stack_grid (out columns, out rows, out visible_rows, shown.size, tile_width, tile_height, TILE_SPACING,
                          width - empty.width, height - empty.height);

      grid.min_children_per_line = columns;
      grid.max_children_per_line = columns;

      // Names wrapping at the tiles' width can make them taller than they
      // asked to be on their own, so the rows are measured as laid out
      int grid_height;
      grid.get_preferred_height_for_width (columns * tile_width + (columns - 1) * TILE_SPACING, null, out grid_height);
      var row_height = (grid_height - (rows - 1) * TILE_SPACING) / rows;
      if (row_height > tile_height) {
        tile_height = row_height;
        compute_stack_grid (out columns, out rows, out visible_rows, shown.size, tile_width, tile_height, TILE_SPACING,
                            width - empty.width, height - empty.height);
      }

      var visible_height = visible_rows * tile_height + (visible_rows - 1) * TILE_SPACING;
      // Neither limit can be set past the other
      scroller.min_content_height = -1;
      scroller.max_content_height = -1;
      scroller.min_content_height = visible_height;
      scroller.max_content_height = visible_height;
      scroller.get_vadjustment ().set_value (0);

      // realize and show the window early to be able to move it, as
      // HoverWindow does; the natural size is the new one even while a
      // showing window still has its old allocation
      show ();

      Gtk.Requisition natural;
      get_preferred_size (null, out natural);

      int x, y;
      compute_preview_position (out x, out y, position, anchor_x, anchor_y, natural.width, natural.height, GAP, area);
      move (x, y);
    }

    static string directory_title (File directory) {
      try {
        var info = directory.query_info (FileAttribute.STANDARD_DISPLAY_NAME, 0);
        return info.get_display_name ();
      } catch (Error e) {
        return directory.get_basename () ?? directory.get_uri ();
      }
    }

    Gtk.Widget create_tile (string text, string icon, int icon_size, int tile_width) {
      var box = new Gtk.Box (Gtk.Orientation.VERTICAL, TILE_SPACING);
      box.margin = TILE_PADDING;

      // Surfaces with the scale factor draw sharp on HiDPI screens
      var image = new Gtk.Image.from_surface (DrawingService.load_icon_for_scale (icon, icon_size, icon_size, get_scale_factor ()));
      image.set_size_request (icon_size, icon_size);
      box.pack_start (image, false, false, 0);

      var label = new Gtk.Label (text);
      label.justify = Gtk.Justification.CENTER;
      label.wrap = true;
      label.wrap_mode = Pango.WrapMode.WORD_CHAR;
      label.lines = LABEL_LINES;
      label.ellipsize = Pango.EllipsizeMode.END;
      label.max_width_chars = 1;
      label.valign = Gtk.Align.START;
      label.set_size_request (tile_width - 2 * TILE_PADDING, -1);
      box.pack_start (label, false, false, 0);

      var tile = new Gtk.FlowBoxChild ();
      tile.can_focus = false;
      tile.tooltip_text = text;
      tile.add (box);

      return tile;
    }

    void activate_index (int index) {
      if (index < 0 || index >= shown.size)
        return;

      var entry = shown[index];
      var directory = current;

      // The last tile, counting the entries left out
      if (entry == null) {
        if (!grid.get_child_at_index (index).sensitive)
          return;

        close_stack ();
        if (directory != null)
          open_requested (directory);
        return;
      }

      if (entry.is_directory) {
        history.add (current);
        show_directory (entry.file);
        return;
      }

      close_stack ();
      activated (entry);
    }

    void go_back () {
      if (history.is_empty)
        return;

      show_directory (history.remove_at (history.size - 1));
    }

    void move_cursor (int index) {
      index = index.clamp (0, shown.size - 1);
      unowned Gtk.FlowBoxChild? child = grid.get_child_at_index (index);
      if (child == null)
        return;

      cursor = index;
      grid.select_child (child);

      // Keep the tile in view
      Gtk.Allocation allocation;
      child.get_allocation (out allocation);
      scroller.get_vadjustment ().clamp_page (allocation.y, allocation.y + allocation.height);
    }

    bool grid_button_pressed (Gdk.EventButton event) {
      if (event.button != Gdk.BUTTON_SECONDARY)
        return Gdk.EVENT_PROPAGATE;

      unowned Gtk.FlowBoxChild? child = grid.get_child_at_pos ((int) event.x, (int) event.y);
      if (child == null)
        return Gdk.EVENT_STOP;

      var index = child.get_index ();
      if (index < 0 || index >= shown.size || shown[index] == null)
        return Gdk.EVENT_STOP;

      grid.select_child (child);
      cursor = index;
      show_entry_menu (shown[index], event);

      return Gdk.EVENT_STOP;
    }

    void show_entry_menu (StackEntry entry, Gdk.EventButton event) {
      if (menu != null)
        menu.destroy ();

      menu = new Gtk.Menu ();
      menu.attach_to_widget (this, null);

      var file = entry.file;

      var item = new Gtk.MenuItem.with_mnemonic (_("_Open"));
      item.activate.connect (() => {
        close_stack ();
        if (entry.is_directory)
          open_requested (file);
        else
          activated (entry);
      });
      menu.append (item);

      if (!entry.is_directory && !entry.is_launcher) {
        item = new Gtk.MenuItem.with_mnemonic (_("Open _With…"));
        item.activate.connect (() => {
          close_stack ();
          show_open_with_dialog (file);
        });
        menu.append (item);
      }

      if (file.is_native ()) {
        if (entry.is_directory) {
          item = new Gtk.MenuItem.with_mnemonic (_("Open in _Terminal"));
          item.activate.connect (() => {
            close_stack ();
            open_terminal (file);
          });
          menu.append (item);
        }

        item = new Gtk.MenuItem.with_mnemonic (_("_Copy Path"));
        item.activate.connect (() => {
          var path = file.get_path ();
          close_stack ();
          if (path != null)
            Gtk.Clipboard.get (Gdk.SELECTION_CLIPBOARD).set_text (path, -1);
        });
        menu.append (item);
      }

      // The menu takes the pointer and gives it up as it closes, rather
      // than back, so the popup takes it again
      menu.hide.connect (() => {
        Idle.add (() => {
          if (visible && grabbed)
            grab_popup (this);
          return Source.REMOVE;
        });
      });

      menu.show_all ();
      menu.popup_at_pointer (event);
    }

    /**
     * {@inheritDoc}
     */
    public override bool button_press_event (Gdk.EventButton event) {
      // With the pointer taken, a press anywhere else arrives here
      if (!point_on_popup (this, event.x_root, event.y_root)) {
        close_stack ();
        return Gdk.EVENT_STOP;
      }

      return base.button_press_event (event);
    }

    /**
     * {@inheritDoc}
     */
    public override bool key_press_event (Gdk.EventKey event) {
      switch (event.keyval) {
      case Gdk.Key.Escape:
        close_stack ();
        break;
      case Gdk.Key.BackSpace:
        go_back ();
        break;
      case Gdk.Key.Left:
      case Gdk.Key.KP_Left:
        if ((event.state & Gdk.ModifierType.MOD1_MASK) != 0)
          go_back ();
        else
          move_cursor (cursor < 0 ? 0 : cursor - 1);
        break;
      case Gdk.Key.Right:
      case Gdk.Key.KP_Right:
        move_cursor (cursor + 1);
        break;
      case Gdk.Key.Up:
      case Gdk.Key.KP_Up:
        move_cursor (cursor < 0 ? 0 : (cursor - columns >= 0 ? cursor - columns : cursor));
        break;
      case Gdk.Key.Down:
      case Gdk.Key.KP_Down:
        move_cursor (cursor < 0 ? 0 : (cursor + columns < shown.size ? cursor + columns : cursor));
        break;
      case Gdk.Key.Home:
        move_cursor (0);
        break;
      case Gdk.Key.End:
        move_cursor (shown.size - 1);
        break;
      case Gdk.Key.Return:
      case Gdk.Key.KP_Enter:
      case Gdk.Key.space:
        activate_index (cursor);
        break;
      default:
        break;
      }

      return Gdk.EVENT_STOP;
    }

    /**
     * {@inheritDoc}
     */
    public override bool draw (Cairo.Context cr) {
      draw_tooltip_window (this, cr);

      return base.draw (cr);
    }
  }
}

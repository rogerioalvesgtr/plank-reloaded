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
   * The most entries a fan shows, not counting its last one, which opens
   * the directory in the file manager.
   */
  public const int STACK_FAN_MAX_ENTRIES = 9;

  /**
   * The most entries a grid shows of a directory; the rest are counted on
   * a last tile that opens the directory in the file manager.
   */
  public const int STACK_GRID_MAX_ENTRIES = 150;

  /**
   * The most columns and visible rows of a grid. Further rows scroll.
   */
  public const int STACK_GRID_MAX_COLUMNS = 6;
  public const int STACK_GRID_MAX_ROWS = 4;

  /**
   * Whether a directory item's entries fan out, rather than show in a
   * grid, when its stack style leaves the two to choose from. A fan only
   * rises from a dock at the bottom of the screen and only holds a few
   * entries, so left to choose, it is taken for directories that fit, while
   * an asked for fan is kept however many entries there are. On the other
   * edges it is always a grid. Pure, testable in isolation.
   *
   * @param fan_wanted whether the style asks for a fan, rather than leaving the choice
   * @param position the dock's position
   * @param entries how many entries the directory has
   * @return whether to show a fan
   */
  public static bool stack_shows_fan (bool fan_wanted, Gtk.PositionType position, int entries) {
    if (position != Gtk.PositionType.BOTTOM)
      return false;

    return (fan_wanted || entries <= STACK_FAN_MAX_ENTRIES);
  }

  /**
   * The shape of a grid of tiles: as many columns as fit, up to
   * STACK_GRID_MAX_COLUMNS, then evened out over the rows needed, so 7
   * tiles with room for 6 columns make rows of 4 and 3 rather than 6 and
   * 1. The rows that don't fit, or exceed STACK_GRID_MAX_ROWS, scroll.
   * There is always at least one column and one visible row, however
   * little room there is. Pure math, testable in isolation.
   *
   * @param columns the resulting number of columns
   * @param rows the resulting number of rows, visible or not
   * @param visible_rows the resulting number of rows shown without scrolling
   * @param tiles how many tiles there are
   * @param tile_width the width of a tile
   * @param tile_height the height of a tile
   * @param spacing the space between tiles
   * @param max_width the room for tiles across
   * @param max_height the room for tiles down
   */
  public static void compute_stack_grid (out int columns, out int rows, out int visible_rows,
                                         int tiles, int tile_width, int tile_height, int spacing,
                                         int max_width, int max_height) {
    tiles = int.max (1, tiles);

    var fitting_columns = (max_width + spacing) / int.max (1, tile_width + spacing);
    fitting_columns = fitting_columns.clamp (1, STACK_GRID_MAX_COLUMNS);

    rows = (tiles + fitting_columns - 1) / fitting_columns;
    columns = (tiles + rows - 1) / rows;

    var fitting_rows = (max_height + spacing) / int.max (1, tile_height + spacing);
    visible_rows = int.min (rows, fitting_rows.clamp (1, STACK_GRID_MAX_ROWS));
  }

  /**
   * The command lines to try, in order, to open a terminal: the desktop's
   * configured terminal first, then the launchers that pick the user's
   * preferred one, then the common terminals. Each is a program followed by
   * its arguments, and starts in the directory it is spawned in. Pure,
   * testable in isolation.
   *
   * @param configured the terminals configured for the desktop, most wanted first
   * @return the command lines
   */
  public static Gee.ArrayList<string> terminal_candidates (string[] configured) {
    var candidates = new Gee.ArrayList<string> ();

    foreach (unowned string exec in configured) {
      var stripped = exec.strip ();
      if (stripped != "" && !candidates.contains (stripped))
        candidates.add (stripped);
    }

    string[] known = {
      "xdg-terminal-exec", "x-terminal-emulator", "exo-open --launch TerminalEmulator",
      "gnome-terminal", "konsole", "xfce4-terminal", "mate-terminal", "qterminal", "lxterminal",
      "tilix", "terminator", "kitty", "alacritty", "xterm"
    };
    foreach (unowned string exec in known)
      if (!candidates.contains (exec))
        candidates.add (exec);

    return candidates;
  }

  // The terminals the running desktops are set to use
  static string[] configured_terminals () {
    string[] configured = {};

    string[] schemas = {
      "org.cinnamon.desktop.default-applications.terminal",
      "org.gnome.desktop.default-applications.terminal",
      "org.mate.applications-terminal"
    };

    unowned SettingsSchemaSource? source = SettingsSchemaSource.get_default ();
    if (source == null)
      return configured;

    foreach (unowned string id in schemas) {
      var schema = source.lookup (id, true);
      if (schema == null || !schema.has_key ("exec"))
        continue;

      var exec = new GLib.Settings.full (schema, null, null).get_string ("exec");
      if (exec != null && exec != "")
        configured += exec;
    }

    return configured;
  }

  /**
   * Opens a terminal in a directory, with the desktop's configured terminal
   * if there is one that is installed.
   *
   * @param directory the directory, which has to be a local one
   * @return whether a terminal was started
   */
  public static bool open_terminal (File directory) {
    var path = directory.get_path ();
    if (path == null) {
      warning ("Can't open a terminal in '%s', it isn't a local directory", directory.get_uri ());
      return false;
    }

    foreach (var candidate in terminal_candidates (configured_terminals ())) {
      string[] argv;
      try {
        Shell.parse_argv (candidate, out argv);
      } catch (ShellError e) {
        continue;
      }

      if (argv.length == 0 || Environment.find_program_in_path (argv[0]) == null)
        continue;

      try {
        Process.spawn_async (path, argv, null, SpawnFlags.SEARCH_PATH, null, null);
        return true;
      } catch (SpawnError e) {
        warning ("Could not start the terminal '%s': %s", candidate, e.message);
      }
    }

    warning ("No terminal found to open in '%s'", path);
    return false;
  }

  /**
   * Takes the pointer and the keyboard for a popup, as menus do, so a
   * click anywhere else, on the dock too, reaches the popup and closes it.
   *
   * @param popup the popup, which has to be showing
   */
  public static void grab_popup (Gtk.Window popup) {
    unowned Gdk.Seat seat = popup.get_display ().get_default_seat ();
    seat.grab (popup.get_window (), Gdk.SeatCapabilities.ALL, true, null, null, null);
    Gtk.grab_add (popup);
  }

  /**
   * Gives up what grab_popup () took.
   *
   * @param popup the popup
   */
  public static void ungrab_popup (Gtk.Window popup) {
    Gtk.grab_remove (popup);
    popup.get_display ().get_default_seat ().ungrab ();
  }

  /**
   * Whether a point of the screen is on a popup.
   *
   * @param popup the popup
   * @param x_root the x coordinate of the point
   * @param y_root the y coordinate of the point
   * @return whether the point is on the popup
   */
  public static bool point_on_popup (Gtk.Window popup, double x_root, double y_root) {
    int x, y;
    popup.get_window ().get_origin (out x, out y);

    return (x_root >= x && x_root < x + popup.get_allocated_width ()
            && y_root >= y && y_root < y + popup.get_allocated_height ());
  }
}

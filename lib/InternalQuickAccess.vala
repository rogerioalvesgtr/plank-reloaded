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
   * The most recent files an application's menu lists.
   */
  public const int RECENT_FILES_MAX = 10;

  /**
   * The most places a file manager's menu lists.
   */
  public const int PLACES_MAX = 20;

  /**
   * A place a file manager's menu lists: a folder the user bookmarked.
   */
  public class Place : GLib.Object {
    public string uri { get; construct; }
    public string label { get; construct; }

    public Place (string uri, string label) {
      GLib.Object (uri: uri, label: label);
    }
  }

  /**
   * The program a command line runs, by its name without folders, so the
   * command lines of a launcher and of a recent file's application can be
   * told to be the same application's. A leading "env" with its variables
   * is skipped, a command line quoted as a whole, as the recent files list
   * keeps them, is read as what it quotes, and a Flatpak or Snap command
   * line gives the application it runs rather than "flatpak" or "snap",
   * which every such application shares. Pure, testable in isolation.
   *
   * @param commandline the command line, as in a launcher's Exec key
   * @return the program's name, or null if there is none
   */
  public static string? exec_program (string commandline) {
    string[] argv;
    try {
      Shell.parse_argv (commandline, out argv);
    } catch (ShellError e) {
      return null;
    }

    // The recent files list quotes whole command lines, as 'gedit %u'
    if (argv.length == 1 && argv[0].contains (" %")) {
      try {
        Shell.parse_argv (argv[0], out argv);
      } catch (ShellError e) {
        return null;
      }
    }

    var i = 0;

    // "env VAR=value program"
    if (i < argv.length && Path.get_basename (argv[i]) == "env") {
      i++;
      while (i < argv.length && (argv[i].contains ("=") || argv[i].has_prefix ("-"))) {
        // Options that name a variable or a folder in the next argument
        if (argv[i] == "-u" || argv[i] == "--unset" || argv[i] == "-C" || argv[i] == "--chdir")
          i++;
        i++;
      }
    }

    if (i >= argv.length)
      return null;

    var program = Path.get_basename (argv[i]);

    // "flatpak run --branch=stable org.example.App", "snap run app"
    if (program == "flatpak" || program == "snap") {
      var run = false;
      for (var j = i + 1; j < argv.length; j++) {
        if (!run) {
          run = (argv[j] == "run");
          continue;
        }

        // Field codes come after the application
        if (!argv[j].has_prefix ("-") && !argv[j].has_prefix ("%") && !argv[j].has_prefix ("@"))
          return argv[j];
      }
    }

    return (program != "" ? program : null);
  }

  /**
   * The folders in a GTK bookmarks file, as file managers keep it: a line
   * for each with its URI and, after a space, the name the user gave it, if
   * any. Without one, the place is named by its folder. Empty lines, lines
   * without a URI and repeated folders are skipped, and no more than
   * PLACES_MAX are returned. Pure, testable in isolation.
   *
   * @param contents the file's contents
   * @return the places, in the file's order
   */
  public static Gee.ArrayList<Place> parse_bookmarks (string contents) {
    var places = new Gee.ArrayList<Place> ();
    var seen = new Gee.HashSet<string> ();

    foreach (unowned string line in contents.split ("\n")) {
      var stripped = line.strip ();
      if (stripped == "")
        continue;

      var parts = stripped.split (" ", 2);
      var uri = parts[0];
      if (!uri.contains ("://") || seen.contains (uri))
        continue;

      var label = (parts.length > 1 ? parts[1].strip () : "");
      if (label == "") {
        var path = Uri.unescape_string (uri) ?? uri;
        while (path.length > 1 && path.has_suffix ("/"))
          path = path.substring (0, path.length - 1);

        label = Path.get_basename (path);
        if (label == "" || label == "/" || label == ".")
          label = path;
      }

      seen.add (uri);
      places.add (new Place (uri, label));

      if (places.size >= PLACES_MAX)
        break;
    }

    return places;
  }
}

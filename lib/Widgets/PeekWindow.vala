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
   * Shows a picture of a window where the window is, above the other
   * windows, to peek at it while its preview is hovered. The window itself
   * stays where it is in the stack and nothing gets the focus, so hiding
   * the picture leaves everything as it was. The pointer passes through.
   */
  internal class PeekWindow : Gtk.Window {
    const double BORDER = 2.0;

    Cairo.Surface? picture = null;

    public PeekWindow () {
      GLib.Object (type: Gtk.WindowType.POPUP, type_hint: Gdk.WindowTypeHint.TOOLTIP);
    }

    construct
    {
      app_paintable = true;
      resizable = false;
      accept_focus = false;

      // Windows with shadows of their own have transparent edges
      unowned Gdk.Screen screen = get_screen ();
      set_visual (screen.get_rgba_visual () ?? screen.get_system_visual ());
    }

    /**
     * Shows a window's picture. All geometry is in logical pixels.
     *
     * @param pixbuf the window's picture, in device pixels
     * @param x the window's x position
     * @param y the window's y position
     * @param keep_clear an area the picture leaves alone, such as the dock's
     */
    public void show_picture (Gdk.Pixbuf pixbuf, int x, int y, Gdk.Rectangle keep_clear) {
      var scale = get_scale_factor ();
      var width = int.max (1, pixbuf.width / scale);
      var height = int.max (1, pixbuf.height / scale);

      picture = Gdk.cairo_surface_create_from_pixbuf (pixbuf, scale, null);

      set_size_request (width, height);
      resize (width, height);
      move (x, y);
      show ();

      unowned Gdk.Window window = get_window ();

      // Nothing of it takes the pointer
      window.input_shape_combine_region (new Cairo.Region (), 0, 0);

      var shape = new Cairo.Region.rectangle ({ 0, 0, width, height });
      shape.subtract_rectangle ({ keep_clear.x - x, keep_clear.y - y, keep_clear.width, keep_clear.height });
      window.shape_combine_region (shape, 0, 0);

      queue_draw ();
    }

    /**
     * Hides the picture and frees it.
     */
    public void clear () {
      hide ();
      picture = null;
    }

    /**
     * {@inheritDoc}
     */
    public override bool draw (Cairo.Context cr) {
      cr.save ();
      cr.set_operator (Cairo.Operator.SOURCE);
      cr.set_source_rgba (0, 0, 0, 0);
      cr.paint ();
      cr.restore ();

      if (picture == null)
        return Gdk.EVENT_STOP;

      cr.set_source_surface (picture, 0, 0);
      cr.paint ();

      // An outline tells the picture from the windows around it, on light
      // and dark ones alike
      var width = get_allocated_width ();
      var height = get_allocated_height ();
      cr.set_line_width (BORDER / 2);
      cr.set_source_rgba (0, 0, 0, 0.5);
      cr.rectangle (BORDER / 4, BORDER / 4, width - BORDER / 2, height - BORDER / 2);
      cr.stroke ();
      cr.set_source_rgba (1, 1, 1, 0.6);
      cr.rectangle (BORDER * 3 / 4, BORDER * 3 / 4, width - BORDER * 3 / 2, height - BORDER * 3 / 2);
      cr.stroke ();

      return Gdk.EVENT_STOP;
    }
  }
}

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
   * A popup that fans a folder's entries out of a dock item, in an arc
   * rising from a dock at the bottom of the screen.
   */
  internal class FanWindow : Gtk.Window {
    const int ICON_SIZE = 56;
    const int GAP = 12;
    const int LABEL_WIDTH = 280;
    const int PADDING = 16;
    const double CURVE = 1.5;
    const double TILT = 0.03;
    const int64 DURATION = 220 * 1000;

    /**
     * Emitted when an entry was chosen.
     */
    public signal void activated (StackEntry entry);

    Gee.ArrayList<StackEntry> entries = new Gee.ArrayList<StackEntry> ();
    Gee.ArrayList<Gdk.Pixbuf> pixbufs = new Gee.ArrayList<Gdk.Pixbuf> ();
    int hovered = -1;
    int fan_height = 0;
    double progress = 0.0;
    int64 start_time = 0;
    uint tick_id = 0U;

    public FanWindow () {
      GLib.Object (type: Gtk.WindowType.POPUP, type_hint: Gdk.WindowTypeHint.POPUP_MENU);
    }

    construct {
      app_paintable = true;
      resizable = false;

      unowned Gdk.Screen screen = get_screen ();
      set_visual (screen.get_rgba_visual () ?? screen.get_system_visual ());

      add_events (Gdk.EventMask.POINTER_MOTION_MASK
                  | Gdk.EventMask.BUTTON_PRESS_MASK
                  | Gdk.EventMask.BUTTON_RELEASE_MASK
                  | Gdk.EventMask.KEY_PRESS_MASK);
    }

    /**
     * Whether a fan of some entries has the room it needs: to the left of
     * the point it fans out of for its labels, and above it.
     *
     * @param count how many entries there are
     * @param x the x position to fan out of
     * @param y the y position to fan out of
     * @param area the dock's area, the monitor or its work area
     * @return whether the fan fits
     */
    public static bool fits (int count, int x, int y, Gdk.Rectangle area) {
      var max_dx = (int) (CURVE * (count - 1) * (count - 1));

      return (x - LABEL_WIDTH - ICON_SIZE / 2 >= area.x
              && x + ICON_SIZE / 2 + max_dx + ICON_SIZE <= area.x + area.width
              && y - (count * (ICON_SIZE + GAP) + 2 * PADDING + tilt_rise (count)) >= area.y);
    }

    // How far the last entry's label rises above its icon's row as it tilts
    static int tilt_rise (int count) {
      return (int) Math.ceil ((LABEL_WIDTH + ICON_SIZE / 2.0) * Math.sin (TILT * (count - 1)));
    }

    /**
     * Fans the entries out of a point.
     *
     * @param list the entries, the first one nearest to the dock
     * @param x the x position to fan out of, the dock item's center
     * @param y the y position to fan out of, the dock item's top
     */
    public void show_fan (Gee.List<StackEntry> list, int x, int y) {
      close_fan ();

      entries.clear ();
      pixbufs.clear ();
      foreach (var entry in list) {
        entries.add (entry);
        pixbufs.add (DrawingService.load_icon (entry.icon, ICON_SIZE, ICON_SIZE));
      }

      var n = entries.size;
      if (n == 0)
        return;

      var max_dx = (int) (CURVE * (n - 1) * (n - 1));
      var width = LABEL_WIDTH + ICON_SIZE + max_dx + ICON_SIZE;
      // The labels tilt with their entries, the last one's the most, which
      // lifts its far end
      fan_height = n * (ICON_SIZE + GAP) + 2 * PADDING + tilt_rise (n);

      set_size_request (width, fan_height);
      resize (width, fan_height);
      move (x - LABEL_WIDTH - ICON_SIZE / 2, y - fan_height);

      hovered = -1;
      progress = 0.0;
      show ();

      grab_popup (this);

      start_time = get_frame_clock ().get_frame_time ();
      tick_id = add_tick_callback ((widget, clock) => {
        var t = (double) (clock.get_frame_time () - start_time) / DURATION;
        t = t.clamp (0.0, 1.0);
        // ease out
        progress = 1.0 - Math.pow (1.0 - t, 3.0);
        queue_draw ();
        if (t >= 1.0) {
          tick_id = 0U;
          return false;
        }
        return true;
      });
    }

    /**
     * Closes the fan if it is showing.
     */
    public void close_fan () {
      if (tick_id > 0U) {
        remove_tick_callback (tick_id);
        tick_id = 0U;
      }

      if (!visible)
        return;

      ungrab_popup (this);
      hide ();
    }

    void get_entry_center (int i, out double cx, out double cy) {
      cx = LABEL_WIDTH + ICON_SIZE / 2.0 + CURVE * i * i * progress;
      cy = fan_height - PADDING - ICON_SIZE / 2.0 - i * (ICON_SIZE + GAP) * progress;
    }

    int get_entry_at (double x, double y) {
      for (var i = 0; i < entries.size; i++) {
        double cx, cy;
        get_entry_center (i, out cx, out cy);
        if (x >= cx - ICON_SIZE / 2.0 - LABEL_WIDTH && x <= cx + ICON_SIZE / 2.0
            && y >= cy - (ICON_SIZE + GAP) / 2.0 && y <= cy + (ICON_SIZE + GAP) / 2.0)
          return i;
      }

      return -1;
    }

    // With the pointer taken, events on the dock's window arrive here too,
    // so positions are taken from the screen rather than the event's window
    int get_entry_at_root (double x_root, double y_root) {
      int x, y;
      get_window ().get_origin (out x, out y);

      return get_entry_at (x_root - x, y_root - y);
    }

    public override bool motion_notify_event (Gdk.EventMotion event) {
      var entry = get_entry_at_root (event.x_root, event.y_root);
      if (entry != hovered) {
        hovered = entry;
        queue_draw ();
      }

      return true;
    }

    public override bool button_press_event (Gdk.EventButton event) {
      return true;
    }

    public override bool button_release_event (Gdk.EventButton event) {
      var entry = get_entry_at_root (event.x_root, event.y_root);
      close_fan ();
      if (entry >= 0)
        activated (entries[entry]);

      return true;
    }

    public override bool key_press_event (Gdk.EventKey event) {
      if (event.keyval == Gdk.Key.Escape)
        close_fan ();

      return true;
    }

    public override bool draw (Cairo.Context cr) {
      cr.save ();
      cr.set_operator (Cairo.Operator.CLEAR);
      cr.paint ();
      cr.restore ();

      for (var i = 0; i < entries.size; i++) {
        double cx, cy;
        get_entry_center (i, out cx, out cy);

        cr.save ();
        cr.translate (cx, cy);
        cr.rotate (TILT * i * progress);

        var pixbuf = pixbufs[i];
        Gdk.cairo_set_source_pixbuf (cr, pixbuf, -pixbuf.width / 2.0, -pixbuf.height / 2.0);
        cr.paint_with_alpha (progress);

        var layout = create_pango_layout (entries[i].text);
        var font = get_style_context ().get_font (Gtk.StateFlags.NORMAL);
        font.set_weight (Pango.Weight.SEMIBOLD);
        layout.set_font_description (font);
        layout.set_ellipsize (Pango.EllipsizeMode.MIDDLE);
        layout.set_width ((LABEL_WIDTH - 50) * Pango.SCALE);

        int text_width, text_height;
        layout.get_pixel_size (out text_width, out text_height);

        var pill_height = text_height + 10.0;
        var pill_width = text_width + 22.0;
        var pill_x = -ICON_SIZE / 2.0 - 12.0 - pill_width;
        var pill_y = -pill_height / 2.0;
        var radius = pill_height / 2.0;

        cr.new_sub_path ();
        cr.arc (pill_x + pill_width - radius, pill_y + radius, radius, -Math.PI_2, Math.PI_2);
        cr.arc (pill_x + radius, pill_y + radius, radius, Math.PI_2, 3.0 * Math.PI_2);
        cr.close_path ();
        if (i == hovered)
          cr.set_source_rgba (0.16, 0.47, 0.96, 0.92 * progress);
        else
          cr.set_source_rgba (0.0, 0.0, 0.0, 0.66 * progress);
        cr.fill ();

        cr.set_source_rgba (1.0, 1.0, 1.0, progress);
        cr.move_to (pill_x + 11.0, -text_height / 2.0);
        Pango.cairo_show_layout (cr, layout);

        cr.restore ();
      }

      return true;
    }
  }
}

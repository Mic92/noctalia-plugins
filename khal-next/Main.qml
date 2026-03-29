import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: root

  property var pluginApi: null

  // Expose service to bar widget / panel via mainInstance
  property alias calService: calService

  QtObject {
    id: calService

    // Flat, time-sorted list of {start, end, title, location, allDay}
    // start/end are JS Date objects; title/location strings.
    property var events: []
    // Next non-all-day event (or first all-day as fallback); null if none.
    property var nextEvent: null
    property string fetchState: "idle" // "idle", "loading", "success", "error"
    property string errorMessage: ""

    function refresh() {
      if (fetchProcess.running) return;
      var cfg = pluginApi?.pluginSettings || {};
      var defaults = pluginApi?.manifest?.metadata?.defaultSettings || {};
      var days = cfg.lookaheadDays ?? defaults.lookaheadDays;
      var extra = (cfg.khalArgs ?? defaults.khalArgs) || "";

      // khal emits one JSON array per day; merge with jq. --once so multi-day
      // / recurring instances don't double up, --notstarted so we only see
      // future events (currently-running ones are handled by the display timer,
      // not the poll).
      var cmd = "khal list now " + days + "d --once --notstarted --day-format '' " +
                "--json start --json end --json title --json location " +
                extra + " 2>/dev/null | jq -sc 'add // []'";

      fetchState = "loading";
      fetchProcess.command = ["sh", "-c", cmd];
      fetchProcess.running = true;
    }

    // Recompute nextEvent from events[] against current wall-clock.
    // Prefer timed events that haven't ended yet; fall back to today's
    // all-day entries if that's all there is.
    function recomputeNext() {
      var now = Date.now();
      var timed = null, allDay = null;
      for (var i = 0; i < events.length; i++) {
        var ev = events[i];
        if (ev.allDay) {
          if (!allDay && ev.end.getTime() > now) allDay = ev;
          continue;
        }
        if (ev.end.getTime() > now) {
          timed = ev;
          break; // events[] is pre-sorted
        }
      }
      nextEvent = timed || allDay;
    }
  }

  // khal's date format follows the user's locale config, but with the default
  // longdateformat it's "YYYY-MM-DD HH:MM" or "YYYY-MM-DD" for all-day.
  // JS Date() would treat "YYYY-MM-DD" as UTC midnight, so parse manually.
  function parseKhalDate(s) {
    var m = s.match(/^(\d{4})-(\d{2})-(\d{2})(?:\s+(\d{2}):(\d{2}))?$/);
    if (!m) return null;
    return new Date(
      parseInt(m[1], 10),
      parseInt(m[2], 10) - 1,
      parseInt(m[3], 10),
      m[4] ? parseInt(m[4], 10) : 0,
      m[5] ? parseInt(m[5], 10) : 0
    );
  }

  Process {
    id: fetchProcess
    stdout: StdioCollector {}
    stderr: StdioCollector {}

    onExited: function(exitCode) {
      if (exitCode !== 0) {
        calService.fetchState = "error";
        calService.errorMessage = stderr.text.trim() || ("khal exit " + exitCode);
        Logger.w("KhalNext", "khal failed:", exitCode, stderr.text);
        return;
      }

      var out = stdout.text.trim();
      if (!out) out = "[]";

      var parsed;
      try {
        parsed = JSON.parse(out);
      } catch (e) {
        calService.fetchState = "error";
        calService.errorMessage = "parse error: " + e;
        Logger.e("KhalNext", "JSON parse failed:", e, out.slice(0, 200));
        return;
      }

      var evs = [];
      for (var i = 0; i < parsed.length; i++) {
        var raw = parsed[i];
        var start = root.parseKhalDate(raw.start);
        var end = root.parseKhalDate(raw.end);
        if (!start || !end) continue;
        // All-day: no time component in the start string.
        var allDay = raw.start.length <= 10;
        evs.push({
          start: start,
          end: end,
          title: raw.title || "(untitled)",
          location: raw.location || "",
          allDay: allDay
        });
      }
      evs.sort(function(a, b) { return a.start.getTime() - b.start.getTime(); });

      calService.events = evs;
      calService.recomputeNext();
      calService.fetchState = "success";
      Logger.d("KhalNext", "loaded", evs.length, "events");
    }
  }

  // Data refresh — khal is cheap but not free, default 5 min is plenty given
  // vdirsyncer runs on a 15 min timer anyway.
  Timer {
    id: pollTimer
    repeat: true
    running: pluginApi !== null
    triggeredOnStart: true
    interval: {
      var cfg = pluginApi?.pluginSettings || {};
      var defaults = pluginApi?.manifest?.metadata?.defaultSettings || {};
      return (cfg.pollInterval ?? defaults.pollInterval) * 1000;
    }
    onTriggered: calService.refresh()
  }

  // Countdown tick — just re-derives nextEvent and prods the bar widget.
  // 30s is fine for "23m" granularity.
  Timer {
    repeat: true
    running: pluginApi !== null
    interval: 30000
    onTriggered: calService.recomputeNext()
  }

  IpcHandler {
    target: "plugin:khal-next"

    function refresh() {
      calService.refresh();
    }

    function toggle() {
      if (!pluginApi) return;
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.togglePanel(screen);
      });
    }

    // Join the next meeting from a keybind. Falls back to whatever
    // xdg-open makes of the location string — for Google Meet / Jitsi
    // URLs that's the browser, for anything else you get a best-effort.
    function join() {
      var ev = calService.nextEvent;
      if (!ev || !ev.location) {
        Logger.i("KhalNext", "join: no next event or no location");
        return;
      }
      Quickshell.execDetached(["xdg-open", ev.location]);
    }
  }
}

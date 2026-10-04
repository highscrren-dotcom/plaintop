// Line-builder stand for the text monitor: does MonitorData turn blocks and values into
// the lines it should?
//
// What it checks. MonitorData (monitor/shared/) is loaded as the plasmoid loads it, with
// the machine's sensors replaced: the registry's polling is stopped and its id list set by
// hand, values are pushed through publish() — the same path the individual sensors use —
// and the one-shot readings (nodes, model) are set as properties. Then the lines are read
// back for each block type: the fixes of 2026-10-04 (one node, no "/0°C"; the GPU block
// hiding without a card), thresholds, sparklines, the clock formats, swap, the separator
// and bar settings, the two columns, text and spacer, temperatures, load, network extras.
//
// How to run: ./install.sh --check-monitor, or by hand from the repo root
//   QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests/monitor.qml
// /usr/bin/qmltestrunner is the Qt 5 runner and cannot read a Qt 6 qmldir. The plasma
// modules MonitorData imports must be installed, as for the click-through stand.
//
// ⚠️ Written 2026-10-04 in a container without Qt: not yet run. The first run on a Plasma
// machine is the verification; a failure here is a question, not yet a bug in the widget.

import QtQuick
import QtTest
import "../monitor/shared"

Item {
    id: scene
    width: 800; height: 600

    MonitorData {
        id: monitor
        rate: 100000          // the stand ticks by hand
        liveSensors: false    // and feeds the values: the machine's own stay out
    }

    TestCase {
        name: "MonitorLines"
        when: windowShown

        function text(l) {
            if (!l || l.kind !== "parts") return ""
            let s = ""
            for (let i = 0; i < l.parts.length; i++) s += l.parts[i].text
            return s
        }
        function texts(lines) {
            const out = []
            for (let i = 0; i < lines.length; i++) out.push(text(lines[i]))
            return out
        }
        function find(lines, re) {
            for (let i = 0; i < lines.length; i++)
                if (re.test(text(lines[i]))) return lines[i]
            return null
        }
        function role(l) { return l ? l.parts[0].role : "" }

        // One machine for every test: two cores on one node, no GPU unless a test adds it.
        function initTestCase() {
            // The real machine's readings land asynchronously: let them, then override.
            wait(1500)
            monitor.registry.poll.running = false
            monitor.registry.ids = ["cpu/all/usage", "memory/physical/usedPercent"]
            monitor.coreCount = 2
        }

        function reset() {
            monitor.nodeCpus = [{ 0: true, 1: true }]
            monitor.cpuModel = "Test CPU"
            monitor.cpuSockets = 1
            monitor.cpuCores = 2
            monitor.cpuThreads = 4
            monitor.hist = ({})
            monitor.barWidth = 18
            monitor.barFill = "/"
            monitor.barEmpty = ""
            monitor.separatorChar = "-"
            monitor.separatorWidth = 35
            monitor.publish("cpu/all/usage", 42, true)
            monitor.publish("cpu/cpu0/usage", 40, true)
            monitor.publish("cpu/cpu1/usage", 44, true)
            monitor.publish("cpu/cpu0/temperature", 62, true)
            monitor.publish("cpu/cpu1/temperature", 58, true)
            monitor.publish("cpu/cpu0/frequency", 3400, true)
            monitor.publish("cpu/cpu1/frequency", 3600, true)
        }

        function show(blocks) {
            monitor.blocks = blocks
            monitor.tick++
            return monitor.lines
        }

        function test_01_one_node_prints_one_temperature_and_no_node_line() {
            reset()
            const lines = show([{ id: "cpu", type: "cpu", enabled: true,
                                  params: { per_socket: true, model_line: true, top_processes: 0, fans: [], frequency: true } }])
            const model = find(lines, /Test CPU/)
            verify(model !== null, "the model line is there: " + texts(lines))
            verify(/62°C/.test(text(model)), "the one node's temperature: " + text(model))
            verify(!/\/0°C/.test(text(model)), "no phantom second node: " + text(model))
            verify(/3[.,]5 GHz/.test(text(model)), "the average frequency: " + text(model))
            compare(find(lines, /^S0 /), null, "no per-node line for a single node")
        }

        function test_02_two_nodes_print_both() {
            reset()
            monitor.nodeCpus = [{ 0: true }, { 1: true }]
            const lines = show([{ id: "cpu", type: "cpu", enabled: true,
                                  params: { per_socket: true, model_line: true, top_processes: 0, fans: [] } }])
            verify(/62\/58°C/.test(text(find(lines, /Test CPU/))), "both nodes: " + texts(lines))
            verify(find(lines, /^S0 /) !== null && find(lines, /^S1 /) !== null, "a line per node")
        }

        function test_03_gpu_block_hides_without_a_card_and_counts_them() {
            reset()
            let lines = show([{ id: "gpu", type: "gpu", enabled: true, params: { details: true } }])
            compare(find(lines, /GPU/), null, "no card, no lines: " + texts(lines))
            monitor.registry.ids = ["gpu/gpu0/usage"]
            monitor.publish("gpu/gpu0/usage", 30, true)
            lines = show([{ id: "gpu", type: "gpu", enabled: true, params: { details: false } }])
            verify(find(lines, /^GPU /) !== null, "one card: " + texts(lines))
            monitor.registry.ids = ["gpu/gpu0/usage", "gpu/gpu1/usage"]
            monitor.publish("gpu/gpu1/usage", 70, true)
            lines = show([{ id: "gpu", type: "gpu", enabled: true, params: { details: false } }])
            verify(find(lines, /^GP0 /) !== null && find(lines, /^GP1 /) !== null, "two cards: " + texts(lines))
            monitor.registry.ids = ["cpu/all/usage", "memory/physical/usedPercent"]
        }

        function test_16_gpu_power_falls_back_to_power1() {
            reset()
            // amdgpu: "power" listed but never filled, the package power in "power1".
            monitor.registry.ids = ["gpu/gpu0/usage", "gpu/gpu0/power", "gpu/gpu0/power1"]
            monitor.publish("gpu/gpu0/usage", 30, true)
            monitor.publish("gpu/gpu0/power1", 19, true)
            let lines = show([{ id: "gpu", type: "gpu", enabled: true, params: { details: true } }])
            verify(monitor.gpuIds.indexOf("gpu/gpu0/power1") >= 0, "power1 is read: " + monitor.gpuIds)
            verify(find(lines, /pwr 19W$/) !== null, "the PPT figure: " + texts(lines))
            // A card that fills "power" keeps it.
            monitor.publish("gpu/gpu0/power", 42, true)
            lines = show([{ id: "gpu", type: "gpu", enabled: true, params: { details: true } }])
            verify(find(lines, /pwr 42W$/) !== null, "power wins when it has a value: " + texts(lines))
            monitor.registry.ids = ["cpu/all/usage", "memory/physical/usedPercent"]
        }

        function test_04_threshold_turns_the_line_accent() {
            reset()
            monitor.publish("cpu/all/usage", 95, true)
            let lines = show([{ id: "cpu", type: "cpu", enabled: true, params: { per_socket: false, model_line: false, top_processes: 0, warn: 90 } }])
            compare(role(find(lines, /^CPU /)), "accent", "95% past a 90% threshold")
            monitor.publish("cpu/all/usage", 50, true)
            lines = show([{ id: "cpu", type: "cpu", enabled: true, params: { per_socket: false, model_line: false, top_processes: 0, warn: 90 } }])
            compare(role(find(lines, /^CPU /)), "fg", "50% stays plain")
            monitor.publish("cpu/all/usage", 95, true)
            lines = show([{ id: "cpu", type: "cpu", enabled: true, params: { per_socket: false, model_line: false, top_processes: 0, warn: 0 } }])
            compare(role(find(lines, /^CPU /)), "fg", "0 means never")
        }

        function test_05_sparkline_follows_the_ticks() {
            reset()
            const blocks = [{ id: "cpu", type: "cpu", enabled: true, params: { per_socket: false, model_line: false, top_processes: 0, history: 4 } }]
            monitor.blocks = blocks
            for (const v of [0, 50, 100, 100]) {
                monitor.publish("cpu/all/usage", v, true)
                monitor.sample()
                monitor.tick++
            }
            const l = text(find(monitor.lines, /^CPU /))
            verify(/  ▁▄██$/.test(l), "four samples drawn after the bar: " + l)
        }

        function test_06_clock_formats() {
            reset()
            let lines = show([{ id: "clock", type: "clock", enabled: true, params: { seconds: true, format: "24h" } }])
            verify(/^\d\d:\d\d$/.test(lines[0].big), "24-hour: " + lines[0].big)
            verify(/^:\d\d$/.test(lines[0].small), "seconds: " + lines[0].small)
            lines = show([{ id: "clock", type: "clock", enabled: true, params: { seconds: false, format: "12h" } }])
            verify(/^\d{1,2}:\d\d$/.test(lines[0].big), "12-hour: " + lines[0].big)
            verify(/^ (AM|PM)$/.test(lines[0].small), "the marker in the small part: " + lines[0].small)
        }

        function test_07_swap_hides_without_swap() {
            reset()
            monitor.publish("memory/swap/total", 0, true)
            let lines = show([{ id: "swap", type: "swap", enabled: true, params: { totals: true } }])
            compare(lines.length, 0, "no swap, no lines")
            monitor.publish("memory/swap/total", 4 * 1073741824, true)
            monitor.publish("memory/swap/used", 1073741824, true)
            lines = show([{ id: "swap", type: "swap", enabled: true, params: { totals: true } }])
            verify(/^SWP .* 25%$/.test(text(lines[0])), "a quarter used: " + text(lines[0]))
            verify(/1[.,]0 GiB \/ 4[.,]0 GiB/.test(text(lines[1])), "the totals: " + text(lines[1]))
        }

        function test_08_separator_and_bar_settings() {
            reset()
            monitor.separatorChar = "="
            monitor.separatorWidth = 10
            monitor.barFill = "#"
            monitor.barEmpty = "."
            monitor.barWidth = 10
            monitor.publish("memory/physical/usedPercent", 50, true)
            const lines = show([{ id: "a", type: "memory", enabled: true, params: { totals: false, top_processes: 0 } },
                                { id: "s", type: "separator", enabled: true },
                                { id: "b", type: "memory", enabled: true, params: { totals: false, top_processes: 0 } }])
            compare(text(lines[0]), "RAM #####.....  50%")
            compare(text(lines[1]), "==========")
        }

        function test_09_two_columns() {
            reset()
            monitor.blocks = [{ id: "a", type: "text", enabled: true, params: { text: "left", role: "fg" } },
                              { id: "b", type: "text", enabled: true, column: 2, params: { text: "right", role: "dim" } }]
            monitor.tick++
            compare(monitor.twoColumns, true)
            compare(texts(monitor.lines), ["left"])
            compare(texts(monitor.lines2), ["right"])
            compare(role(monitor.lines2[0]), "dim")
        }

        function test_10_text_and_spacer() {
            reset()
            const lines = show([{ id: "t", type: "text", enabled: true, params: { text: "hello", role: "value" } },
                                { id: "sp", type: "spacer", enabled: true, params: { lines: 2 } },
                                { id: "t2", type: "text", enabled: true, params: { text: "", role: "fg" } }])
            compare(texts(lines), ["hello", " ", " "])
            compare(role(lines[0]), "value")
        }

        function test_11_temperatures_take_labels_or_the_sensors_names() {
            reset()
            monitor.publish("lmsensors/x/temp1", 45.4, true, "Tctl")
            monitor.publish("lmsensors/x/temp2", 91, true, "Tdie")
            const lines = show([{ id: "t", type: "temps", enabled: true,
                                  params: { sensors: ["VRM=lmsensors/x/temp1", "lmsensors/x/temp2", "lmsensors/x/none"], warn: 85 } }])
            compare(lines.length, 2, "the unknown sensor is skipped: " + texts(lines))
            verify(/^VRM +\| 45°C$/.test(text(lines[0])), "the label of the entry: " + text(lines[0]))
            verify(/^Tdie +\| 91°C$/.test(text(lines[1])), "the sensor's own name: " + text(lines[1]))
            compare(lines[1].parts[1].role, "accent", "91°C past 85")
        }

        function test_12_load_from_the_sensors() {
            reset()
            monitor.registry.ids = ["cpu/loadaverages/loadaverage1"]
            monitor.publish("cpu/loadaverages/loadaverage1", 2.5, true)
            monitor.publish("cpu/loadaverages/loadaverage5", 0.6, true)
            monitor.publish("cpu/loadaverages/loadaverage15", 0.7, true)
            let lines = show([{ id: "l", type: "load", enabled: true, params: { warn: 100 } }])
            verify(/^load 2[.,]50  0[.,]60  0[.,]70$/.test(text(lines[0])), "three averages: " + texts(lines))
            compare(role(lines[0]), "accent", "2.5 on two cores is past 100% of the cores")
            lines = show([{ id: "l", type: "load", enabled: true, params: { warn: 0 } }])
            compare(role(lines[0]), "dim")
            monitor.registry.ids = ["cpu/all/usage", "memory/physical/usedPercent"]
        }

        function test_13_network_extras_only_when_the_interface_reports_them() {
            reset()
            const iface = monitor.netIface
            monitor.publish("network/" + iface + "/download", 1024, true)
            monitor.publish("network/" + iface + "/upload", 0, true)
            monitor.publish("network/" + iface + "/ipv4address", "192.168.1.10", true)
            monitor.publish("network/" + iface + "/totalDownload", 2 * 1073741824, true)
            monitor.publish("network/" + iface + "/totalUpload", 5 * 1048576, true)
            const lines = show([{ id: "n", type: "network", enabled: true,
                                  params: { interface: "", address: true, totals: true, signal: true } }])
            compare(lines.length, 2, "the speed line and the extras: " + texts(lines))
            verify(/192\.168\.1\.10/.test(text(lines[1])), "the address: " + text(lines[1]))
            verify(/2[.,]0 GiB/.test(text(lines[1])) && /5 MiB/.test(text(lines[1])), "the totals: " + text(lines[1]))
            verify(!/signal/.test(text(lines[1])), "no signal sensor, no signal: " + text(lines[1]))
            monitor.publish("network/" + iface + "/signal", 78, true)
            const again = show([{ id: "n", type: "network", enabled: true,
                                  params: { interface: "", address: false, totals: false, signal: true } }])
            verify(/78%/.test(text(again[1])), "the signal once the sensor answers: " + texts(again))
        }

        function test_14_battery_below_the_threshold() {
            reset()
            monitor.registry.ids = ["power/b1/chargePercentage"]
            monitor.publish("power/b1/capacity", 50, true)
            monitor.publish("power/b1/chargePercentage", 10, true)
            monitor.publish("power/b1/chargeRate", -8, true)
            monitor.publish("power/b1/charge", 5, true)
            monitor.publish("power/b1/health", 90, true)
            let lines = show([{ id: "b", type: "battery", enabled: true, params: { warn_low: 15 } }])
            compare(role(find(lines, /^BAT /)), "accent", "10% below 15: " + texts(lines))
            lines = show([{ id: "b", type: "battery", enabled: true, params: { warn_low: 5 } }])
            compare(role(find(lines, /^BAT /)), "fg")
            monitor.registry.ids = ["cpu/all/usage", "memory/physical/usedPercent"]
        }

        function test_15_separators_collapse_around_hidden_blocks() {
            reset()
            monitor.publish("memory/swap/total", 0, true)
            const lines = show([{ id: "s1", type: "separator", enabled: true },
                                { id: "sw", type: "swap", enabled: true, params: { totals: true } },
                                { id: "s2", type: "separator", enabled: true },
                                { id: "t", type: "text", enabled: true, params: { text: "x", role: "fg" } },
                                { id: "s3", type: "separator", enabled: true }])
            compare(texts(lines), ["x"], "no leading, doubled or trailing rule")
        }

        // --- Active lines, 17 and up: the action a line carries comes from its block.
        // Written 2026-10-04 without Qt, like the rest of this file was.
        function test_17_lines_carry_actions_from_their_block() {
            reset()
            monitor.actions = true
            const lines = show([{ id: "head", type: "header", enabled: true, params: { text: "stand", hostname: false } },
                                { id: "cpu", type: "cpu", enabled: true,
                                  params: { per_socket: false, model_line: false, top_processes: 0 } }])
            compare(lines.length, 2, texts(lines))
            verify(lines[0].action !== undefined, "the header has an action: " + JSON.stringify(lines[0]))
            compare(lines[0].action.items[0].configure, true, "…which opens the settings")
            compare(lines[1].action.title, "CPU")
            compare(lines[1].action.items.length, 1)
            verify(/systemmonitor/.test(lines[1].action.items[0].run), "the bar opens System Monitor: " + lines[1].action.items[0].run)
            compare(lines[1].action.items[0].gui, true, "…detached, as a GUI program")
            compare(lines[1].action.items[0].confirm, false)
        }

        function test_18_actions_off_globally_or_per_block() {
            reset()
            const cpu = { id: "cpu", type: "cpu", enabled: true, params: { per_socket: false, model_line: false, top_processes: 0 } }
            monitor.actions = false
            let lines = show([cpu])
            verify(lines[0].action === undefined, "switched off: no action")
            monitor.actions = true
            lines = show([{ id: "cpu", type: "cpu", enabled: true, active: false, params: cpu.params }])
            verify(lines[0].action === undefined, "the block opted out: no action")
            lines = show([{ id: "t", type: "text", enabled: true, params: { text: "note", role: "fg" } }])
            verify(lines[0].action === undefined, "a text line has nothing to do by itself")
            lines = show([{ id: "t", type: "text", enabled: true, click: "notify-send {name}", params: { text: "note", role: "fg" } }])
            verify(lines[0].action !== undefined, "…unless the block names a command")
            compare(lines[0].action.items.length, 1)
        }

        function test_19_the_blocks_own_click_goes_first_with_the_row_filled_in() {
            reset()
            monitor.cmdOut = { u: "nginx.service|active\nsshd.service|failed" }
            const lines = show([{ id: "u", type: "units", enabled: true, click: "systemctl status {unit} # {value}",
                                  params: { units: ["nginx.service", "sshd.service"], user: false } }])
            compare(lines.length, 2, texts(lines))
            const a = lines[1].action
            compare(a.title, "sshd.service")
            compare(a.items.length, 6, "the custom one and five built in")
            compare(a.items[0].run, "systemctl status sshd.service # failed", "the custom command, filled in, first")
            compare(a.items[1].run, "systemctl status 'sshd.service'", "then the built-in status")
            compare(a.items[1].terminal, true)
            compare(a.items[1].confirm, false, "status runs without a question")
            compare(a.items[2].confirm, true, "start asks first")
            compare(a.items[4].run, "systemctl restart 'sshd.service'")
            verify(/^journalctl -e -u 'sshd.service'$/.test(a.items[5].run), "the journal: " + a.items[5].run)
            const user = show([{ id: "u", type: "units", enabled: true, params: { units: ["nginx.service", "sshd.service"], user: true } }])
            compare(user[0].action.items[0].run, "systemctl --user status 'nginx.service'", "the user manager")
            compare(user[0].action.items[4].run, "journalctl --user -e -u 'nginx.service'")
        }

        function test_20_disks_repos_and_the_power_menu() {
            reset()
            monitor.diskRows = [{ target: "/home", size: 100 * 1073741824, used: 50 * 1073741824, pct: 50 }]
            let lines = show([{ id: "d", type: "disks", enabled: true, params: { mounts: ["/home"], nvme_temp: false } }])
            compare(lines.length, 2, texts(lines))
            compare(lines[0].action.title, "/home")
            compare(lines[0].action.items[0].run, "xdg-open '/home'", "the first item opens the folder")
            compare(lines[0].action.items[0].gui, true)
            compare(lines[1].action.title, "/home", "the free/total line shares the action")
            // Repositories: the path comes from the parameter, the script printed only its name.
            monitor.cmdOut = { r: "plaintop|main|2|1|0\nother|notgit" }
            lines = show([{ id: "r", type: "repos", enabled: true, params: { paths: ["~/dev/plaintop", "/tmp/other"] } }])
            compare(lines.length, 2, texts(lines))
            compare(lines[0].action.items[0].run, "cd \"$HOME\"'/dev/plaintop' && exec \"${SHELL:-sh}\"", "a terminal at the path, ~ left to the shell")
            compare(lines[0].action.items[0].terminal, true)
            compare(lines[0].action.items[2].editor, true, "the editor item carries the path alone")
            compare(lines[0].action.items[2].run, "\"$HOME\"'/dev/plaintop'")
            compare(lines[1].action.items.length, 2, "not a repository: open and a terminal, no git")
            // The power menu: every step but the lock asks first.
            lines = show([{ id: "up", type: "uptime", enabled: true }])
            const p = lines[0].action.items
            compare(p.length, 4)
            compare(p[0].run, "loginctl lock-session"); compare(p[0].confirm, false)
            compare(p[2].run, "systemctl reboot"); compare(p[2].confirm, true)
            compare(p[3].run, "systemctl poweroff"); compare(p[3].confirm, true)
            // The quoting helpers.
            compare(monitor.sh("it's"), "'it'\\''s'")
            compare(monitor.pathArg("~/dev/a b"), "\"$HOME\"'/dev/a b'")
            compare(monitor.pathArg("/plain"), "'/plain'")
            compare(monitor.fill("kill {pid} {x}", { pid: 42 }), "kill 42 {x}", "unknown placeholders stay")
        }

        function test_21_sound_toggles_mute_health_reboots_after_a_question() {
            reset()
            monitor.cmdOut = { snd: "sink|Speakers|45|1" }
            let lines = show([{ id: "snd", type: "sound", enabled: true, params: { input: false, device: true } }])
            compare(lines.length, 2, texts(lines))
            compare(lines[0].action.items[0].run, "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", "the first item toggles the mute")
            compare(lines[0].action.items[0].confirm, false)
            compare(lines[1].action.title, "Speakers", "the device line shares it")
            monitor.cmdOut = { snd: "source|Mic|80|0" }
            lines = show([{ id: "snd", type: "sound", enabled: true, params: { input: true, device: false } }])
            compare(lines[0].action.items[0].run, "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle")
            monitor.healthData = { failed: ["0", "0"], err: ["3", "1"], lines: [{ ident: "kwin_wayland", text: "oops" }], reboot: true }
            lines = show([{ id: "h", type: "health", enabled: true, params: { units: true, errors: true, lines: 3, reboot: true } }])
            compare(lines.length, 4, texts(lines))
            compare(lines[0].action.items[0].run, "systemctl --failed; systemctl --user --failed")
            compare(lines[0].action.items[0].hold, true, "a listing is held open")
            compare(lines[1].action.items[0].run, "journalctl -p err -b -e")
            compare(lines[2].action.items[0].run, "systemctl reboot"); compare(lines[2].action.items[0].confirm, true)
            compare(lines[3].action.items[0].run, "journalctl -b -e -t 'kwin_wayland'", "the error line opens its program's journal")
        }
    }
}

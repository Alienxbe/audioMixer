import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Common
import qs.Services
import qs.Widgets
import qs.DCommon.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    // ---------- Settings (see AudioMixerSettings.qml) ----------
    readonly property bool showPercent: pluginData.showPercent ?? true
    readonly property bool showMicIcon: pluginData.showMicIcon ?? true
    readonly property int scrollStep: parseInt(pluginData.scrollStep ?? "5") || 5
    readonly property int maxVolume: parseInt(pluginData.maxVolume ?? "150") || 150
    readonly property bool showMonitors: pluginData.showMonitors ?? false
    readonly property bool showMeters: pluginData.showMeters ?? true
    readonly property bool autoSwitchMic: pluginData.autoSwitchMic ?? true
    readonly property bool notifyOnPlug: pluginData.notifyOnPlug ?? true

    // ---------- State (filled from pactl) ----------
    // Objects are kept in maps; Repeaters only see key lists, which are replaced
    // only when items appear/disappear. Value changes update rows in place.
    property var sinkMap: ({})
    property var sourceMap: ({})
    property var sinkInputMap: ({})
    property var sourceOutputMap: ({})
    property var cardMap: ({})
    property var sinkKeys: []
    property var sourceKeys: []
    property var sinkInputKeys: []
    property var sourceOutputKeys: []
    property var cardKeys: []
    property string defaultSink: ""
    property string defaultSource: ""
    property int currentTab: 0

    property var prevPortAvail: null   // { sourceName: { portName: availability } }

    readonly property var defaultSinkObj: sinkMap[defaultSink] || null
    readonly property var defaultSourceObj: sourceMap[defaultSource] || null

    popoutWidth: 500
    popoutHeight: 600

    // ---------- Helpers ----------
    function volPercent(vol) {
        if (!vol)
            return 0;
        let m = 0;
        for (const ch in vol)
            m = Math.max(m, vol[ch].value || 0);
        return Math.round(m / 65536 * 100);
    }

    function run(args) {
        Quickshell.execDetached(["pactl"].concat(args));
        refreshTimer.restart();
    }

    function isMonitor(s) {
        return !!s.monitor_source || (s.name || "").endsWith(".monitor");
    }

    function volumeIcon(obj) {
        if (!obj || obj.mute)
            return "volume_off";
        const v = volPercent(obj.volume);
        return v === 0 ? "volume_mute" : v < 50 ? "volume_down" : "volume_up";
    }

    function desktopEntryFor(s) {
        const p = s.properties || {};
        const cands = [p["application.process.binary"], p["application.id"], p["application.name"]];
        for (const c of cands) {
            if (!c)
                continue;
            try {
                const e = DesktopEntries.heuristicLookup(c);
                if (e)
                    return e;
            } catch (err) {}
        }
        return null;
    }

    function streamTitle(s) {
        const p = s.properties || {};
        const e = desktopEntryFor(s);
        return (e && e.name) || p["application.name"] || p["application.process.binary"] || p["node.name"] || "Unknown";
    }

    function streamSubtitle(s) {
        const p = s.properties || {};
        const m = p["media.name"] || "";
        return m === streamTitle(s) ? "" : m;
    }

    function streamIconPath(s) {
        const p = s.properties || {};
        const e = desktopEntryFor(s);
        const cands = [p["application.icon_name"], e ? e.icon : "", (p["application.process.binary"] || "").toLowerCase(), (p["application.name"] || "").toLowerCase()];
        for (const c of cands) {
            if (!c)
                continue;
            if (c.startsWith("/"))
                return "file://" + c;
            const path = Quickshell.iconPath(c, true);
            if (path)
                return path;
        }
        return "";
    }

    function cardName(c) {
        const p = c.properties || {};
        return p["device.description"] || p["alsa.card_name"] || c.name;
    }

    function portLabel(p) {
        return p.description + (p.availability === "not available" ? " (unplugged)" : "");
    }

    function sameKeys(a, b) {
        return a.length === b.length && a.every((k, i) => k === b[i]);
    }

    function toMap(list, keyFn) {
        const m = {};
        for (const o of list)
            m[keyFn(o)] = o;
        return m;
    }

    function applyData(d) {
        const sourceOutputs = d.sourceOutputs.filter(o => {
            const p = o.properties || {};
            return p["media.name"] !== "Peak detect" && p["application.id"] !== "org.PulseAudio.pavucontrol" && !(p["node.name"] || "").startsWith("quickshell");
        });
        const visibleSources = d.sources.filter(s => root.showMonitors || !root.isMonitor(s));

        // Maps first (rows bind to them), then keys (only if membership changed)
        sinkMap = toMap(d.sinks, o => o.name);
        sourceMap = toMap(d.sources, o => o.name);
        sinkInputMap = toMap(d.sinkInputs, o => String(o.index));
        sourceOutputMap = toMap(sourceOutputs, o => String(o.index));
        cardMap = toMap(d.cards, o => o.name);

        const nk = {
            "sinkKeys": d.sinks.map(o => o.name),
            "sourceKeys": visibleSources.map(o => o.name),
            "sinkInputKeys": d.sinkInputs.map(o => String(o.index)),
            "sourceOutputKeys": sourceOutputs.map(o => String(o.index)),
            "cardKeys": d.cards.map(o => o.name)
        };
        for (const k in nk)
            if (!sameKeys(root[k], nk[k]))
                root[k] = nk[k];

        defaultSink = d.info.default_sink_name || "";
        defaultSource = d.info.default_source_name || "";

        handleJacks(d.sources);
    }

    // ---------- Jack plug/unplug handling (feature 6) ----------
    function handleJacks(sources) {
        const snap = {};
        for (const s of sources) {
            if (isMonitor(s))
                continue;
            snap[s.name] = {};
            for (const p of (s.ports || []))
                snap[s.name][p.name] = p.availability;
        }
        const prev = prevPortAvail;
        prevPortAvail = snap;
        if (!prev)
            return;

        for (const s of sources) {
            if (isMonitor(s) || !prev[s.name])
                continue;
            const ports = s.ports || [];
            const plugged = ports.filter(p => prev[s.name][p.name] === "not available" && p.availability !== "not available");
            const unplugged = ports.filter(p => prev[s.name][p.name] !== undefined && prev[s.name][p.name] !== "not available" && p.availability === "not available");

            if (plugged.length > 0) {
                const target = plugged.find(p => p.type === "Headset") || plugged[0];
                if (autoSwitchMic && s.active_port !== target.name) {
                    run(["set-source-port", s.name, target.name]);
                    run(["set-default-source", s.name]);
                }
                if (notifyOnPlug)
                    ToastService.showInfo(autoSwitchMic ? "Headset plugged in — using " + target.description : "Headset plugged in", autoSwitchMic ? "" : "Open the Audio Mixer → Input to switch to " + target.description);
            } else if (unplugged.length > 0) {
                let fallback = null;
                if (unplugged.some(p => p.name === s.active_port)) {
                    fallback = ports.filter(p => p.availability !== "not available").sort((a, b) => b.priority - a.priority)[0] || null;
                    if (fallback && autoSwitchMic)
                        run(["set-source-port", s.name, fallback.name]);
                }
                if (notifyOnPlug)
                    ToastService.showInfo("Headset unplugged" + (fallback && autoSwitchMic ? " — using " + fallback.description : ""));
            }
        }
    }

    // ---------- Data loading ----------
    Timer {
        id: refreshTimer
        interval: 120
        onTriggered: {
            if (!dumpProc.running)
                dumpProc.running = true;
            else
                restart();
        }
    }

    Process {
        id: dumpProc
        command: ["bash", "-c", "j(){ pactl -f json \"$@\" 2>/dev/null || echo '[]'; }; " + "printf '{\"sinks\":%s,\"sources\":%s,\"sinkInputs\":%s,\"sourceOutputs\":%s,\"cards\":%s,\"info\":%s}' " + "\"$(j list sinks)\" \"$(j list sources)\" \"$(j list sink-inputs)\" \"$(j list source-outputs)\" \"$(j list cards)\" " + "\"$(pactl -f json info 2>/dev/null || echo '{}')\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.applyData(JSON.parse(text));
                } catch (e) {
                    console.warn("audioMixer: failed to parse pactl output:", e);
                }
            }
        }
    }

    // Live updates: any PulseAudio/PipeWire event triggers a (debounced) refresh
    Process {
        id: subscribeProc
        running: true
        command: ["pactl", "subscribe"]
        stdout: SplitParser {
            onRead: data => refreshTimer.restart()
        }
        onExited: restartSub.start()
    }

    Timer {
        id: restartSub
        interval: 2000
        onTriggered: subscribeProc.running = true
    }

    onShowMonitorsChanged: refreshTimer.restart()
    Component.onCompleted: refreshTimer.start()

    // ---------- Bar pill ----------
    pillRightClickAction: () => {
        if (root.defaultSource)
            root.run(["set-source-mute", "@DEFAULT_SOURCE@", "toggle"]);
    }

    component WheelVolume: MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton
        onClicked: root.run(["set-sink-mute", "@DEFAULT_SINK@", "toggle"])
        onWheel: wheel => {
            const step = wheel.angleDelta.y > 0 ? root.scrollStep : -root.scrollStep;
            const cur = root.volPercent(root.defaultSinkObj ? root.defaultSinkObj.volume : null);
            const next = Math.max(0, Math.min(Math.min(100, root.maxVolume), cur + step));
            root.run(["set-sink-volume", "@DEFAULT_SINK@", next + "%"]);
        }
    }

    horizontalBarPill: Component {
        Item {
            implicitWidth: pillBox.implicitWidth
            implicitHeight: pillBox.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Row {
                id: pillBox
                spacing: Theme.spacingXS

                DIcon {
                    name: root.volumeIcon(root.defaultSinkObj)
                    color: Theme.primary
                    size: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    visible: root.showPercent
                    text: root.volPercent(root.defaultSinkObj ? root.defaultSinkObj.volume : null) + "%"
                    color: Theme.surfaceText
                    font.pixelSize: root.textSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                DIcon {
                    visible: root.showMicIcon
                    name: root.defaultSourceObj && root.defaultSourceObj.mute ? "mic_off" : "mic"
                    color: root.defaultSourceObj && root.defaultSourceObj.mute ? Theme.error : Theme.primary
                    size: root.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            WheelVolume {}
        }
    }

    verticalBarPill: Component {
        Item {
            implicitWidth: pillBoxV.implicitWidth
            implicitHeight: pillBoxV.implicitHeight
            width: implicitWidth
            height: implicitHeight

            Column {
                id: pillBoxV
                spacing: Theme.spacingXS

                DIcon {
                    name: root.volumeIcon(root.defaultSinkObj)
                    color: Theme.primary
                    size: root.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    visible: root.showPercent
                    text: root.volPercent(root.defaultSinkObj ? root.defaultSinkObj.volume : null)
                    color: Theme.surfaceText
                    font.pixelSize: root.textSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                DIcon {
                    visible: root.showMicIcon
                    name: root.defaultSourceObj && root.defaultSourceObj.mute ? "mic_off" : "mic"
                    color: root.defaultSourceObj && root.defaultSourceObj.mute ? Theme.error : Theme.primary
                    size: root.iconSize
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
            WheelVolume {}
        }
    }

    // ---------- Reusable pieces ----------

    // Slider that follows external changes without fighting the user while dragging
    component VolumeSlider: DSlider {
        id: vs
        property var target: null
        property var setArgs: []   // e.g. ["set-sink-volume", name]
        readonly property int extValue: root.volPercent(target ? target.volume : null)
        width: parent.width
        minimum: 0
        maximum: Math.max(root.maxVolume, extValue)
        unit: "%"
        showValue: true
        Component.onCompleted: value = extValue
        onExtValueChanged: if (!isDragging)
            value = extValue
        onIsDraggingChanged: if (!isDragging)
            value = extValue
        onSliderValueChanged: newValue => root.run(setArgs.concat([newValue + "%"]))
    }

    // Dropdown that follows external changes (selection breaks a plain binding)
    component SyncDropdown: DDropdown {
        property string extValue: ""
        width: parent.width
        dropdownWidth: parent.width
        popupWidth: parent.width
        Component.onCompleted: currentValue = extValue
        onExtValueChanged: currentValue = extValue
    }

    // Live peak meter for a PipeWire node (feature 3)
    component LevelMeter: Item {
        id: lm
        property int objectId: -1
        readonly property var node: objectId < 0 ? null : (Pipewire.nodes.values.find(n => n.id === objectId) || null)
        readonly property bool active: root.showMeters && node !== null && (lm.Window.window ? lm.Window.window.visible : false)
        // Linear peak (like pavucontrol): quiet noise stays low, only loud signals reach the end
        readonly property real level: {
            const p = peakMon.peak;
            if (!active || !(p > 0))
                return 0;
            return Math.max(0, Math.min(1, p));
        }
        visible: root.showMeters && node !== null
        width: parent.width
        height: 4

        PwObjectTracker {
            objects: lm.active && lm.node ? [lm.node] : []
        }

        PwNodePeakMonitor {
            id: peakMon
            node: lm.node
            enabled: lm.active
        }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: Theme.withAlpha(Theme.onSurfaceVariant, 0.15)
        }

        Rectangle {
            height: parent.height
            radius: height / 2
            width: parent.width * lm.level
            color: lm.level > 0.95 ? Theme.error : lm.level > 0.8 ? Theme.warning : Theme.primary
            Behavior on width {
                NumberAnimation {
                    duration: 60
                }
            }
        }
    }

    component Card: StyledRect {
        width: parent.width
        radius: Theme.cornerRadius
        color: Theme.chipSurface
    }

    component EmptyNote: StyledText {
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        color: Theme.onSurfaceVariant
        font.pixelSize: Theme.fontSizeMedium
        topPadding: Theme.spacingXL
    }

    // A sink or source
    component DeviceRow: Card {
        id: dr
        property string key
        property bool isSink: true
        readonly property var dev: (isSink ? root.sinkMap[key] : root.sourceMap[key]) || ({})
        readonly property bool isDefault: key === (isSink ? root.defaultSink : root.defaultSource)
        readonly property var ports: dev.ports || []
        height: drCol.implicitHeight + Theme.spacingM * 2

        Column {
            id: drCol
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            Item {
                width: parent.width
                height: Math.max(drTitle.implicitHeight, drDefault.height)

                DIcon {
                    id: drIcon
                    name: dr.isSink ? "speaker" : (root.isMonitor(dr.dev) ? "settings_voice" : "mic")
                    color: dr.isDefault ? Theme.primary : Theme.onSurfaceVariant
                    size: Theme.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    id: drTitle
                    anchors.left: drIcon.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: drDefault.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: dr.dev.description || dr.key
                    elide: Text.ElideRight
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: dr.isDefault ? Font.Bold : Font.Normal
                }

                DActionButton {
                    id: drDefault
                    anchors.right: drMute.left
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: dr.isDefault ? "check_circle" : "radio_button_unchecked"
                    iconFilled: dr.isDefault
                    iconColor: dr.isDefault ? Theme.primary : Theme.onSurfaceVariant
                    tooltipText: dr.isDefault ? "Default device" : "Set as default"
                    onClicked: root.run([dr.isSink ? "set-default-sink" : "set-default-source", dr.key])
                }

                DActionButton {
                    id: drMute
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: dr.isSink ? (dr.dev.mute ? "volume_off" : "volume_up") : (dr.dev.mute ? "mic_off" : "mic")
                    iconColor: dr.dev.mute ? Theme.error : Theme.onSurfaceVariant
                    tooltipText: dr.dev.mute ? "Unmute" : "Mute"
                    onClicked: root.run([dr.isSink ? "set-sink-mute" : "set-source-mute", dr.key, "toggle"])
                }
            }

            SyncDropdown {
                visible: dr.ports.length > 1
                options: dr.ports.map(p => root.portLabel(p))
                optionValues: dr.ports.map(p => p.name)
                extValue: dr.dev.active_port || ""
                onValueChanged: value => root.run([dr.isSink ? "set-sink-port" : "set-source-port", dr.key, value])
            }

            VolumeSlider {
                target: dr.dev
                setArgs: [dr.isSink ? "set-sink-volume" : "set-source-volume", dr.key]
            }

            LevelMeter {
                objectId: dr.dev.properties ? parseInt(dr.dev.properties["object.id"] ?? "-1") : -1
            }
        }
    }

    // A playback (sink-input) or recording (source-output) stream
    component StreamRow: Card {
        id: sr
        property string key
        property bool isPlayback: true
        readonly property var stream: (isPlayback ? root.sinkInputMap[key] : root.sourceOutputMap[key]) || ({})
        readonly property string iconPath: root.streamIconPath(stream)
        height: srCol.implicitHeight + Theme.spacingM * 2

        Column {
            id: srCol
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            Item {
                width: parent.width
                height: Math.max(srText.implicitHeight, srMute.height, srIconBox.height)

                Item {
                    id: srIconBox
                    width: Theme.iconSizeLarge
                    height: Theme.iconSizeLarge
                    anchors.verticalCenter: parent.verticalCenter

                    Image {
                        id: srImg
                        anchors.fill: parent
                        source: sr.iconPath
                        sourceSize.width: width * 2
                        sourceSize.height: height * 2
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        asynchronous: true
                        visible: status === Image.Ready
                    }

                    DIcon {
                        anchors.centerIn: parent
                        visible: !srImg.visible
                        name: sr.isPlayback ? "music_note" : "graphic_eq"
                        color: Theme.primary
                        size: Theme.iconSize
                    }
                }

                Column {
                    id: srText
                    anchors.left: srIconBox.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: srMute.left
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        width: parent.width
                        text: root.streamTitle(sr.stream)
                        elide: Text.ElideRight
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                    }
                    StyledText {
                        width: parent.width
                        visible: text !== ""
                        text: root.streamSubtitle(sr.stream)
                        elide: Text.ElideRight
                        color: Theme.onSurfaceVariant
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }

                DActionButton {
                    id: srMute
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: sr.stream.mute ? "volume_off" : "volume_up"
                    iconColor: sr.stream.mute ? Theme.error : Theme.onSurfaceVariant
                    tooltipText: sr.stream.mute ? "Unmute" : "Mute"
                    onClicked: root.run([sr.isPlayback ? "set-sink-input-mute" : "set-source-output-mute", sr.key, "toggle"])
                }
            }

            SyncDropdown {
                readonly property var devKeys: sr.isPlayback ? root.sinkKeys : root.sourceKeys
                readonly property var devMap: sr.isPlayback ? root.sinkMap : root.sourceMap
                options: devKeys.map(k => (sr.isPlayback ? "Play on: " : "Record from: ") + ((devMap[k] || {}).description || k))
                optionValues: devKeys.map(k => String((devMap[k] || {}).index))
                extValue: String(sr.isPlayback ? sr.stream.sink : sr.stream.source)
                onValueChanged: value => root.run([sr.isPlayback ? "move-sink-input" : "move-source-output", sr.key, value])
            }

            VolumeSlider {
                target: sr.stream
                setArgs: [sr.isPlayback ? "set-sink-input-volume" : "set-source-output-volume", sr.key]
            }

            LevelMeter {
                objectId: sr.stream.properties ? parseInt(sr.stream.properties["object.id"] ?? "-1") : -1
            }
        }
    }

    component CardProfileRow: Card {
        id: cr
        property string key
        readonly property var card: root.cardMap[key] || ({})
        height: crCol.implicitHeight + Theme.spacingM * 2

        Column {
            id: crCol
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            Row {
                spacing: Theme.spacingS
                DIcon {
                    name: "settings_input_component"
                    color: Theme.primary
                    size: Theme.iconSize
                    anchors.verticalCenter: parent.verticalCenter
                }
                StyledText {
                    text: root.cardName(cr.card)
                    color: Theme.surfaceText
                    font.pixelSize: Theme.fontSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            SyncDropdown {
                readonly property var profs: Object.keys(cr.card.profiles || {}).map(k => ({
                            "key": k,
                            "p": cr.card.profiles[k]
                        })).sort((a, b) => b.p.priority - a.p.priority)
                options: profs.map(x => x.p.description + (x.p.available ? "" : " (unavailable)"))
                optionValues: profs.map(x => x.key)
                extValue: cr.card.active_profile || ""
                onValueChanged: value => root.run(["set-card-profile", cr.key, value])
            }
        }
    }

    // ---------- Popout ----------
    popoutContent: Component {
        PopoutComponent {
            id: pop
            headerText: "Audio Mixer"

            Component.onCompleted: refreshTimer.restart()

            Column {
                width: parent.width
                spacing: Theme.spacingM

                DTabBar {
                    id: tabs
                    width: parent.width
                    currentIndex: root.currentTab
                    model: [
                        {
                            "text": "Playback"
                        },
                        {
                            "text": "Recording"
                        },
                        {
                            "text": "Output"
                        },
                        {
                            "text": "Input"
                        },
                        {
                            "text": "Config"
                        }
                    ]
                    showIcons: false
                    onTabClicked: index => root.currentTab = index
                }

                DFlickable {
                    width: parent.width
                    height: root.popoutHeight - pop.headerHeight - pop.detailsHeight - tabs.height - Theme.spacingXL * 3
                    contentHeight: list.height
                    clip: true

                    Column {
                        id: list
                        width: parent.width
                        spacing: Theme.spacingS

                        // Playback
                        Repeater {
                            model: root.currentTab === 0 ? root.sinkInputKeys : []
                            StreamRow {
                                required property string modelData
                                key: modelData
                                isPlayback: true
                            }
                        }
                        EmptyNote {
                            visible: root.currentTab === 0 && root.sinkInputKeys.length === 0
                            text: "No application is playing audio"
                        }

                        // Recording
                        Repeater {
                            model: root.currentTab === 1 ? root.sourceOutputKeys : []
                            StreamRow {
                                required property string modelData
                                key: modelData
                                isPlayback: false
                            }
                        }
                        EmptyNote {
                            visible: root.currentTab === 1 && root.sourceOutputKeys.length === 0
                            text: "No application is recording audio"
                        }

                        // Output devices
                        Repeater {
                            model: root.currentTab === 2 ? root.sinkKeys : []
                            DeviceRow {
                                required property string modelData
                                key: modelData
                                isSink: true
                            }
                        }

                        // Input devices
                        Repeater {
                            model: root.currentTab === 3 ? root.sourceKeys : []
                            DeviceRow {
                                required property string modelData
                                key: modelData
                                isSink: false
                            }
                        }

                        // Configuration
                        Repeater {
                            model: root.currentTab === 4 ? root.cardKeys : []
                            CardProfileRow {
                                required property string modelData
                                key: modelData
                            }
                        }
                    }
                }
            }
        }
    }
}

import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Widgets
import QtQuick

// The settings window's Sound section (AGENTS.md, Settings window ›
// Sound): the output and the input, each with its volume and the list
// of devices to pick the default from, the input's level meter, and a
// volume per app that is playing. Everything applies at once; PipeWire
// and WirePlumber keep it. There is no Bluetooth profile switch: the
// earbuds stay in A2DP (HFP froze the Intel adapter).
Item {
    id: page

    readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio)
    readonly property var sinks: nodes.filter(n => n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => !n.isSink && !n.isStream)
    // Apps playing: streams that feed a sink (Quickshell's node
    // properties don't carry PipeWire's media.class).
    readonly property var streams: nodes.filter(n => n.isStream && n.isSink)

    PwObjectTracker {
        objects: page.sinks.concat(page.sources).concat(page.streams)
    }

    PwNodePeakMonitor {
        id: meter
        node: Pipewire.defaultAudioSource
        enabled: page.visible && node !== null
    }

    function nameOf(n) {
        return n.description || n.nickname || n.name
    }

    function deviceIcon(n, input) {
        const p = n.properties || {}
        const hint = [n.name, n.description, p["device.icon-name"], p["device.form-factor"]].join(" ").toLowerCase()
        if (/bluez|headset|headphone/.test(hint))
            return input ? "\u{f02ce}" : "\u{f02cb}"
        if (/hdmi|displayport/.test(hint))
            return "\u{f0379}"
        return input ? "\u{f036c}" : "\u{f04c3}"
    }

    function appName(n) {
        const p = n.properties || {}
        return p["application.name"] || p["application.process.binary"] || n.name
    }

    function appIcon(n) {
        const p = n.properties || {}
        const name = p["application.icon-name"] || (p["application.process.binary"] || "").toLowerCase()
        return name ? Quickshell.iconPath(name, true) : ""
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            width: flick.width
            spacing: 8

            // ── Output ──
            Heading { text: "Output" }

            VolumeRow {
                width: parent.width
                node: Pipewire.defaultAudioSink
            }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: page.sinks

                    ListRow {
                        required property var modelData
                        width: parent.width
                        icon: page.deviceIcon(modelData, false)
                        label: page.nameOf(modelData)
                        active: modelData === Pipewire.defaultAudioSink
                        onClicked: Pipewire.preferredDefaultAudioSink = modelData
                    }
                }

                Empty { visible: page.sinks.length === 0; text: "No output devices" }
            }

            Item { width: 1; height: 8 }

            // ── Input ──
            Heading { text: "Input" }

            VolumeRow {
                width: parent.width
                node: Pipewire.defaultAudioSource
                input: true
                // Quickshell's peak is already on a visual scale (the cube
                // root of the sample peak), so it is drawn as it comes.
                level: meter.enabled ? Math.min(1, meter.peak) : -1
            }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: page.sources

                    ListRow {
                        required property var modelData
                        width: parent.width
                        icon: page.deviceIcon(modelData, true)
                        label: page.nameOf(modelData)
                        active: modelData === Pipewire.defaultAudioSource
                        onClicked: Pipewire.preferredDefaultAudioSource = modelData
                    }
                }

                Empty { visible: page.sources.length === 0; text: "No input devices" }
            }

            Item { width: 1; height: 8 }

            // ── Apps ──
            Heading { text: "Apps" }

            Column {
                width: parent.width
                spacing: 4

                Repeater {
                    model: page.streams

                    Item {
                        id: app
                        required property var modelData
                        width: parent.width
                        height: 40

                        IconImage {
                            id: appIcon
                            anchors.left: parent.left
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 24
                            source: page.appIcon(app.modelData)
                            visible: source != ""
                        }

                        Text {
                            anchors.centerIn: appIcon
                            visible: !appIcon.visible
                            text: "\u{f075a}"
                            color: "white"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: 18
                        }

                        Column {
                            id: appText
                            anchors.left: parent.left
                            anchors.leftMargin: 44
                            anchors.verticalCenter: parent.verticalCenter
                            width: 168

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: page.appName(app.modelData)
                                color: "white"
                                font.family: "JetBrainsMono Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: 13
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                elide: Text.ElideRight
                                text: (app.modelData.properties || {})["media.name"] || ""
                                color: "white"
                                opacity: 0.6
                                font.family: "JetBrainsMono Nerd Font"
                                font.weight: Font.Bold
                                font.pixelSize: 11
                            }
                        }

                        VolumeRow {
                            anchors.left: appText.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            node: app.modelData
                        }
                    }
                }

                Empty { visible: page.streams.length === 0; text: "No app is playing sound" }
            }
        }
    }

    component Heading: Text {
        height: 32
        verticalAlignment: Text.AlignVCenter
        color: "white"
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 16
    }

    component Empty: Text {
        height: 40
        leftPadding: 12
        verticalAlignment: Text.AlignVCenter
        color: "white"
        opacity: 0.6
        font.family: "JetBrainsMono Nerd Font"
        font.weight: Font.Bold
        font.pixelSize: 13
    }
}

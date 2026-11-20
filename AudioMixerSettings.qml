import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "audioMixer"

    StyledText {
        width: parent.width
        text: "Bar"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "showPercent"
        label: "Show volume percentage"
        description: "Display the output volume next to the speaker icon"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showMicIcon"
        label: "Show microphone icon"
        description: "Shows mic state (red when muted). Right-click the widget to mute/unmute"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "scrollStep"
        label: "Scroll step"
        description: "Volume change per mouse-wheel notch on the bar widget"
        options: [
            {
                "label": "1%",
                "value": "1"
            },
            {
                "label": "2%",
                "value": "2"
            },
            {
                "label": "5%",
                "value": "5"
            },
            {
                "label": "10%",
                "value": "10"
            }
        ]
        defaultValue: "5"
    }

    StyledText {
        width: parent.width
        text: "Mixer"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    SelectionSetting {
        settingKey: "maxVolume"
        label: "Maximum slider volume"
        description: "Above 100% the sound is amplified in software and may distort"
        options: [
            {
                "label": "100%",
                "value": "100"
            },
            {
                "label": "150%",
                "value": "150"
            }
        ]
        defaultValue: "150"
    }

    ToggleSetting {
        settingKey: "showMeters"
        label: "Show level meters"
        description: "Live sound level bars under each device and app"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showMonitors"
        label: "Show monitor sources"
        description: "List 'Monitor of …' inputs, used to record what your computer is playing"
        defaultValue: false
    }

    StyledText {
        width: parent.width
        text: "Headset jack"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "autoSwitchMic"
        label: "Switch microphone automatically"
        description: "Use the headset mic when earbuds are plugged in, and go back to the internal mic when unplugged"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "notifyOnPlug"
        label: "Notify on plug / unplug"
        description: "Show a notification when a headset is connected or removed"
        defaultValue: true
    }
}

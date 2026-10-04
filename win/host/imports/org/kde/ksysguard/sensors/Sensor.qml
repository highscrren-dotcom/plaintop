import QtQuick

// One sensor by id, as org.kde.ksysguard.sensors has it: `value`, `name` (the sensor's own
// label) and `status` — 2 is Ready, the only number the shared QML tests. Here it is a
// view on the store's last answer; `enabled: false` leaves it blank, as an unsubscribed
// sensor would be.
QtObject {
    id: sensor

    enum Status { Unknown, Loading, Ready, Error }

    property string sensorId: ""
    property bool enabled: true
    property int updateRateLimit: 1000

    property var value: undefined
    property string name: ""
    property int status: Sensor.Loading

    onUpdateRateLimitChanged: SensorStore.want(updateRateLimit)
    onSensorIdChanged: refresh()
    onEnabledChanged: refresh()

    function refresh() {
        if (!enabled || sensorId.length === 0) {
            value = undefined
            status = Sensor.Unknown
            return
        }
        if (!SensorStore.answered) {
            status = Sensor.Loading
            return
        }
        if (SensorStore.has(sensorId)) {
            // The status and the name first, the value last: the shared QML publishes on
            // onValueChanged and reads `status === 2` and `name` in that handler.
            if (status !== Sensor.Ready) status = Sensor.Ready
            const n = SensorStore.name(sensorId)
            if (n.length > 0 && name !== n) name = n
            // Assigning an equal value fires no change signal; a changed one does.
            const v = SensorStore.value(sensorId)
            if (value !== v) value = v
        } else if (status !== Sensor.Error) {
            status = Sensor.Error
        }
    }

    readonly property Connections link: Connections {
        target: SensorStore
        function onUpdated() { sensor.refresh() }
    }

    Component.onCompleted: {
        SensorStore.want(updateRateLimit)
        refresh()
    }
}

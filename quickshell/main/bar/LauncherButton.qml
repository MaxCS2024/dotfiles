import QtQuick
import "../services"

BarButton {
    id: root

    dropdownEnabled: false

    icon: "󰍉"

    onTapped: Panels.toggle("launcher")
}

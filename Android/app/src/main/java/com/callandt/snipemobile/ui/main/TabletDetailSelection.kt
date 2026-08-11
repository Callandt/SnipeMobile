package com.callandt.snipemobile.ui.main

/** Entity shown in the tablet detail pane. */
sealed class TabletDetailSelection {
    data class Asset(val id: Int) : TabletDetailSelection()
    data class Accessory(val id: Int) : TabletDetailSelection()
    data class License(val id: Int) : TabletDetailSelection()
    data class Consumable(val id: Int) : TabletDetailSelection()
    data class Component(val id: Int) : TabletDetailSelection()
    data class User(val id: Int) : TabletDetailSelection()
    data class Location(val id: Int) : TabletDetailSelection()
    data class Maintenance(val id: Int) : TabletDetailSelection()
}

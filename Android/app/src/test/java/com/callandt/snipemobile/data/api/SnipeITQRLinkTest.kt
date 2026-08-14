package com.callandt.snipemobile.data.api

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SnipeITQRLinkTest {
    @Test
    fun parseHardwareUrl() {
        val link = SnipeITQRLink.parse("https://snipe.example.com/hardware/42")
        assertTrue(link is SnipeITQRLink.Hardware)
        assertEquals(42, (link as SnipeITQRLink.Hardware).id)
    }

    @Test
    fun parseHardwareAliasesAndTag() {
        val asset = SnipeITQRLink.parse("https://snipe.example.com/assets/42")
        assertTrue(asset is SnipeITQRLink.Hardware)
        assertEquals(42, (asset as SnipeITQRLink.Hardware).id)

        val tag = SnipeITQRLink.parse("https://snipe.example.com/hardware/00042")
        assertTrue(tag is SnipeITQRLink.HardwareByTag)
        assertEquals("00042", (tag as SnipeITQRLink.HardwareByTag).tag)

        val ht = SnipeITQRLink.parse("https://snipe.example.com/ht/LAPTOP-9")
        assertTrue(ht is SnipeITQRLink.HardwareByTag)
        assertEquals("LAPTOP-9", (ht as SnipeITQRLink.HardwareByTag).tag)

        val byTag = SnipeITQRLink.parse("https://snipe.example.com/hardware/bytag/ABC-1")
        assertTrue(byTag is SnipeITQRLink.HardwareByTag)
        assertEquals("ABC-1", (byTag as SnipeITQRLink.HardwareByTag).tag)
    }

    @Test
    fun parseLocationUrl() {
        val link = SnipeITQRLink.parse("https://snipe.example.com/locations/17")
        assertTrue(link is SnipeITQRLink.Location)
        assertEquals(17, (link as SnipeITQRLink.Location).id)
    }

    @Test
    fun parseLocationUrlWithSubdirectory() {
        val link = SnipeITQRLink.parse("https://snipe.example.com/snipeit/locations/9")
        assertTrue(link is SnipeITQRLink.Location)
        assertEquals(9, (link as SnipeITQRLink.Location).id)
    }

    @Test
    fun parseUserMaintenanceAndSingularAliases() {
        val user = SnipeITQRLink.parse("https://snipe.example.com/users/5")
        assertTrue(user is SnipeITQRLink.User)
        assertEquals(5, (user as SnipeITQRLink.User).id)
        assertTrue(SnipeITQRLink.parse("https://snipe.example.com/user/5") is SnipeITQRLink.User)

        val maintenance = SnipeITQRLink.parse("https://snipe.example.com/maintenances/8")
        assertTrue(maintenance is SnipeITQRLink.Maintenance)
        assertEquals(8, (maintenance as SnipeITQRLink.Maintenance).id)
        assertTrue(SnipeITQRLink.parse("https://snipe.example.com/maintenance/8") is SnipeITQRLink.Maintenance)
    }

    @Test
    fun parseStockEntityUrls() {
        assertEquals(3, (SnipeITQRLink.parse("https://snipe.example.com/accessories/3") as SnipeITQRLink.Accessory).id)
        assertEquals(4, (SnipeITQRLink.parse("https://snipe.example.com/licenses/4") as SnipeITQRLink.License).id)
        assertEquals(6, (SnipeITQRLink.parse("https://snipe.example.com/consumables/6") as SnipeITQRLink.Consumable).id)
        assertEquals(7, (SnipeITQRLink.parse("https://snipe.example.com/components/7") as SnipeITQRLink.Component).id)
    }

    @Test
    fun ignoreNonNumericAndCreatePaths() {
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/locations/create"))
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/users/create"))
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/maintenances/create"))
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/users/0005"))
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/companies/1"))
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/models/12"))
        assertNull(SnipeITQRLink.parse("https://snipe.example.com/model/12"))
    }
}

package com.callandt.snipemobile.ui.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CardLayoutResolverTest {
    @Test
    fun defaultAssetUsesModelTitleTagSerialStatusAndNameLocation() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardKindSpec.spec(CardKind.Asset).defaultLayout,
            name = "MacBook Pro 16\"",
            model = "MacBook Pro",
            tag = "A-100",
            serial = "C02YV1ABJGH6",
            status = "Ready to deploy",
            location = "Brussels",
        )
        assertEquals("MacBook Pro", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("Tag: A-100", "SN: C02YV1ABJGH6", "Ready to deploy"), resolved.headerLines)
        assertEquals(listOf("MacBook Pro 16\"", "Brussels"), resolved.meta.map { it.text })
    }

    @Test
    fun nameAsTitleKeepsTagAndShowsModelInHeader() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardSlotLayout(title = CardFieldID.Name, subtitle = CardFieldID.Tag),
            name = "Pac-Man",
            model = "Arcade Cabinet",
            tag = "A-100",
        )
        assertEquals("Pac-Man", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("Tag: A-100", "Ready to deploy"), resolved.headerLines)
        assertEquals("Arcade Cabinet", resolved.meta.first().text)
    }

    @Test
    fun unusedDefaultSubtitleMovesToHeader() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardSlotLayout(title = CardFieldID.Name, subtitle = CardFieldID.Model),
            name = "Pac-Man",
            model = "Arcade Cabinet",
            tag = "A-100",
            serial = "SN-9",
        )
        assertEquals("Pac-Man", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("Arcade Cabinet", "Tag: A-100", "Ready to deploy"), resolved.headerLines)
        assertTrue(resolved.meta.none { it.text == "Arcade Cabinet" })
    }

    @Test
    fun titleFallsBackWhenPreferredValueIsEmpty() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardSlotLayout(title = CardFieldID.Name, subtitle = CardFieldID.Tag),
            name = "",
            model = "Arcade Cabinet",
            tag = "A-100",
        )
        assertEquals("Arcade Cabinet", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("Tag: A-100", "Ready to deploy"), resolved.headerLines)
        assertEquals(listOf("HQ"), resolved.meta.map { it.text })
    }

    @Test
    fun skipsDuplicateTitleInOtherSlots() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardKindSpec.spec(CardKind.Asset).defaultLayout,
            name = "Same",
            model = "Same",
            tag = "A-100",
        )
        assertEquals("Same", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals("Tag: A-100", resolved.headerLines.first())
        assertTrue(resolved.headerLines.none { it == "Same" })
        assertTrue(resolved.meta.none { it.text == "Same" })
        assertEquals(listOf("HQ"), resolved.meta.map { it.text })
    }

    @Test
    fun userDefaultUsesNameAndEmail() {
        val resolved = CardLayoutResolver.resolve(
            CardKind.User,
            CardKindSpec.spec(CardKind.User).defaultLayout,
            listOf(
                CardFieldContent(CardFieldID.Name, "Ada Lovelace"),
                CardFieldContent(CardFieldID.Email, "ada@example.com"),
                CardFieldContent(CardFieldID.JobTitle, "Engineer"),
                CardFieldContent(CardFieldID.Location, "HQ"),
            ),
        )
        assertEquals("Ada Lovelace", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("ada@example.com"), resolved.headerLines)
        assertEquals(listOf("Engineer", "HQ"), resolved.meta.map { it.text })
    }

    @Test
    fun decodeMigratesPreferAssetNameWhenAssetLayoutMissing() {
        val store = CardLayoutStore.decode("", preferAssetNameInLists = true)
        val layout = store.layout(CardKind.Asset)
        assertEquals(CardFieldID.Name, layout.title)
        assertEquals(CardFieldID.Tag, layout.subtitle)
    }

    @Test
    fun decodeDoesNotOverrideSavedAssetLayout() {
        val json = CardLayoutStore(
            mapOf(CardKind.Asset.id to CardSlotLayout(title = CardFieldID.Serial, subtitle = CardFieldID.Name)),
        ).encodeJson()
        val store = CardLayoutStore.decode(json, preferAssetNameInLists = true)
        val layout = store.layout(CardKind.Asset)
        assertEquals(CardFieldID.Serial, layout.title)
        assertEquals(CardFieldID.Name, layout.subtitle)
    }

    @Test
    fun replacingDefaultRemovesKindFromStore() {
        val store = CardLayoutStore(
            mapOf(CardKind.Asset.id to CardSlotLayout(title = CardFieldID.Name, subtitle = CardFieldID.Tag)),
        ).replacing(CardKind.Asset, CardKindSpec.spec(CardKind.Asset).defaultLayout)
        assertTrue(store.layouts.isEmpty())
        assertEquals("", store.encodeJson())
    }

    @Test
    fun noneSubtitleOmitsSubtitle() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardSlotLayout(title = CardFieldID.Model, subtitle = null),
            name = "Pac-Man",
            model = "Arcade Cabinet",
            tag = "A-100",
        )
        assertEquals("Arcade Cabinet", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("Tag: A-100", "Ready to deploy"), resolved.headerLines)
        assertEquals(listOf("Pac-Man", "HQ"), resolved.meta.map { it.text })
    }

    @Test
    fun explicitLayoutHidesOmittedFields() {
        val resolved = resolve(
            kind = CardKind.Asset,
            layout = CardSlotLayout(
                title = CardFieldID.Name,
                subtitle = CardFieldID.Model,
                details = listOf(CardFieldID.Tag),
                meta = listOf(CardFieldID.Location),
            ),
            name = "Pac-Man",
            model = "Arcade Cabinet",
            tag = "A-100",
            serial = "SN-9",
        )
        assertEquals("Pac-Man", resolved.title)
        assertNull(resolved.subtitle)
        assertEquals(listOf("Arcade Cabinet", "Tag: A-100"), resolved.headerLines)
        assertTrue(resolved.meta.none { it.text.contains("SN") })
        assertTrue(resolved.headerLines.none { it.contains("SN") })
    }

    @Test
    fun customIconIsUsedOnMeta() {
        val resolved = CardLayoutResolver.resolve(
            CardKind.Asset,
            CardSlotLayout(
                title = CardFieldID.Model,
                subtitle = CardFieldID.Tag,
                details = emptyList(),
                meta = listOf(CardFieldID.Location),
                icons = mapOf(CardFieldID.Location to "pin"),
            ),
            listOf(
                CardFieldContent(CardFieldID.Model, "MacBook Pro"),
                CardFieldContent(CardFieldID.Tag, "A-100", formatted = "Tag: A-100"),
                CardFieldContent(CardFieldID.Location, "Amsterdam"),
            ),
        )
        assertEquals("pin", resolved.meta.single().icon)
        assertEquals("Amsterdam", resolved.meta.single().text)
    }

    @Test
    fun replacingUsedFieldSwapsSlots() {
        val spec = CardKindSpec.spec(CardKind.Asset)
        val swapped = spec.defaultLayout.replacingDetail(0, CardFieldID.Name)
        assertEquals(CardFieldID.Model, swapped.title)
        assertEquals(listOf(CardFieldID.Name, CardFieldID.Serial, CardFieldID.Status), swapped.details)
        assertEquals(listOf(CardFieldID.Tag, CardFieldID.Location), swapped.meta)
    }

    private fun resolve(
        kind: CardKind,
        layout: CardSlotLayout,
        name: String,
        model: String,
        tag: String,
        serial: String = "",
        status: String = "Ready to deploy",
        location: String = "HQ",
    ): ResolvedCardLayout = CardLayoutResolver.resolve(
        kind,
        layout,
        listOf(
            CardFieldContent(CardFieldID.Model, model),
            CardFieldContent(CardFieldID.Name, name),
            CardFieldContent(
                id = CardFieldID.Tag,
                raw = tag,
                formatted = tag.takeIf { it.isNotEmpty() }?.let { "Tag: $it" },
            ),
            CardFieldContent(
                id = CardFieldID.Serial,
                raw = serial,
                formatted = serial.takeIf { it.isNotEmpty() }?.let { "SN: $it" },
            ),
            CardFieldContent(CardFieldID.Status, status),
            CardFieldContent(CardFieldID.Location, location),
        ),
    )
}

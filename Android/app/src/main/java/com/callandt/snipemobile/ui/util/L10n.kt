package com.callandt.snipemobile.ui.util

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import java.util.Locale

/** Localized UI strings. */
object L10n {
    const val SYSTEM_LANGUAGE = "system"
    val supportedLanguageCodes = listOf(
        "en", "nl", "fr", "es", "de", "zh", "pt", "ja", "it", "ko", "ru", "ar",
    )

    var overrideLanguageCode: String by mutableStateOf(SYSTEM_LANGUAGE)

    private val languageCode: String
        get() {
            val stored = overrideLanguageCode
            if (stored != SYSTEM_LANGUAGE && stored in supportedLanguageCodes) return stored
            return deviceLanguageCode
        }

    val deviceLanguageCode: String
        get() {
            val code = Locale.getDefault().language.lowercase().ifEmpty { "en" }
            return if (code in supportedLanguageCodes) code else "en"
        }

    /** Picker languages besides the device language. */
    val languagePickerCodes: List<String>
        get() = supportedLanguageCodes.filter { it != deviceLanguageCode }

    private fun nativeLanguageName(code: String): String {
        val loc = Locale.forLanguageTag(code)
        val name = loc.getDisplayLanguage(loc)
        return name.replaceFirstChar { if (it.isLowerCase()) it.titlecase(loc) else it.toString() }
    }

    fun languageDisplayName(code: String): String {
        if (code == SYSTEM_LANGUAGE) {
            return "${nativeLanguageName(deviceLanguageCode)} (${string("system")})"
        }
        return nativeLanguageName(code)
    }

    val isDutch: Boolean get() = languageCode == "nl"
    val isFrench: Boolean get() = languageCode == "fr"
    val isSpanish: Boolean get() = languageCode == "es"
    val isGerman: Boolean get() = languageCode == "de"
    val isChinese: Boolean get() = languageCode == "zh"
    val isPortuguese: Boolean get() = languageCode == "pt"
    val isJapanese: Boolean get() = languageCode == "ja"
    val isItalian: Boolean get() = languageCode == "it"
    val isKorean: Boolean get() = languageCode == "ko"
    val isRussian: Boolean get() = languageCode == "ru"
    val isArabic: Boolean get() = languageCode == "ar"

    val locale: Locale
        get() = when (languageCode) {
            "nl" -> Locale.forLanguageTag("nl-NL")
            "fr" -> Locale.forLanguageTag("fr-FR")
            "es" -> Locale.forLanguageTag("es-ES")
            "de" -> Locale.forLanguageTag("de-DE")
            "zh" -> Locale.forLanguageTag("zh-CN")
            "pt" -> Locale.forLanguageTag("pt-BR")
            "ja" -> Locale.forLanguageTag("ja-JP")
            "it" -> Locale.forLanguageTag("it-IT")
            "ko" -> Locale.forLanguageTag("ko-KR")
            "ru" -> Locale.forLanguageTag("ru-RU")
            "ar" -> Locale.forLanguageTag("ar")
            else -> Locale.forLanguageTag("en-US")
        }

    private fun tableFor(code: String): Map<String, String> = when (code) {
        "nl" -> L10n_nl.strings
        "fr" -> L10n_fr.strings
        "es" -> L10n_es.strings
        "de" -> L10n_de.strings
        "zh" -> L10n_zh.strings
        "pt" -> L10n_pt.strings
        "ja" -> L10n_ja.strings
        "it" -> L10n_it.strings
        "ko" -> L10n_ko.strings
        "ru" -> L10n_ru.strings
        "ar" -> L10n_ar.strings
        else -> L10n_en.strings
    }

    fun string(key: String, locale: Locale = L10n.locale): String {
        val code = locale.language.lowercase().ifEmpty { "en" }
        val primary = tableFor(code)
        return primary[key] ?: L10n_en.strings[key] ?: key
    }

    fun string(key: String, arg: String): String = format(string(key), arg)

    fun string(key: String, arg: Int): String = format(string(key), arg)

    fun string(key: String, arg1: Int, arg2: Int): String = format(string(key), arg1, arg2)

    fun fieldLabel(key: String, required: Boolean = false): String {
        val label = string(key)
        return if (required) "$label *" else label
    }

    fun statusLabel(statusMeta: String): String {
        val key = "status_${statusMeta.trim().lowercase()}"
        val out = string(key)
        return if (out == key) statusMeta else out
    }

    private fun format(template: String, vararg args: Any): String {
        return try {
            String.format(locale, template, *args)
        } catch (_: Exception) {
            var result = template
            args.forEach { arg ->
                when {
                    "%s" in result -> result = result.replaceFirst("%s", arg.toString())
                    "%d" in result -> result = result.replaceFirst("%d", arg.toString())
                    "%@" in result -> result = result.replaceFirst("%@", arg.toString())
                    else -> Unit
                }
            }
            result
        }
    }
}

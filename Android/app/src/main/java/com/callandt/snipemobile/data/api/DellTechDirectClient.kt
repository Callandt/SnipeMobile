package com.callandt.snipemobile.data.api

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.time.Instant
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit
import java.util.Date
import java.util.concurrent.TimeUnit

data class DellWarrantyInfo(
    val shipDate: Date?,
    val warrantyMonths: Int?,
)

sealed class DellTechDirectException(message: String) : Exception(message) {
    class MissingCredentials : DellTechDirectException("Missing credentials")
    class TokenRequestFailed(message: String) : DellTechDirectException(message)
    class WarrantyRequestFailed(message: String) : DellTechDirectException(message)
}

/** Dell TechDirect ship date / warranty lookup. */
object DellTechDirectClient {

    private const val TOKEN_URL = "https://apigtwb2c.us.dell.com/auth/oauth/v2/token"
    private const val ENTITLEMENTS_URL =
        "https://apigtwb2c.us.dell.com/PROD/sbil/eapi/v5/asset-entitlements?servicetags="

    private val http = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    private val json = Json { ignoreUnknownKeys = true }

    /** OAuth2 token for TechDirect. */
    suspend fun testConnection(clientId: String, clientSecret: String): String? =
        runCatching {
            fetchToken(clientId.trim(), clientSecret)
            null
        }.exceptionOrNull()?.let { error ->
            when (error) {
                is DellTechDirectException -> error.message
                else -> error.message ?: error.toString()
            }
        }

    suspend fun fetchWarrantyInfo(
        serviceTag: String,
        clientId: String,
        clientSecret: String,
    ): DellWarrantyInfo = withContext(Dispatchers.IO) {
        val id = clientId.trim()
        val secret = clientSecret
        if (id.isEmpty() || secret.isEmpty()) {
            throw DellTechDirectException.MissingCredentials()
        }
        val tag = serviceTag.trim()
        if (tag.isEmpty()) {
            throw DellTechDirectException.WarrantyRequestFailed("Empty service tag")
        }

        val token = fetchToken(id, secret)
        val encodedTag = URLEncoder.encode(tag, StandardCharsets.UTF_8.name())
        val request = Request.Builder()
            .url(ENTITLEMENTS_URL + encodedTag)
            .header("Authorization", "Bearer $token")
            .get()
            .build()

        http.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw DellTechDirectException.WarrantyRequestFailed(
                    "HTTP ${response.code}: $body",
                )
            }
            parseEntitlementsResponse(body)
        }
    }

    private fun fetchToken(clientId: String, clientSecret: String): String {
        val form = FormBody.Builder()
            .add("client_id", clientId)
            .add("client_secret", clientSecret)
            .add("grant_type", "client_credentials")
            .build()
        val request = Request.Builder()
            .url(TOKEN_URL)
            .post(form)
            .build()

        http.newCall(request).execute().use { response ->
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw DellTechDirectException.TokenRequestFailed(
                    "HTTP ${response.code}: $body",
                )
            }
            val root = runCatching { json.parseToJsonElement(body).jsonObject }.getOrNull()
            val token = root?.get("access_token")?.jsonPrimitive?.contentOrNull
            if (token.isNullOrEmpty()) {
                throw DellTechDirectException.TokenRequestFailed("No access_token in response")
            }
            return token
        }
    }

    private fun parseEntitlementsResponse(body: String): DellWarrantyInfo {
        val element = runCatching { json.parseToJsonElement(body) }.getOrNull() ?: return emptyInfo()

        val asset = when (element) {
            is JsonObject -> {
                element["assets"]?.jsonArray?.firstOrNull()?.jsonObject
                    ?: element.takeIf { it.containsKey("shipDate") || it.containsKey("ShipDate") }
            }
            is JsonArray -> element.firstOrNull()?.jsonObject
            else -> null
        } ?: return emptyInfo()

        val shipDate = parseDate(asset["shipDate"]?.jsonPrimitive?.contentOrNull)
            ?: parseDate(asset["ShipDate"]?.jsonPrimitive?.contentOrNull)

        var latestEnd: Instant? = null
        asset["entitlements"]?.jsonArray?.forEach { entitlement ->
            val endStr = entitlement.jsonObject["endDate"]?.jsonPrimitive?.contentOrNull
                ?: entitlement.jsonObject["EndDate"]?.jsonPrimitive?.contentOrNull
            val end = parseInstant(endStr)
            if (end != null && (latestEnd == null || end.isAfter(latestEnd))) {
                latestEnd = end
            }
        }

        val warrantyMonths = if (shipDate != null && latestEnd != null && latestEnd!!.isAfter(shipDate)) {
            val months = ChronoUnit.MONTHS.between(
                shipDate.atZone(ZoneOffset.UTC).toLocalDate(),
                latestEnd!!.atZone(ZoneOffset.UTC).toLocalDate(),
            ).toInt()
            maxOf(0, months)
        } else {
            null
        }

        return DellWarrantyInfo(
            shipDate = shipDate?.let { Date.from(it) },
            warrantyMonths = warrantyMonths,
        )
    }

    private fun emptyInfo() = DellWarrantyInfo(shipDate = null, warrantyMonths = null)

    private fun parseDate(raw: String?): Instant? = parseInstant(raw)

    private fun parseInstant(raw: String?): Instant? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        return runCatching { Instant.parse(value) }
            .recoverCatching {
                Instant.parse(value.replace(" ", "T") + "Z")
            }
            .getOrNull()
    }
}

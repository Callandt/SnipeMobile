package com.callandt.snipemobile.data.api

import android.net.Uri
import android.util.Base64
import com.callandt.snipemobile.BuildConfig
import com.callandt.snipemobile.debug.AppLog
import com.callandt.snipemobile.ui.util.L10n
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.concurrent.TimeUnit

/** Browser OAuth login. */
object SnipeITOAuthService {
    /** Redirect for Snipe-IT's public mobile OAuth client. */
    const val REDIRECT_SCHEME = "com.grokability.snipeitmobile"
    const val REDIRECT_URI = "com.grokability.snipeitmobile://home"

    private val http = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private val userAgent: String
        get() = "SnipeMobile/${BuildConfig.VERSION_NAME} (Android)"

    sealed class Discovery {
        data class OAuth(val clientId: String) : Discovery()
        data object Unavailable : Discovery()
        data object Unreachable : Discovery()
    }

    data class AuthSession(
        val clientId: String,
        val verifier: String,
        val state: String,
        val authorizeUrl: String,
    )

    data class LoginResult(
        val baseUrl: String,
        val token: String,
    )

    class ServiceException(val kind: Kind) : Exception() {
        enum class Kind {
            InvalidUrl,
            Cancelled,
            MissingCode,
            StateMismatch,
            TokenExchangeFailed,
            OauthUnavailable,
            ConnectionFailed,
        }

        override val message: String
            get() = when (kind) {
                Kind.InvalidUrl -> L10n.string("api_validate_invalid_url")
                Kind.Cancelled -> L10n.string("login_cancelled")
                Kind.MissingCode, Kind.StateMismatch, Kind.TokenExchangeFailed ->
                    L10n.string("login_failed")
                Kind.OauthUnavailable -> L10n.string("login_oauth_unavailable")
                Kind.ConnectionFailed -> L10n.string("login_connection_error")
            }
    }

    suspend fun discover(rawBaseUrl: String): Discovery = withContext(Dispatchers.IO) {
        val base = SnipeApiClient.normalizeBaseUrl(rawBaseUrl)
        val url = runCatching { java.net.URI("$base/api/v1/client").toURL() }.getOrNull()
            ?: return@withContext Discovery.Unreachable
        if (url.protocol != "http" && url.protocol != "https") return@withContext Discovery.Unreachable
        if (url.host.isNullOrBlank()) return@withContext Discovery.Unreachable

        val request = Request.Builder()
            .url(url)
            .header("Accept", "application/json")
            .header("User-Agent", userAgent)
            .get()
            .build()
        try {
            http.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    AppLog.network("OAuth discover HTTP ${response.code}")
                    return@withContext Discovery.Unavailable
                }
                val body = response.body?.string().orEmpty()
                val json = runCatching { JSONObject(body) }.getOrNull()
                    ?: return@withContext Discovery.Unavailable
                val rawId = json.opt("client_id")
                val clientId = rawId?.toString()?.takeIf { it.isNotBlank() && it != "null" }
                if (clientId.isNullOrBlank()) return@withContext Discovery.Unavailable
                AppLog.network("OAuth client discovered")
                Discovery.OAuth(clientId)
            }
        } catch (e: Exception) {
            AppLog.network("OAuth discover failed ${e.javaClass.simpleName}")
            Discovery.Unreachable
        }
    }

    fun startSession(rawBaseUrl: String, clientId: String): AuthSession {
        val base = SnipeApiClient.normalizeBaseUrl(rawBaseUrl)
        val verifier = makeCodeVerifier()
        val state = makeCodeVerifier()
        val challenge = makeCodeChallenge(verifier)
        val uri = Uri.parse("$base/oauth/authorize").buildUpon()
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("client_id", clientId)
            .appendQueryParameter("redirect_uri", REDIRECT_URI)
            .appendQueryParameter("code_challenge", challenge)
            .appendQueryParameter("code_challenge_method", "S256")
            .appendQueryParameter("state", state)
            .appendQueryParameter("prompt", "login")
            .build()
        return AuthSession(
            clientId = clientId,
            verifier = verifier,
            state = state,
            authorizeUrl = uri.toString(),
        )
    }

    fun authorizationCode(callback: Uri, expectedState: String): String {
        val returnedState = callback.getQueryParameter("state")
        if (!returnedState.isNullOrBlank() && returnedState != expectedState) {
            throw ServiceException(ServiceException.Kind.StateMismatch)
        }
        val error = callback.getQueryParameter("error")
        if (!error.isNullOrBlank()) {
            AppLog.network("OAuth authorize error=$error")
            throw ServiceException(ServiceException.Kind.TokenExchangeFailed)
        }
        val code = callback.getQueryParameter("code")
        if (code.isNullOrBlank()) {
            throw ServiceException(ServiceException.Kind.MissingCode)
        }
        return code
    }

    suspend fun completeSignIn(
        rawBaseUrl: String,
        session: AuthSession,
        callback: Uri,
    ): LoginResult = withContext(Dispatchers.IO) {
        val base = SnipeApiClient.normalizeBaseUrl(rawBaseUrl)
        val code = authorizationCode(callback, session.state)
        val accessToken = exchangeCode(base, session, code)
        AppLog.network("OAuth login complete")
        LoginResult(baseUrl = base, token = accessToken)
    }

    private fun exchangeCode(base: String, session: AuthSession, code: String): String {
        val body = FormBody.Builder()
            .add("grant_type", "authorization_code")
            .add("client_id", session.clientId)
            .add("code", code)
            .add("code_verifier", session.verifier)
            .add("redirect_uri", REDIRECT_URI)
            .build()
        val request = Request.Builder()
            .url("$base/oauth/token")
            .header("Accept", "application/json")
            .header("User-Agent", userAgent)
            .post(body)
            .build()
        http.newCall(request).execute().use { response ->
            if (!response.isSuccessful) {
                AppLog.network("OAuth token HTTP ${response.code}")
                throw ServiceException(ServiceException.Kind.TokenExchangeFailed)
            }
            val json = JSONObject(response.body?.string().orEmpty())
            val token = json.optString("access_token")
            if (token.isBlank()) throw ServiceException(ServiceException.Kind.TokenExchangeFailed)
            return token
        }
    }

    private fun makeCodeVerifier(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.encodeToString(bytes, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }

    private fun makeCodeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(verifier.toByteArray(Charsets.US_ASCII))
        return Base64.encodeToString(digest, Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
    }
}

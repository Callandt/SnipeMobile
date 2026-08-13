package com.callandt.snipemobile.data.api

import android.content.Context
import com.callandt.snipemobile.BuildConfig
import com.callandt.snipemobile.data.cache.LocalCacheStore
import com.callandt.snipemobile.widget.WidgetSnapshotBuilder
import com.callandt.snipemobile.data.model.Accessory
import com.callandt.snipemobile.data.model.Activity
import com.callandt.snipemobile.data.model.ActivityResponse
import com.callandt.snipemobile.data.model.MaintenanceType
import com.callandt.snipemobile.data.model.MaintenanceTypesMode
import com.callandt.snipemobile.data.model.ManagementWriteResult
import com.callandt.snipemobile.data.model.Asset
import com.callandt.snipemobile.data.model.AssetAssignedComponent
import com.callandt.snipemobile.data.model.AssetFile
import com.callandt.snipemobile.data.model.AssetFileResponse
import com.callandt.snipemobile.data.model.AssetMaintenance
import com.callandt.snipemobile.data.model.Company
import com.callandt.snipemobile.data.model.Component
import com.callandt.snipemobile.data.model.Consumable
import com.callandt.snipemobile.data.model.CreateResult
import com.callandt.snipemobile.data.model.FieldDefinition
import com.callandt.snipemobile.data.model.Fieldset
import com.callandt.snipemobile.data.model.License
import com.callandt.snipemobile.data.model.LicenseSeatRow
import com.callandt.snipemobile.data.model.Location
import com.callandt.snipemobile.data.model.AccessoryCheckedOutRow
import com.callandt.snipemobile.data.model.AssetModelRow
import com.callandt.snipemobile.data.model.ComponentAssetRow
import com.callandt.snipemobile.data.model.ConsumableUserRow
import com.callandt.snipemobile.data.model.AssetModelRowSerializer
import com.callandt.snipemobile.data.model.CategoryRow
import com.callandt.snipemobile.data.model.Manufacturer
import com.callandt.snipemobile.data.model.PagedResponse
import com.callandt.snipemobile.data.model.SnipeDataCacheSnapshot
import com.callandt.snipemobile.data.model.SnipeJson
import com.callandt.snipemobile.data.model.StatusLabel
import com.callandt.snipemobile.data.model.Supplier
import com.callandt.snipemobile.data.model.User
import com.callandt.snipemobile.data.model.WriteResult
import com.callandt.snipemobile.data.prefs.AppMode
import com.callandt.snipemobile.data.prefs.AppModeCheckProgress
import com.callandt.snipemobile.data.prefs.AppModeStore
import com.callandt.snipemobile.data.prefs.AppPreferences
import com.callandt.snipemobile.data.secure.AppSecret
import com.callandt.snipemobile.ui.util.L10n
import com.callandt.snipemobile.debug.AppLog
import com.callandt.snipemobile.data.secure.SecureStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.Locale
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import kotlin.coroutines.cancellation.CancellationException

data class LoadingProgress(val current: Int, val total: Int)

data class AssetTagGenerationSettings(
    val autoIncrementAssets: Boolean,
    val prefix: String,
    val zerofillCount: Int,
    val nextAutoTagBase: Int,
)

data class AccessoryCheckoutRef(val accessoryId: Int, val checkoutId: Int)

/** A file staged for upload via `uploadAssetFiles`. */
data class UploadFile(val filename: String, val mimeType: String, val data: ByteArray) {
    fun toBase64ImageSource(): String {
        val encoded = android.util.Base64.encodeToString(data, android.util.Base64.NO_WRAP)
        return "data:$mimeType;base64,$encoded"
    }
}

private data class AssignedAccessoriesResult(
    val accessories: List<Accessory>,
    val checkouts: List<AccessoryCheckoutRef>,
)

data class AuthorizedProbeResult(
    val statusCode: Int,
    val data: String,
    val ok: Boolean,
)

/**
 * OkHttp-based Snipe-IT API client.
 */
class SnipeApiClient(
    context: Context,
    private val preferences: AppPreferences,
    private val appModeStore: AppModeStore,
    private val secureStore: SecureStore = SecureStore(context.applicationContext),
) {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private val client = OkHttpClient.Builder()
        .connectTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .addInterceptor { chain ->
            val request = chain.request().newBuilder()
                .header("User-Agent", USER_AGENT)
                .build()
            chain.proceed(request)
        }
        .build()

    private val jsonMediaType = "application/json".toMediaType()

    private val _assets = MutableStateFlow<List<Asset>>(emptyList())
    val assets: StateFlow<List<Asset>> = _assets.asStateFlow()

    private val _users = MutableStateFlow<List<User>>(emptyList())
    val users: StateFlow<List<User>> = _users.asStateFlow()

    private val _accessories = MutableStateFlow<List<Accessory>>(emptyList())
    val accessories: StateFlow<List<Accessory>> = _accessories.asStateFlow()

    private val _licenses = MutableStateFlow<List<License>>(emptyList())
    val licenses: StateFlow<List<License>> = _licenses.asStateFlow()

    private val _consumables = MutableStateFlow<List<Consumable>>(emptyList())
    val consumables: StateFlow<List<Consumable>> = _consumables.asStateFlow()

    private val _components = MutableStateFlow<List<Component>>(emptyList())
    val components: StateFlow<List<Component>> = _components.asStateFlow()

    private val _locations = MutableStateFlow<List<Location>>(emptyList())
    val locations: StateFlow<List<Location>> = _locations.asStateFlow()

    private val _companies = MutableStateFlow<List<Company>>(emptyList())
    val companies: StateFlow<List<Company>> = _companies.asStateFlow()

    private val _manufacturers = MutableStateFlow<List<Manufacturer>>(emptyList())
    val manufacturers: StateFlow<List<Manufacturer>> = _manufacturers.asStateFlow()

    private val _suppliers = MutableStateFlow<List<Supplier>>(emptyList())
    val suppliers: StateFlow<List<Supplier>> = _suppliers.asStateFlow()

    private val _statusLabels = MutableStateFlow<List<StatusLabel>>(emptyList())
    val statusLabels: StateFlow<List<StatusLabel>> = _statusLabels.asStateFlow()

    private val _models = MutableStateFlow<List<AssetModelRow>>(emptyList())
    val models: StateFlow<List<AssetModelRow>> = _models.asStateFlow()

    private val _categories = MutableStateFlow<List<CategoryRow>>(emptyList())
    val categories: StateFlow<List<CategoryRow>> = _categories.asStateFlow()

    private val _assetTagSettings = MutableStateFlow<AssetTagGenerationSettings?>(null)
    val assetTagSettings: StateFlow<AssetTagGenerationSettings?> = _assetTagSettings.asStateFlow()

    private val _fieldDefinitions = MutableStateFlow<List<FieldDefinition>>(emptyList())
    val fieldDefinitions: StateFlow<List<FieldDefinition>> = _fieldDefinitions.asStateFlow()

    private val _fieldsets = MutableStateFlow<List<Fieldset>?>(null)
    val fieldsets: StateFlow<List<Fieldset>?> = _fieldsets.asStateFlow()

    private val _maintenances = MutableStateFlow<List<AssetMaintenance>>(emptyList())
    val maintenances: StateFlow<List<AssetMaintenance>> = _maintenances.asStateFlow()

    private val _maintenanceTypes = MutableStateFlow<List<MaintenanceType>>(emptyList())
    val maintenanceTypes: StateFlow<List<MaintenanceType>> = _maintenanceTypes.asStateFlow()

    private val _maintenanceTypesMode = MutableStateFlow(MaintenanceTypesMode.Unknown)
    val maintenanceTypesMode: StateFlow<MaintenanceTypesMode> = _maintenanceTypesMode.asStateFlow()

    private val _currentUser = MutableStateFlow<User?>(null)
    val currentUser: StateFlow<User?> = _currentUser.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _isConfigured = MutableStateFlow(false)
    val isConfigured: StateFlow<Boolean> = _isConfigured.asStateFlow()

    private val _hasCompletedInitialLoad = MutableStateFlow(false)
    val hasCompletedInitialLoad: StateFlow<Boolean> = _hasCompletedInitialLoad.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _refreshErrorMessage = MutableStateFlow<String?>(null)
    val refreshErrorMessage: StateFlow<String?> = _refreshErrorMessage.asStateFlow()

    private val _pendingUnauthorizedSessionWipe = MutableStateFlow(false)
    val pendingUnauthorizedSessionWipe: StateFlow<Boolean> = _pendingUnauthorizedSessionWipe.asStateFlow()

    /** Keep the first refresh error of a sync. */
    private fun reportRefreshError(message: String) {
        if (_refreshErrorMessage.value == null) {
            _refreshErrorMessage.value = message
        }
    }

    fun clearRefreshError() {
        _refreshErrorMessage.value = null
    }

    fun clearPendingUnauthorizedSessionWipe() {
        _pendingUnauthorizedSessionWipe.value = false
    }

    private fun isUnauthorizedStatus(code: Int): Boolean = code == 401 || code == 403

    /** 401/403 → wipe dialog (when configured). */
    private fun reportUnauthorizedSession() {
        val onboarded = preferences.getHasCompletedOnboardingBlocking()
        if (!_isConfigured.value || !onboarded) {
            reportRefreshError(L10n.string("api_validate_unauthorized"))
            return
        }
        if (_pendingUnauthorizedSessionWipe.value) return
        _refreshErrorMessage.value = null
        _pendingUnauthorizedSessionWipe.value = true
    }

    private fun reportHttpRefreshFailure(statusCode: Int) {
        if (isUnauthorizedStatus(statusCode)) {
            reportUnauthorizedSession()
        } else {
            reportRefreshError(localizedHttpFailureMessage(statusCode))
        }
    }

    private val _lastApiMessage = MutableStateFlow<String?>(null)
    val lastApiMessage: StateFlow<String?> = _lastApiMessage.asStateFlow()

    private val _loadingProgress = MutableStateFlow<LoadingProgress?>(null)
    val loadingProgress: StateFlow<LoadingProgress?> = _loadingProgress.asStateFlow()

    private var cacheSaveJob: Job? = null
    private var isApplyingCache = false
    private var primaryFetchJob: Job? = null
    private val primaryFetchMutex = Mutex()
    private val fetchAssetsGeneration = AtomicInteger(0)
    private var fetchAssetsJob: Job? = null
    private val assetsPendingDetailRefresh = mutableSetOf<Int>()

    val baseUrl: String
        get() = normalizeBaseUrl(preferences.getBaseUrlBlocking())

    val apiToken: String
        get() = secureStore.getString(AppSecret.API_TOKEN)

    private val cacheKey: String
        get() = LocalCacheStore.keyForBaseUrl(baseUrl)

    init {
        secureStore.migrateLegacyPlaintextSecretsIfNeeded(
            appContext.getSharedPreferences("snipe_app_prefs", Context.MODE_PRIVATE),
        )
        _isConfigured.value = preferences.getIsConfiguredBlocking()
        loadCachedDataIfAvailable()
        if (_isConfigured.value && baseUrl.isNotEmpty()) {
            scope.launch { fetchCurrentUser() }
            scope.launch { syncForCurrentAppMode() }
        }
    }

    // region Configuration & cache

    /** Save URL/token; optionally sync afterward. */
    suspend fun saveConfiguration(
        baseURL: String,
        apiToken: String,
        syncAfterSave: Boolean = true,
    ) {
        val normalizedBaseUrl = normalizeBaseUrl(baseURL)
        val normalizedToken = normalizeApiToken(apiToken)
        val previousUrl = this.baseUrl
        val previousToken = this.apiToken
        val credentialsChanged = normalizedBaseUrl != previousUrl || normalizedToken != previousToken

        if (credentialsChanged) {
            clearSessionData(resetAppMode = true, fullWipe = false)
            appModeStore.clearForServerChange()
        }

        preferences.setBaseUrl(normalizedBaseUrl)
        secureStore.setString(AppSecret.API_TOKEN, normalizedToken)
        _isConfigured.value = true
        preferences.setIsConfigured(true)

        if (syncAfterSave) {
            scope.launch { syncForCurrentAppMode() }
        }
    }

    /** Clear lists and on-disk cache. */
    fun clearSessionData(
        resetConfigured: Boolean = false,
        resetAppMode: Boolean = true,
        fullWipe: Boolean = resetConfigured,
    ) {
        cacheSaveJob?.cancel()
        primaryFetchJob?.cancel()
        primaryFetchJob = null
        fetchAssetsJob?.cancel()
        fetchAssetsGeneration.incrementAndGet()
        assetsPendingDetailRefresh.clear()

        isApplyingCache = true
        try {
            _assets.value = emptyList()
            _users.value = emptyList()
            _currentUser.value = null
            _accessories.value = emptyList()
            _licenses.value = emptyList()
            _consumables.value = emptyList()
            _components.value = emptyList()
            _locations.value = emptyList()
            _companies.value = emptyList()
            _manufacturers.value = emptyList()
            _suppliers.value = emptyList()
            _statusLabels.value = emptyList()
            _models.value = emptyList()
            _categories.value = emptyList()
            _maintenances.value = emptyList()
            _maintenanceTypes.value = emptyList()
            _maintenanceTypesMode.value = MaintenanceTypesMode.Unknown
            _assetTagSettings.value = null
            _fieldDefinitions.value = emptyList()
            _fieldsets.value = null
            _hasCompletedInitialLoad.value = false
            _isLoading.value = false
            _loadingProgress.value = null
            _errorMessage.value = null
            _lastApiMessage.value = null
            _refreshErrorMessage.value = null
            _pendingUnauthorizedSessionWipe.value = false
            if (resetConfigured) {
                _isConfigured.value = false
            }
        } finally {
            isApplyingCache = false
        }

        LocalCacheStore.clearAll(appContext)
        WidgetSnapshotBuilder.clear(appContext)

        if (resetAppMode) {
            if (fullWipe) appModeStore.clear()
            else appModeStore.clearForServerChange()
        }
    }

    suspend fun validateApiCredentials(): String? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return L10n.string("api_validate_missing")
        }
        val url = "$baseUrl/api/v1/users/me".toHttpUrlOrNull()
            ?: return L10n.string("api_validate_invalid_url")
        if (url.scheme !in setOf("http", "https") || url.host.isEmpty()) {
            return L10n.string("api_validate_invalid_url")
        }
        AppLog.network("Validating API credentials scheme=${url.scheme}")
        return try {
            val response = executeGet(url.toString(), reportConnectionError = false)
            AppLog.network("Validate HTTP ${response.code} bytes=${response.body.length}")
            if (response.code in 200..299) null
            else localizedHttpFailureMessage(response.code)
        } catch (e: Exception) {
            AppLog.network("Validate failed: ${e.javaClass.simpleName}")
            localizedConnectionFailureMessage(e)
        }
    }

    fun loadCachedDataIfAvailable() {
        if (!_isConfigured.value || baseUrl.isEmpty()) return
        val snapshot = LocalCacheStore.load(appContext, cacheKey) ?: return
        isApplyingCache = true
        try {
            if (snapshot.assets.isNotEmpty()) _hasCompletedInitialLoad.value = true
            if (_assets.value.isEmpty()) _assets.value = snapshot.assets
            if (_users.value.isEmpty()) _users.value = snapshot.users
            if (_currentUser.value == null && snapshot.currentUser != null) {
                _currentUser.value = snapshot.users.find { it.id == snapshot.currentUser?.id }
                    ?: snapshot.currentUser
            }
            if (_accessories.value.isEmpty()) _accessories.value = snapshot.accessories
            if (_licenses.value.isEmpty()) _licenses.value = snapshot.licenses
            if (_consumables.value.isEmpty()) _consumables.value = snapshot.consumables
            if (_components.value.isEmpty()) _components.value = snapshot.components
            if (_locations.value.isEmpty()) _locations.value = snapshot.locations
            if (_companies.value.isEmpty()) _companies.value = snapshot.companies
            if (_manufacturers.value.isEmpty()) _manufacturers.value = snapshot.manufacturers
            if (_suppliers.value.isEmpty()) _suppliers.value = snapshot.suppliers
            if (_statusLabels.value.isEmpty()) _statusLabels.value = snapshot.statusLabels
            if (_maintenances.value.isEmpty()) _maintenances.value = snapshot.maintenances
        } finally {
            isApplyingCache = false
        }
    }

    private fun scheduleCacheSave() {
        if (isApplyingCache || !_isConfigured.value || baseUrl.isEmpty()) return
        cacheSaveJob?.cancel()
        cacheSaveJob = scope.launch {
            delay(CACHE_SAVE_DEBOUNCE_MS)
            persistCacheNow()
        }
    }

    private suspend fun persistCacheNow() {
        if (!_isConfigured.value || baseUrl.isEmpty()) return
        val snapshot = SnipeDataCacheSnapshot(
            assets = _assets.value,
            users = _users.value,
            currentUser = _currentUser.value,
            accessories = _accessories.value,
            licenses = _licenses.value,
            consumables = _consumables.value,
            components = _components.value,
            locations = _locations.value,
            companies = _companies.value,
            manufacturers = _manufacturers.value,
            suppliers = _suppliers.value,
            statusLabels = _statusLabels.value,
            maintenances = _maintenances.value,
        )
        LocalCacheStore.save(appContext, snapshot, cacheKey)
        WidgetSnapshotBuilder.update(appContext, snapshot, baseUrl, _isConfigured.value)
    }

    // endregion

    // region Sync

    suspend fun fetchPrimaryThenBackground(clearRefreshError: Boolean = false) {
        val jobToAwait = primaryFetchMutex.withLock {
            primaryFetchJob?.takeIf { it.isActive }
                ?: scope.launch { performPrimaryThenBackground(clearRefreshError) }
                    .also { primaryFetchJob = it }
        }
        jobToAwait.join()
    }

    private suspend fun performPrimaryThenBackground(clearRefreshError: Boolean) {
        withContext(Dispatchers.Main) {
            _isLoading.value = true
            _errorMessage.value = null
            if (clearRefreshError) {
                _refreshErrorMessage.value = null
            }
        }
        fetchCurrentUser()
        fetchAssets()
        // Stop after auth/connectivity failure.
        if (_refreshErrorMessage.value != null || _pendingUnauthorizedSessionWipe.value) {
            withContext(Dispatchers.Main) {
                _isLoading.value = false
                _hasCompletedInitialLoad.value = true
            }
            return
        }
        fetchUsers()
        reconcileCurrentUserWithUsersList()
        if (_refreshErrorMessage.value != null || _pendingUnauthorizedSessionWipe.value) {
            withContext(Dispatchers.Main) {
                _isLoading.value = false
                _hasCompletedInitialLoad.value = true
            }
            return
        }
        fetchAccessories()
        fetchLicenses()
        fetchConsumables()
        fetchComponents()
        fetchLocations()
        fetchAllMaintenances()
        withContext(Dispatchers.Main) {
            _isLoading.value = false
            _hasCompletedInitialLoad.value = true
        }
        if (_refreshErrorMessage.value != null || _pendingUnauthorizedSessionWipe.value) return
        scope.launch {
            fetchCompanies()
            fetchStatusLabels()
            fetchAssetTagSettings()
            fetchManufacturers()
            fetchCategories()
            fetchSuppliers()
            fetchModels()
            fetchFieldDefinitions()
            fetchFieldsets()
        }
    }

    fun syncAllInBackground() {
        scope.launch { syncForCurrentAppMode() }
    }

    // region App mode

    /** Authenticated GET probe. */
    suspend fun authorizedProbe(
        path: String,
        query: Map<String, String> = emptyMap(),
    ): AuthorizedProbeResult? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        val builder = "$baseUrl$path".toHttpUrlOrNull()?.newBuilder() ?: return null
        query.forEach { (key, value) -> builder.addQueryParameter(key, value) }
        return try {
            val response = executeGet(builder.build().toString(), reportConnectionError = false)
            AuthorizedProbeResult(
                statusCode = response.code,
                data = response.body,
                ok = response.code in 200..299,
            )
        } catch (_: Exception) {
            null
        }
    }

    /** Detect admin vs user; reports progress via [onProgress]. */
    suspend fun detectAppMode(
        onProgress: (AppModeCheckProgress) -> Unit = {},
    ): AppModeCheckProgress {
        var progress = AppModeCheckProgress()

        suspend fun publish() {
            val snapshot = progress
            withContext(Dispatchers.Main) { onProgress(snapshot) }
        }

        progress = progress.copy(connection = AppModeCheckProgress.StepState.Running)
        publish()

        val meProbe = authorizedProbe("/api/v1/users/me")
        if (meProbe == null) {
            progress = progress.copy(
                connection = AppModeCheckProgress.StepState.Failure(
                    L10n.string("api_validate_connect_failed"),
                ),
            )
            publish()
            return progress
        }

        val user = if (meProbe.ok) decodePayloadOrRoot<User>(meProbe.data) else null
        if (user == null) {
            progress = progress.copy(
                connection = AppModeCheckProgress.StepState.Failure(
                    localizedHttpFailureMessage(meProbe.statusCode),
                ),
            )
            publish()
            return progress
        }

        withContext(Dispatchers.Main) { _currentUser.value = user }
        progress = progress.copy(connection = AppModeCheckProgress.StepState.Success)
        publish()

        progress = progress.copy(rights = AppModeCheckProgress.StepState.Running)
        publish()

        val permissionHintsIsAdmin = adminPermissionHints(meProbe.data)
        val hardwareProbe = authorizedProbe("/api/v1/hardware", mapOf("limit" to "1"))
        val isAdmin = permissionHintsIsAdmin || (hardwareProbe?.ok == true)
        val mode = if (isAdmin) AppMode.Admin else AppMode.User

        progress = progress.copy(
            detectedMode = mode,
            rights = AppModeCheckProgress.StepState.Success,
        )
        publish()

        withContext(Dispatchers.Main) {
            appModeStore.applyDetection(
                detectedMode = mode,
                canRequestAssets = appModeStore.canRequestAssets.value,
            )
        }

        return progress
    }

    /** Sync for the active app mode. */
    suspend fun syncForCurrentAppMode() {
        when (appModeStore.current.value) {
            AppMode.User -> {
                fetchUserModeData()
                WidgetSnapshotBuilder.publishAdminOnly(appContext, baseUrl, _isConfigured.value)
            }
            AppMode.Admin, null -> fetchPrimaryThenBackground()
        }
    }

    /** Load current user and assigned items. */
    suspend fun fetchUserModeData(clearRefreshError: Boolean = false) {
        withContext(Dispatchers.Main) {
            _isLoading.value = true
            _errorMessage.value = null
            if (clearRefreshError) {
                _refreshErrorMessage.value = null
            }
        }

        fetchCurrentUser(reportErrors = true)
        if (_refreshErrorMessage.value != null || _pendingUnauthorizedSessionWipe.value) {
            withContext(Dispatchers.Main) {
                _isLoading.value = false
                _hasCompletedInitialLoad.value = true
            }
            return
        }

        val userId = _currentUser.value?.id
        if (userId != null) {
            val myAssets = fetchUserAssets(userId)
            val myAccessories = fetchUserAccessories(userId, allowAdminFallback = false)
            val myLicenses = fetchUserLicenses(userId)
            withContext(Dispatchers.Main) {
                _assets.value = myAssets
                _accessories.value = myAccessories
                _licenses.value = myLicenses
            }
        } else if (_isConfigured.value) {
            reportRefreshError(L10n.string("api_validate_connect_failed"))
        }

        withContext(Dispatchers.Main) {
            _isLoading.value = false
            _hasCompletedInitialLoad.value = true
        }
        scheduleCacheSave()
    }

    suspend fun fetchRequestableAssets(reportErrors: Boolean = false): List<Asset> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            if (reportErrors) {
                reportRefreshError(L10n.string("api_validate_missing"))
            }
            return emptyList()
        }
        return try {
            fetchAllPaginated(
                path = "/api/v1/account/requestable/hardware",
                serializer = Asset.serializer(),
                reportConnectionError = reportErrors,
            ).orEmpty()
        } catch (e: Exception) {
            if (reportErrors) {
                reportRefreshError(localizedConnectionFailureMessage(e))
            }
            emptyList()
        }
    }

    /** Request an asset for the current user. */
    suspend fun requestAsset(assetId: Int): String? =
        postAccountRequestAction("/api/v1/account/request/$assetId")

    suspend fun cancelAssetRequest(assetId: Int): String? =
        postAccountRequestAction("/api/v1/account/request/$assetId/cancel")

    private suspend fun postAccountRequestAction(path: String): String? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return L10n.string("api_validate_missing")
        }
        val url = "$baseUrl$path".toHttpUrlOrNull()?.toString()
            ?: return L10n.string("api_validate_invalid_url")
        return try {
            val response = executeJsonPost(url, emptyMap())
            if (response.code in 200..299 && !isSnipeApiErrorResponse(response.json)) {
                null
            } else {
                parseSnipeErrorMessage(response.body)
                    ?: localizedHttpFailureMessage(response.code)
            }
        } catch (e: Exception) {
            localizedConnectionFailureMessage(e)
        }
    }

    private fun adminPermissionHints(data: String): Boolean {
        val json = parseJsonObject(data) ?: return false
        val root = json["payload"]?.jsonObject ?: json
        val permissions = root["permissions"]?.jsonObject ?: return false

        fun isGranted(key: String): Boolean {
            val value = permissions[key] ?: return false
            if (value is JsonNull) return false
            val primitive = runCatching { value.jsonPrimitive }.getOrNull() ?: return false
            primitive.contentOrNull?.let { content ->
                return content == "1" || content.equals("true", ignoreCase = true)
            }
            return (primitive.intOrNull ?: 0) != 0
        }

        return isGranted("superuser") || isGranted("admin")
    }

    private fun parseSnipeErrorMessage(body: String): String? {
        val json = parseJsonObject(body) ?: return null
        json["messages"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { return it }
        return extractApiErrorMessage(json)
    }

    // endregion

    suspend fun fetchCurrentUser(reportErrors: Boolean = false) {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            if (reportErrors) {
                reportRefreshError(L10n.string("api_validate_missing"))
            }
            return
        }
        val url = "$baseUrl/api/v1/users/me"
        try {
            val response = executeGet(url)
            if (isUnauthorizedStatus(response.code)) {
                withContext(Dispatchers.Main) {
                    reportUnauthorizedSession()
                }
                return
            }
            if (response.code !in 200..299) {
                if (reportErrors) {
                    withContext(Dispatchers.Main) {
                        reportHttpRefreshFailure(response.code)
                    }
                }
                return
            }
            decodePayloadOrRoot<User>(response.body)?.let { user ->
                withContext(Dispatchers.Main) {
                    _currentUser.value = user
                    reconcileCurrentUserWithUsersList()
                }
            } ?: run {
                if (reportErrors) {
                    reportRefreshError(L10n.string("api_validate_connect_failed"))
                }
            }
        } catch (e: Exception) {
            if (reportErrors) {
                reportRefreshError(localizedConnectionFailureMessage(e))
            }
        }
    }

    private fun reconcileCurrentUserWithUsersList() {
        // Keep `/users/me`; do not overwrite from the users list.
    }

    suspend fun fetchAssets() {
        fetchAssetsJob?.cancel()
        val generation = fetchAssetsGeneration.incrementAndGet()
        fetchAssetsJob = scope.launch {
            if (baseUrl.isEmpty() || apiToken.isEmpty()) {
                withContext(Dispatchers.Main) {
                    _errorMessage.value = L10n.string("configure_api_short")
                }
                return@launch
            }
            val rows = fetchAllPaginated(
                path = "/api/v1/hardware",
                serializer = Asset.serializer(),
                reportProgress = true,
                reportConnectionError = true,
                isCancelled = { generation != fetchAssetsGeneration.get() },
            ) ?: return@launch
            if (generation != fetchAssetsGeneration.get()) return@launch
            val merged = rows.toMutableList()
            synchronized(assetsPendingDetailRefresh) {
                assetsPendingDetailRefresh.forEach { id ->
                    val existing = _assets.value.find { it.id == id }
                    val idx = merged.indexOfFirst { it.id == id }
                    if (existing != null && idx >= 0) merged[idx] = existing
                }
            }
            withContext(Dispatchers.Main) { _assets.value = merged }
            reconcilePendingAssetDetails()
            scheduleCacheSave()
        }
        fetchAssetsJob?.join()
    }

    suspend fun fetchUsers() {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            withContext(Dispatchers.Main) { _errorMessage.value = L10n.string("configure_api_short") }
            return
        }
        val rows = fetchAllPaginated(
            path = "/api/v1/users",
            serializer = User.serializer(),
            reportConnectionError = true,
        ) ?: return
        withContext(Dispatchers.Main) {
            _users.value = rows.sortedBy { it.decodedName.lowercase() }
            reconcileCurrentUserWithUsersList()
        }
        scheduleCacheSave()
    }

    suspend fun fetchAccessories() = fetchSimpleList("/api/v1/accessories", Accessory.serializer()) { incoming ->
        val previousById = _accessories.value.associateBy { it.id }
        _accessories.value = incoming.map { item ->
            val cachedNotes = previousById[item.id]?.notes
            if (item.notes.isNullOrBlank() && !cachedNotes.isNullOrBlank()) {
                item.copy(notes = cachedNotes)
            } else {
                item
            }
        }
    }

    suspend fun fetchLicenses() = fetchSimpleList("/api/v1/licenses", License.serializer()) {
        _licenses.value = it
    }

    suspend fun fetchConsumables() = fetchSimpleList("/api/v1/consumables", Consumable.serializer()) {
        _consumables.value = it
    }

    suspend fun fetchComponents() = fetchSimpleList("/api/v1/components", Component.serializer()) {
        _components.value = it
    }

    suspend fun fetchLocations() = fetchSimpleList("/api/v1/locations", Location.serializer()) {
        _locations.value = it.sortedBy { loc -> loc.decodedName.lowercase() }
    }

    suspend fun fetchCompanies() = fetchSimpleList("/api/v1/companies", Company.serializer()) {
        _companies.value = it.sortedBy { c -> c.name.lowercase() }
    }

    suspend fun fetchManufacturers() = fetchSimpleList("/api/v1/manufacturers", Manufacturer.serializer()) {
        _manufacturers.value = it.sortedBy { m -> m.name.lowercase() }
    }

    suspend fun fetchSuppliers() = fetchSimpleList("/api/v1/suppliers", Supplier.serializer()) {
        _suppliers.value = it.sortedBy { s -> s.name.lowercase() }
    }

    suspend fun fetchStatusLabels() = fetchSimpleList("/api/v1/statuslabels", StatusLabel.serializer()) {
        _statusLabels.value = it
    }

    suspend fun fetchModels() = fetchSimpleList("/api/v1/models", AssetModelRowSerializer) {
        _models.value = it.sortedBy { model -> model.decodedName.lowercase() }
    }

    suspend fun fetchCategories() = fetchSimpleList("/api/v1/categories", CategoryRow.serializer()) {
        _categories.value = it.sortedBy { row -> row.decodedName.lowercase() }
    }

    /** Asset-tag settings from the server. No-op if unauthorized. */
    suspend fun fetchAssetTagSettings() {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return
        runCatching {
            val response = executeGet("$baseUrl/api/v1/settings/1")
            if (response.code !in 200..299) return
            val json = response.json ?: return
            parseAssetTagSettings(json)?.let { settings ->
                withContext(Dispatchers.Main) { _assetTagSettings.value = settings }
            }
        }
    }

    // region Custom field definitions / fieldsets

    suspend fun fetchFieldDefinitions() {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return
        runCatching {
            val response = executeGet("$baseUrl/api/v1/fields")
            val rows = response.json?.get("rows")?.jsonArray ?: return
            val fields = rows.mapNotNull { decodeJsonElementValue<FieldDefinition>(it) }
            withContext(Dispatchers.Main) { _fieldDefinitions.value = fields }
        }
    }

    suspend fun fetchFieldsets() {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return
        runCatching {
            val response = executeGet("$baseUrl/api/v1/fieldsets")
            val rows = response.json?.get("rows")?.jsonArray ?: return
            val sets = rows.mapNotNull { decodeJsonElementValue<Fieldset>(it) }
            withContext(Dispatchers.Main) { _fieldsets.value = sets }
        }
    }

    /** Field definitions for a model, derived from the cached fieldsets (no per-model defaults). */
    fun modelFieldDefinitionsFromFieldsets(modelId: Int): List<FieldDefinition> {
        val fieldset = _fieldsets.value?.firstOrNull { it.modelIds.contains(modelId) } ?: return emptyList()
        return fieldset.fields.map { f ->
            FieldDefinition(
                id = f.id,
                name = f.name,
                type = f.type,
                fieldValuesArray = f.fieldValuesArray,
            )
        }
    }

    /** Field defs for a model: fieldset defaults, then cache, then models/{id}/fields. */
    suspend fun fetchModelFieldDefinitions(modelId: Int): List<FieldDefinition> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        if (_fieldsets.value == null) fetchFieldsets()
        val fieldsetId = _fieldsets.value?.firstOrNull { it.modelIds.contains(modelId) }?.id
        if (fieldsetId != null) {
            val withDefaults = fetchFieldsetFieldsWithDefaults(fieldsetId, modelId)
            if (!withDefaults.isNullOrEmpty()) return withDefaults
            val fromFieldsets = modelFieldDefinitionsFromFieldsets(modelId)
            if (fromFieldsets.isNotEmpty()) return fromFieldsets
        }
        val fromModelEndpoint = runCatching {
            val response = executeGet("$baseUrl/api/v1/models/$modelId/fields")
            if (!isSnipeApiHttpSuccess(response.code)) return@runCatching null
            val rows = response.json?.get("rows")?.jsonArray ?: response.json?.get("fields")?.jsonArray
            rows?.mapNotNull { decodeJsonElementValue<FieldDefinition>(it) }
        }.getOrNull()
        if (!fromModelEndpoint.isNullOrEmpty()) return fromModelEndpoint
        if (_fieldsets.value == null) fetchFieldsets()
        return modelFieldDefinitionsFromFieldsets(modelId)
    }

    private suspend fun fetchFieldsetFieldsWithDefaults(fieldsetId: Int, modelId: Int): List<FieldDefinition>? =
        runCatching {
            val url = "$baseUrl/api/v1/fieldsets/$fieldsetId/fields/$modelId"
            val request = authorizedRequest(url)
                .post("".toRequestBody("application/json".toMediaType()))
                .build()
            val response = withContext(Dispatchers.IO) { client.newCall(request).execute() }
            if (!isSnipeApiHttpSuccess(response.code)) return@runCatching null
            val body = response.body?.string().orEmpty()
            val json = parseJsonObject(body) ?: return@runCatching null
            val rows = json["rows"]?.jsonArray ?: return@runCatching null
            rows.mapNotNull { decodeJsonElementValue<FieldDefinition>(it) }
        }.getOrNull()

    /** Linked fields for a fieldset, with fallbacks for older Snipe-IT builds. */
    suspend fun fetchFieldsetLinkedFields(fieldsetId: Int): Pair<List<JsonObject>?, String?> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return null to L10n.string("settings_not_configured")
        }

        fun fieldRows(json: JsonObject): List<JsonObject>? {
            json["rows"]?.jsonArray?.let { return it.filterIsInstance<JsonObject>() }
            json["fields"]?.jsonObject?.get("rows")?.jsonArray?.let { return it.filterIsInstance<JsonObject>() }
            (json["payload"] as? JsonObject)?.let { payload ->
                payload["rows"]?.jsonArray?.let { return it.filterIsInstance<JsonObject>() }
                payload["fields"]?.jsonObject?.get("rows")?.jsonArray?.let { return it.filterIsInstance<JsonObject>() }
            }
            return null
        }

        suspend fun tryPath(path: String): Pair<List<JsonObject>?, String?>? {
            val response = try {
                executeGet("$baseUrl$path")
            } catch (e: Exception) {
                return null to e.message
            }
            if (isSnipeApiHttpSuccess(response.code)) {
                response.json?.let { json ->
                    fieldRows(json)?.let { return enrichFieldsetFieldRows(it) to null }
                }
            }
            if (response.code != 404) {
                return null to (extractApiErrorMessage(response.json) ?: "HTTP ${response.code}")
            }
            return null
        }

        tryPath("/api/v1/fieldsets/$fieldsetId/fields")?.let { return it }
        tryPath("/api/v1/fieldsets/$fieldsetId")?.let { return it }

        fetchFieldsets()
        val cached = _fieldsets.value?.firstOrNull { it.id == fieldsetId }
        if (cached != null) {
            val rows = cached.fields.map { field ->
                buildJsonObject {
                    put("id", field.id)
                    put("name", field.name)
                    put("type", field.type ?: "")
                }
            }
            return rows to null
        }
        return null to L10n.string("mgmt_load_failed")
    }

    suspend fun reorderFieldsetFields(fieldsetId: Int, fieldIds: List<Int>): ManagementWriteResult =
        managementCreate(
            path = "/api/v1/fields/fieldsets/$fieldsetId/order",
            body = mapOf("item" to buildJsonArray { fieldIds.forEach { add(it) } }),
        )

    private suspend fun enrichFieldsetFieldRows(rows: List<JsonObject>): List<JsonObject> {
        if (rows.all { it["id"] != null }) return rows
        val (catalog, _) = managementFetchRows("/api/v1/fields")
        if (catalog == null) return rows

        fun resolveId(row: JsonObject): Int? {
            row["id"]?.jsonPrimitive?.intOrNull?.let { return it }
            val dbColumn = row["db_column_name"]?.jsonPrimitive?.contentOrNull
            if (dbColumn != null) {
                catalog.firstOrNull { it["db_column_name"]?.jsonPrimitive?.contentOrNull == dbColumn }
                    ?.get("id")?.jsonPrimitive?.intOrNull?.let { return it }
            }
            val name = row["name"]?.jsonPrimitive?.contentOrNull
            if (name != null) {
                catalog.firstOrNull { it["name"]?.jsonPrimitive?.contentOrNull == name }
                    ?.get("id")?.jsonPrimitive?.intOrNull?.let { return it }
            }
            return null
        }

        return rows.mapNotNull { row ->
            val id = resolveId(row) ?: return@mapNotNull null
            buildJsonObject {
                row.forEach { (key, value) -> put(key, value) }
                put("id", id)
            }
        }
    }

    /** POST /api/v1/hardware/labels — returns raw PDF bytes. */
    suspend fun generateAssetLabels(assetTags: List<String>): ByteArray? {
        val tags = assetTags.map { it.trim() }.filter { it.isNotEmpty() }
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            withContext(Dispatchers.Main) { _lastApiMessage.value = L10n.string("labels_generate_failed") }
            return null
        }
        if (tags.isEmpty()) {
            withContext(Dispatchers.Main) { _lastApiMessage.value = L10n.string("labels_no_asset_tags") }
            return null
        }
        val url = "$baseUrl/api/v1/hardware/labels"
        return runCatching {
            val result = withContext(Dispatchers.IO) {
                val jsonBody = mapToJson(mapOf("asset_tags" to buildJsonArray { tags.forEach { add(it) } }))
                    .toString().toRequestBody(jsonMediaType)
                val request = authorizedRequest(url).post(jsonBody).build()
                val response = client.newCall(request).execute()
                val bytes = response.body?.bytes() ?: ByteArray(0)
                Triple(response.code, bytes, response.header("Content-Type").orEmpty())
            }
            val (code, bytes, contentType) = result
            if (bytes.size >= 4 && String(bytes, 0, 4, Charsets.US_ASCII) == "%PDF") {
                return bytes
            }
            val json = runCatching { parseJsonObject(String(bytes, Charsets.UTF_8)) }.getOrNull()
            if (!isSnipeApiHttpSuccess(code) || isSnipeApiErrorResponse(json)) {
                val payloadError = (json?.get("payload") as? JsonObject)
                    ?.get("error_message")?.jsonPrimitive?.contentOrNull
                val message = payloadError?.takeIf { it.isNotEmpty() }
                    ?: extractApiErrorMessage(json)
                    ?: L10n.string("labels_generate_failed")
                withContext(Dispatchers.Main) { _lastApiMessage.value = message }
                return null
            }
            if (contentType.lowercase().contains("application/pdf")) return bytes
            val pdfBase64 = ((json?.get("payload") as? JsonObject)?.get("pdf") ?: json?.get("pdf"))
                ?.jsonPrimitive?.contentOrNull
            val decoded = pdfBase64?.let { runCatching { android.util.Base64.decode(it, android.util.Base64.DEFAULT) }.getOrNull() }
            if (decoded != null) return decoded
            withContext(Dispatchers.Main) { _lastApiMessage.value = L10n.string("labels_generate_failed") }
            null
        }.getOrElse { error ->
            withContext(Dispatchers.Main) { _lastApiMessage.value = error.message ?: L10n.string("labels_generate_failed") }
            null
        }
    }

    // endregion

    fun categoriesFor(type: String): List<CategoryRow> {
        val typed = _categories.value.filter {
            (it.categoryType ?: "").equals(type, ignoreCase = true)
        }
        return typed.ifEmpty { _categories.value }
    }

    suspend fun fetchAccessoryCheckedOutList(accessoryId: Int): List<AccessoryCheckedOutRow> =
        fetchAllPaginated(
            path = "/api/v1/accessories/$accessoryId/checkedout",
            serializer = AccessoryCheckedOutRow.serializer(),
        ).orEmpty()

    suspend fun fetchAccessoryDetails(accessoryId: Int): Accessory? {
        val item = fetchEntity<Accessory>("$baseUrl/api/v1/accessories/$accessoryId") ?: return null
        withContext(Dispatchers.Main) { replaceCachedItem(item) }
        return item
    }

    suspend fun fetchConsumableDetails(consumableId: Int): Consumable? {
        val item = fetchEntity<Consumable>("$baseUrl/api/v1/consumables/$consumableId") ?: return null
        withContext(Dispatchers.Main) { replaceCachedItem(item) }
        return item
    }

    suspend fun fetchComponentDetails(componentId: Int): Component? {
        val item = fetchEntity<Component>("$baseUrl/api/v1/components/$componentId") ?: return null
        withContext(Dispatchers.Main) { replaceCachedItem(item) }
        return item
    }

    suspend fun fetchConsumableCheckedOutList(consumableId: Int): List<ConsumableUserRow> =
        fetchAllPaginated(
            path = "/api/v1/consumables/$consumableId/users",
            serializer = ConsumableUserRow.serializer(),
        ).orEmpty()

    suspend fun fetchComponentAssetsList(componentId: Int): List<ComponentAssetRow> =
        fetchAllPaginated(
            path = "/api/v1/components/$componentId/assets",
            serializer = ComponentAssetRow.serializer(),
        ).orEmpty()

    suspend fun fetchUserDetails(userId: Int): User? {
        val item = fetchEntity<User>("$baseUrl/api/v1/users/$userId") ?: return null
        withContext(Dispatchers.Main) { replaceCachedUser(item) }
        return item
    }

    suspend fun fetchUserAssets(userId: Int): List<Asset> =
        fetchAllPaginated(
            path = "/api/v1/users/$userId/assets",
            serializer = Asset.serializer(),
        ).orEmpty()

    suspend fun fetchUserAccessories(
        userId: Int,
        allowAdminFallback: Boolean = true,
    ): List<Accessory> {
        val fromEndpoint = fetchAllPaginated(
            path = "/api/v1/users/$userId/accessories",
            serializer = Accessory.serializer(),
        )
        if (fromEndpoint != null) {
            if (fromEndpoint.isNotEmpty() || !allowAdminFallback) return fromEndpoint
        } else if (!allowAdminFallback) {
            return emptyList()
        }

        // Empty endpoint → scan checkouts (admin only).
        if (_accessories.value.isEmpty()) fetchAccessories()
        val candidates = _accessories.value.filter { accessory ->
            val qty = accessory.qty ?: return@filter false
            val remaining = accessory.remaining
            val checkouts = accessory.checkoutsCount
            when {
                remaining != null -> remaining < qty
                checkouts != null -> checkouts > 0
                else -> false
            }
        }
        val results = mutableListOf<Accessory>()
        for (accessory in candidates) {
            val rows = fetchAccessoryCheckedOutList(accessory.id)
            if (rows.any { row -> row.assignedTo?.matchesUser(userId) == true }) {
                results.add(accessory)
            }
        }
        return results.sortedBy { it.decodedName.lowercase() }
    }

    suspend fun fetchUserLicenses(userId: Int): List<License> =
        fetchAllPaginated(
            path = "/api/v1/users/$userId/licenses",
            serializer = License.serializer(),
        ).orEmpty()

    suspend fun fetchUserConsumables(userId: Int): List<Consumable> {
        if (_consumables.value.isEmpty()) fetchConsumables()
        val candidates = _consumables.value.filter { consumable ->
            val qty = consumable.qty ?: return@filter false
            val remaining = consumable.remaining ?: return@filter false
            remaining < qty
        }
        val results = mutableListOf<Consumable>()
        for (consumable in candidates) {
            val rows = fetchConsumableCheckedOutList(consumable.id)
            if (rows.any { it.userId == userId }) results.add(consumable)
        }
        return results.sortedBy { it.decodedName.lowercase() }
    }

    suspend fun fetchLocationAssets(locationId: Int): List<Asset> =
        fetchAllPaginated(
            path = "/api/v1/locations/$locationId/assigned/assets",
            serializer = Asset.serializer(),
        ).orEmpty()

    suspend fun fetchLocationAccessories(locationId: Int): List<Accessory> =
        fetchAssignedAccessories("/api/v1/locations/$locationId/assigned/accessories").accessories

    suspend fun fetchAssetAccessories(assetId: Int): List<Accessory> =
        fetchAssignedAccessories("/api/v1/hardware/$assetId/assigned/accessories").accessories

    suspend fun fetchAssetAccessoryCheckouts(assetId: Int): List<AccessoryCheckoutRef> =
        fetchAssignedAccessories("/api/v1/hardware/$assetId/assigned/accessories").checkouts

    suspend fun fetchLocationAccessoryCheckouts(locationId: Int): List<AccessoryCheckoutRef> =
        fetchAssignedAccessories("/api/v1/locations/$locationId/assigned/accessories").checkouts

    suspend fun fetchAssetLicenses(assetId: Int): List<License> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        return runCatching {
            val response = executeGet("$baseUrl/api/v1/hardware/$assetId/licenses")
            if (!isSnipeApiHttpSuccess(response.code)) return emptyList()
            val rows = response.json?.get("rows")?.jsonArray.orEmpty()
            val ids = mutableListOf<Int>()
            val seen = mutableSetOf<Int>()
            for (rowElement in rows) {
                val row = rowElement.jsonObject
                val licenseId = row["license"]?.jsonObject?.get("id")?.jsonPrimitive?.intOrNull ?: continue
                if (seen.add(licenseId)) ids.add(licenseId)
            }
            ids.mapNotNull { id ->
                _licenses.value.find { it.id == id } ?: fetchLicenseDetails(id)
            }
        }.getOrDefault(emptyList())
    }

    suspend fun fetchAssetAssignedAssets(assetId: Int): List<Asset> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        val results = mutableListOf<Asset>()
        val seen = mutableSetOf<Int>()

        fun appendUnique(assets: List<Asset>) {
            for (asset in assets) {
                if (seen.add(asset.id)) results.add(asset)
            }
        }

        fetchAllPaginated(
            path = "/api/v1/hardware/$assetId/assigned/assets",
            serializer = Asset.serializer(),
        )?.let { appendUnique(it) }

        fetchAllPaginated(
            path = "/api/v1/hardware",
            serializer = Asset.serializer(),
            extraQuery = mapOf(
                "assigned_to" to assetId.toString(),
                "assigned_type" to "App\\Models\\Asset",
            ),
        )?.let { appendUnique(it) }

        appendUnique(
            _assets.value.filter { asset ->
                asset.assignedTo?.isAsset == true && asset.assignedTo?.id == assetId
            },
        )

        return results.sortedBy { it.decodedAssetTag.lowercase() }
    }

    suspend fun fetchAssetComponents(assetId: Int): List<AssetAssignedComponent> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        return runCatching {
            val response = executeGet("$baseUrl/api/v1/hardware/$assetId/assigned/components")
            if (!isSnipeApiHttpSuccess(response.code)) return emptyList()
            val rows = response.json?.get("rows")?.jsonArray.orEmpty()
            val aggregated = mutableMapOf<Int, Pair<Component, Int>>()
            for (rowElement in rows) {
                val row = rowElement.jsonObject
                val qty = row["assigned_qty"]?.jsonPrimitive?.intOrNull ?: 1
                val component = row["component"]?.let { decodeJsonElementValue<Component>(it) }
                    ?: row["name"]?.let { decodeJsonElementValue<Component>(it) }
                    ?: row["id"]?.jsonPrimitive?.intOrNull?.let { componentId ->
                        _components.value.find { it.id == componentId }
                    }
                    ?: continue
                val existing = aggregated[component.id]
                if (existing != null) {
                    aggregated[component.id] = existing.first to (existing.second + qty)
                } else {
                    aggregated[component.id] = component to qty
                }
            }
            aggregated.values.map { (component, assignedQty) ->
                AssetAssignedComponent(component = component, assignedQty = assignedQty)
            }
        }.getOrDefault(emptyList())
    }

    suspend fun fetchLicenseDetails(licenseId: Int): License? {
        val item = fetchEntity<License>("$baseUrl/api/v1/licenses/$licenseId") ?: return null
        withContext(Dispatchers.Main) { replaceCachedItem(item) }
        return item
    }

    suspend fun fetchLocationDetails(locationId: Int): Location? {
        val item = fetchEntity<Location>("$baseUrl/api/v1/locations/$locationId") ?: return null
        withContext(Dispatchers.Main) { replaceCachedLocation(item) }
        return item
    }

    private suspend fun fetchAssignedAccessories(relativePath: String): AssignedAccessoriesResult {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return AssignedAccessoriesResult(emptyList(), emptyList())
        }
        return runCatching {
            val response = executeGet("$baseUrl$relativePath")
            if (!isSnipeApiHttpSuccess(response.code)) {
                return AssignedAccessoriesResult(emptyList(), emptyList())
            }
            val rows = response.json?.get("rows")?.jsonArray.orEmpty()
            val checkouts = mutableListOf<AccessoryCheckoutRef>()
            val accessoryIds = mutableListOf<Int>()
            val seen = mutableSetOf<Int>()
            for (rowElement in rows) {
                val row = rowElement.jsonObject
                val accessoryDict = row["accessory"]?.jsonObject
                    ?: row["accessories"]?.jsonObject
                    ?: row
                val accessoryId = accessoryDict["id"]?.jsonPrimitive?.intOrNull ?: continue
                val checkoutId = row["assigned_pivot_id"]?.jsonPrimitive?.intOrNull
                    ?: row["pivot_id"]?.jsonPrimitive?.intOrNull
                    ?: row["id"]?.jsonPrimitive?.intOrNull?.takeIf {
                        row["accessory"] != null || row["accessories"] != null
                    }
                checkoutId?.let { checkouts.add(AccessoryCheckoutRef(accessoryId, it)) }
                if (seen.add(accessoryId)) accessoryIds.add(accessoryId)
            }
            val accessories = accessoryIds.mapNotNull { id ->
                _accessories.value.find { it.id == id } ?: fetchAccessoryDetails(id)
            }
            AssignedAccessoriesResult(accessories, checkouts)
        }.getOrDefault(AssignedAccessoriesResult(emptyList(), emptyList()))
    }

    /** Next asset tag from server settings, or inferred from existing tags. */
    fun nextAvailableAssetTag(): String {
        val tags = _assets.value
            .map { it.assetTag.trim() }
            .filter { it.isNotEmpty() }
        val settings = _assetTagSettings.value
        if (settings != null && (settings.autoIncrementAssets || settings.prefix.isNotEmpty())) {
            return formatNextAssetTag(tags, settings)
        }
        return inferNextAssetTag(tags)
    }

    suspend fun fetchAllMaintenances(): List<AssetMaintenance>? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        val rows = fetchAllPaginated(
            path = "/api/v1/maintenances",
            serializer = AssetMaintenance.serializer(),
            extraQuery = mapOf("sort" to "start_date", "order" to "desc"),
        ) ?: return null
        val sorted = rows.sortedByDescending { it.startDate?.date.orEmpty() }
        withContext(Dispatchers.Main) { _maintenances.value = sorted }
        scheduleCacheSave()
        return sorted
    }

    suspend fun fetchMaintenances(assetId: Int): List<AssetMaintenance>? =
        fetchAllPaginated(
            path = "/api/v1/maintenances",
            serializer = AssetMaintenance.serializer(),
            extraQuery = mapOf("asset_id" to assetId.toString()),
        )

    suspend fun fetchMaintenance(id: Int): AssetMaintenance? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        return runCatching {
            decodePayloadOrRoot<AssetMaintenance>(executeGet("$baseUrl/api/v1/maintenances/$id").body)
        }.getOrNull()
    }

    private suspend fun <T> fetchSimpleList(
        path: String,
        serializer: KSerializer<T>,
        assign: suspend (List<T>) -> Unit,
    ) {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return
        val rows = fetchAllPaginated(path, serializer, reportConnectionError = true) ?: return
        withContext(Dispatchers.Main) { assign(rows) }
        scheduleCacheSave()
    }

    // endregion

    // region Hardware lookup

    /** Scan value → asset (cache, then by-tag). */
    suspend fun resolveScannedHardware(raw: String): Asset? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null

        fun resolveLocally(value: String): Asset? {
            val normalized = value.trim().lowercase()
            if (normalized.isEmpty()) return null
            return _assets.value.firstOrNull { asset ->
                asset.decodedAssetTag.trim().lowercase() == normalized ||
                    asset.decodedSerial.trim().lowercase() == normalized ||
                    asset.altBarcode?.trim()?.lowercase() == normalized
            }
        }

        resolveLocally(trimmed)?.let { return it }

        when (val link = SnipeITQRLink.parse(trimmed)) {
            is SnipeITQRLink.Hardware -> {
                _assets.value.firstOrNull { it.id == link.id }?.let { return it }
                return fetchHardwareDetails(link.id)?.also { cacheResolvedAsset(it) }
            }
            is SnipeITQRLink.HardwareByTag -> {
                resolveLocally(link.tag)?.let { return it }
                return fetchHardwareByTag(link.tag)?.also { cacheResolvedAsset(it) }
            }
            else -> Unit
        }

        return fetchHardwareByTag(trimmed)?.also { cacheResolvedAsset(it) }
    }

    private suspend fun cacheResolvedAsset(asset: Asset) {
        withContext(Dispatchers.Main) { applyUpdatedAsset(asset) }
    }

    suspend fun fetchHardwareByTag(assetTag: String): Asset? {
        val trimmed = assetTag.trim()
        if (baseUrl.isEmpty() || apiToken.isEmpty() || trimmed.isEmpty()) return null
        val pathEscaped = java.net.URLEncoder.encode(trimmed, Charsets.UTF_8.name())
            .replace("+", "%20")
        val candidates = listOf(
            "$baseUrl/api/v1/hardware/bytag/$pathEscaped",
            "$baseUrl/api/v1/hardware/bytag?asset_tag=$pathEscaped",
            "$baseUrl/api/v1/hardware/bytag?assetTag=$pathEscaped",
        )
        for (url in candidates) {
            runCatching {
                val body = executeGet(url).body
                decodePayloadOrRoot<Asset>(body)
                    ?: decodeFirstRow<Asset>(body)
            }.getOrNull()?.let { return it }
        }
        return null
    }

    suspend fun fetchHardwareDetails(assetId: Int): Asset? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        val response = executeGet("$baseUrl/api/v1/hardware/$assetId", bypassCache = true)
        if (response.code !in 200..299) return null
        val json = response.json ?: return null
        if (isSnipeApiErrorResponse(json)) return null
        decodeJsonElementValue<Asset>(json)?.takeIf { it.id == assetId }?.let { return it }
        val payload = json["payload"] as? JsonObject ?: return null
        return decodeJsonElementValue<Asset>(payload)?.takeIf { it.id == assetId }
    }

    // endregion

    // region Checkout / checkin

    suspend fun checkoutAssetCustom(assetId: Int, body: JsonObject): Boolean =
        checkoutAssetCustom(assetId, jsonObjectToMap(body))

    suspend fun checkoutAsset(assetId: Int, userId: Int): Boolean =
        checkoutAssetCustom(assetId, mapOf("assigned_user" to userId))

    suspend fun checkoutAssetCustom(assetId: Int, body: Map<String, Any?>): Boolean {
        val checkoutBody = body.toMutableMap()
        if (!checkoutBody.containsKey("status_id")) {
            deployedStatusIdForCheckout()?.let { checkoutBody["status_id"] = it }
        }
        val response = executeJsonPost("$baseUrl/api/v1/hardware/$assetId/checkout", checkoutBody)
        val result = evaluateWriteResponse(response.json, response.code, "Check-out successful!", "Check-out failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        refreshAssetInCache(assetId, response.json)
        (body["assigned_asset"] as? Number)?.toInt()?.let { refreshAssetInCache(it) }
        syncAllInBackground()
        return true
    }

    suspend fun checkinAssetCustom(assetId: Int, body: JsonObject): Boolean =
        checkinAssetCustom(assetId, jsonObjectToMap(body))

    suspend fun checkinAssetCustom(assetId: Int, body: Map<String, Any?>): Boolean {
        val response = executeJsonPost("$baseUrl/api/v1/hardware/$assetId/checkin", body)
        val result = evaluateWriteResponse(response.json, response.code, "Check-in successful!", "Check-in failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        refreshAssetInCache(assetId, response.json)
        syncAllInBackground()
        return true
    }

    suspend fun checkoutAccessory(accessoryId: Int, body: Map<String, Any?>): Boolean =
        checkoutAccessoryCustom(accessoryId, body)

    suspend fun checkoutAccessoryCustom(accessoryId: Int, body: Map<String, Any?>): Boolean {
        val response = executeJsonPost("$baseUrl/api/v1/accessories/$accessoryId/checkout", body)
        val result = evaluateWriteResponse(response.json, response.code, "Check-out successful.", "Check-out failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        refreshAccessoryInCache(accessoryId)
        syncAllInBackground()
        return true
    }

    suspend fun checkinAccessory(accessoryId: Int, checkedoutId: Int): Boolean {
        val response = executeJsonPost(
            "$baseUrl/api/v1/accessories/$checkedoutId/checkin",
            mapOf("note" to ""),
        )
        val result = evaluateWriteResponse(response.json, response.code, "Check-in successful.", "Check-in failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        refreshAccessoryInCache(accessoryId)
        syncAllInBackground()
        return true
    }

    suspend fun checkoutLicenseSeat(
        licenseId: Int,
        seatId: Int,
        userId: Int?,
        assetId: Int?,
        note: String?,
    ): String? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return "API not configured."
        when {
            userId != null -> {
                val body = mutableMapOf<String, Any?>("assigned_to" to userId)
                if (!note.isNullOrEmpty()) body["note"] = note
                putLicenseSeatUpdate(licenseId, seatId, body)?.let { return it }
            }
            assetId != null -> {
                val assetBody = mutableMapOf<String, Any?>("asset_id" to assetId)
                if (!note.isNullOrEmpty()) assetBody["note"] = note
                putLicenseSeatUpdate(licenseId, seatId, assetBody)?.let { return it }
                var asset = _assets.value.find { it.id == assetId } ?: fetchHardwareDetails(assetId)
                if (asset?.assignedTo?.isUser == true) {
                    asset.assignedTo?.id?.let { checkoutUserId ->
                        putLicenseSeatUpdate(licenseId, seatId, mapOf("assigned_to" to checkoutUserId))
                            ?.let { return it }
                    }
                }
            }
            else -> return "No assignee selected."
        }
        refreshLicenseInCache(licenseId)
        assetId?.let { refreshAssetInCache(it) }
        syncAllInBackground()
        return null
    }

    suspend fun checkinLicenseSeat(licenseId: Int, seatId: Int): String? {
        val error = putLicenseSeatUpdate(
            licenseId,
            seatId,
            mapOf("assigned_to" to null, "asset_id" to null),
        )
        if (error != null) return error
        refreshLicenseInCache(licenseId)
        syncAllInBackground()
        return null
    }

    suspend fun checkoutConsumable(consumableId: Int, userId: Int, note: String?): Boolean {
        val body = mutableMapOf<String, Any?>("assigned_to" to userId)
        if (!note.isNullOrEmpty()) body["note"] = note
        val response = executeJsonPost("$baseUrl/api/v1/consumables/$consumableId/checkout", body)
        val result = evaluateWriteResponse(response.json, response.code, "Check-out successful.", "Check-out failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        refreshConsumableInCache(consumableId)
        syncAllInBackground()
        return true
    }

    suspend fun checkoutComponent(componentId: Int, assetId: Int, quantity: Int, note: String?): Boolean {
        val body = mutableMapOf<String, Any?>(
            "assigned_to" to assetId,
            "assigned_qty" to maxOf(1, quantity),
        )
        if (!note.isNullOrEmpty()) body["note"] = note
        val response = executeJsonPost("$baseUrl/api/v1/components/$componentId/checkout", body)
        val result = evaluateWriteResponse(response.json, response.code, "Check-out successful.", "Check-out failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        refreshComponentInCache(componentId)
        syncAllInBackground()
        return true
    }

    suspend fun checkinComponent(componentId: Int, componentAssetId: Int, quantity: Int): String? {
        val response = executeJsonPost(
            "$baseUrl/api/v1/components/$componentAssetId/checkin",
            mapOf("checkin_qty" to maxOf(1, quantity)),
        )
        if (!isSnipeApiHttpSuccess(response.code)) {
            return "HTTP ${response.code}: ${response.body.take(300)}"
        }
        if (isSnipeApiErrorResponse(response.json)) {
            return extractApiErrorMessage(response.json) ?: "Check-in failed."
        }
        refreshComponentInCache(componentId)
        syncAllInBackground()
        return null
    }

    suspend fun auditAsset(
        assetTag: String,
        assetId: Int? = null,
        locationId: Int? = null,
        updateLocation: Boolean = false,
        nextAuditDate: String? = null,
        note: String? = null,
        image: UploadFile? = null,
    ): Boolean {
        val trimmedTag = assetTag.trim()
        if (baseUrl.isEmpty() || apiToken.isEmpty() || trimmedTag.isEmpty()) return false
        val url = "$baseUrl/api/v1/hardware/audit"
        val body = mutableMapOf<String, Any?>("asset_tag" to trimmedTag)
        if (locationId != null && locationId != 0) body["location_id"] = locationId
        if (updateLocation) body["update_location"] = true
        nextAuditDate?.trim()?.takeIf { it.isNotEmpty() }?.let { body["next_audit_date"] = it }
        note?.trim()?.takeIf { it.isNotEmpty() }?.let { body["note"] = it }

        val response = if (image != null) {
            val multipart = sendHardwareMultipart(url, "POST", body, image)
            val multipartOk = isSnipeApiHttpSuccess(multipart.code) && !isSnipeApiErrorResponse(multipart.json)
            if (multipartOk) {
                multipart
            } else {
                // Same fallback as maintenance/asset image uploads.
                body["image_source"] = image.toBase64ImageSource()
                executeJsonPost(url, body)
            }
        } else {
            executeJsonPost(url, body)
        }

        if (!isSnipeApiHttpSuccess(response.code) || isSnipeApiErrorResponse(response.json)) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = extractApiErrorMessage(response.json) ?: "Audit failed."
            }
            return false
        }
        if (assetId != null && !nextAuditDate.isNullOrBlank()) {
            updateAsset(assetId, mapOf("next_audit_date" to nextAuditDate.trim()))
        }
        return true
    }

    // endregion

    // region CRUD (JSON body)

    /** Creates an asset; when [image] is set, uploads it as `image` via multipart. */
    suspend fun createAsset(body: Map<String, Any?>, image: UploadFile? = null): CreateResult {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return CreateResult(false, message = "API not configured.")
        }
        val url = "$baseUrl/api/v1/hardware"
        val response = if (image != null) {
            sendHardwareMultipart(url, "POST", body, image)
        } else {
            executeJsonPost(url, body)
        }
        if (!isSnipeApiHttpSuccess(response.code)) {
            return CreateResult(false, message = "HTTP ${response.code}: ${response.body.take(300)}")
        }
        if (isSnipeApiErrorResponse(response.json)) {
            return CreateResult(false, message = extractApiErrorMessage(response.json) ?: "Create failed.")
        }
        val newId = idFromPayload(response.json)
        newId?.let { assetId ->
            fetchHardwareDetails(assetId)?.let { withContext(Dispatchers.Main) { applyUpdatedAsset(it) } }
        }
        return CreateResult(true, id = newId)
    }

    /** Update asset; optional image upload or `image_delete=1`. */
    suspend fun updateAsset(assetId: Int, body: Map<String, Any?>, image: UploadFile? = null): Boolean {
        val url = "$baseUrl/api/v1/hardware/$assetId"
        val wantsImageChange = image != null || body["image_delete"] == 1
        val response = if (wantsImageChange) {
            sendHardwareMultipart(url, "PATCH", body, image)
        } else {
            executeJsonPatch(url, body)
        }
        val result = evaluateWriteResponse(response.json, response.code, "Saved.", "Save failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        withContext(Dispatchers.Main) {
            response.json?.let { mergeAssetFromResponseJson(it) }
        }
        if (wantsImageChange) {
            fetchHardwareDetails(assetId)?.let { withContext(Dispatchers.Main) { applyUpdatedAsset(it) } }
        }
        return true
    }

    suspend fun createAccessory(body: Map<String, Any?>): CreateResult =
        createEntity("$baseUrl/api/v1/accessories", body) { scope.launch { fetchAccessories() } }

    suspend fun updateAccessory(accessoryId: Int, body: Map<String, Any?>): Boolean =
        patchEntity("$baseUrl/api/v1/accessories/$accessoryId", body) {
            val notes = body["notes"] as? String
            withContext(Dispatchers.Main) {
                val current = _accessories.value.firstOrNull { it.id == accessoryId }
                if (current != null && notes != null) {
                    replaceCachedItem(current.copy(notes = notes.takeIf { it.isNotBlank() }))
                }
            }
            refreshAccessoryInCache(accessoryId)
            fetchAccessories()
        }

    suspend fun createUser(body: Map<String, Any?>): CreateResult =
        createEntity("$baseUrl/api/v1/users", body) { scope.launch { fetchUsers() } }

    suspend fun updateUser(userId: Int, body: Map<String, Any?>): Boolean {
        val response = executeJsonPatch("$baseUrl/api/v1/users/$userId", body)
        val result = evaluateWriteResponse(response.json, response.code, "Saved.", "Save failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        decodePayloadOrRoot<User>(response.body)?.let { updated ->
            withContext(Dispatchers.Main) { replaceCachedUser(updated) }
        }
        scope.launch { fetchUsers() }
        return true
    }

    suspend fun createLocation(body: Map<String, Any?>): CreateResult =
        createEntity("$baseUrl/api/v1/locations", body) { scope.launch { fetchLocations() } }

    suspend fun updateLocation(locationId: Int, body: Map<String, Any?>): Boolean {
        val response = executeJsonPatch("$baseUrl/api/v1/locations/$locationId", body)
        val result = evaluateWriteResponse(response.json, response.code, "Saved.", "Save failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        decodePayloadOrRoot<Location>(response.body)?.let { updated ->
            withContext(Dispatchers.Main) { replaceCachedLocation(updated) }
        }
        scope.launch { fetchLocations() }
        return true
    }

    suspend fun createLicense(body: Map<String, Any?>): CreateResult =
        createEntity("$baseUrl/api/v1/licenses", body) { scope.launch { fetchLicenses() } }

    suspend fun updateLicense(licenseId: Int, body: Map<String, Any?>): String? {
        val response = executeJsonPatch("$baseUrl/api/v1/licenses/$licenseId", body)
        if (!isSnipeApiHttpSuccess(response.code)) {
            return "HTTP ${response.code}: ${response.body.take(300)}"
        }
        if (isSnipeApiErrorResponse(response.json)) {
            return extractApiErrorMessage(response.json) ?: "Save failed."
        }
        decodePayloadOrRoot<License>(response.body)?.let { updated ->
            withContext(Dispatchers.Main) { replaceCachedItem(updated) }
        }
        scope.launch { fetchLicenses() }
        return null
    }

    suspend fun createConsumable(body: Map<String, Any?>): CreateResult =
        createEntity("$baseUrl/api/v1/consumables", body) { scope.launch { fetchConsumables() } }

    suspend fun updateConsumable(consumableId: Int, body: Map<String, Any?>): Boolean =
        patchEntity("$baseUrl/api/v1/consumables/$consumableId", body) {
            refreshConsumableInCache(consumableId)
            fetchConsumables()
        }

    suspend fun createComponent(body: Map<String, Any?>): CreateResult =
        createEntity("$baseUrl/api/v1/components", body) { scope.launch { fetchComponents() } }

    suspend fun updateComponent(componentId: Int, body: Map<String, Any?>): Boolean =
        patchEntity("$baseUrl/api/v1/components/$componentId", body) {
            refreshComponentInCache(componentId)
            fetchComponents()
        }

    suspend fun createMaintenance(body: Map<String, Any?>, image: UploadFile? = null): Boolean =
        createMaintenanceReturningId(body, image) != null

    /** New maintenance id, or null on failure. */
    suspend fun createMaintenanceReturningId(body: Map<String, Any?>, image: UploadFile? = null): Int? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        val url = "$baseUrl/api/v1/maintenances"
        val mutableBody = withMirroredMaintenanceCompletion(body).toMutableMap()

        if (image != null) {
            val multipart = sendHardwareMultipart(url, "POST", mutableBody, image)
            val multipartResult = evaluateWriteResponse(
                multipart.json,
                multipart.code,
                "Maintenance created.",
                "Create failed.",
            )
            if (multipartResult.success) {
                withContext(Dispatchers.Main) { _lastApiMessage.value = multipartResult.message }
                scope.launch { fetchAllMaintenances() }
                return idFromPayload(multipart.json) ?: decodePayloadOrRoot<AssetMaintenance>(multipart.body)?.id
            }
            // Multipart image failed — retry via image_source.
            mutableBody["image_source"] = image.toBase64ImageSource()
        }

        val response = executeJsonPost(url, mutableBody)
        val result = evaluateWriteResponse(response.json, response.code, "Maintenance created.", "Create failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return null
        scope.launch { fetchAllMaintenances() }
        return idFromPayload(response.json) ?: decodePayloadOrRoot<AssetMaintenance>(response.body)?.id
    }

    /**
     * Update maintenance. May return a new id when the image changes
     * (API has no in-place image update).
     */
    suspend fun updateMaintenance(
        id: Int,
        assetId: Int,
        body: Map<String, Any?>,
        image: UploadFile? = null,
        imageDelete: Boolean = false,
        wasCompleted: Boolean = false,
    ): Int? {
        val wantsImageChange = image != null || imageDelete
        if (wantsImageChange) {
            return updateMaintenanceRecreatingForImage(
                id = id,
                assetId = assetId,
                body = body,
                image = if (imageDelete && image == null) null else image,
                wasCompleted = wasCompleted,
            )
        }
        val response = executeJsonPut(
            "$baseUrl/api/v1/maintenances/$id",
            withMirroredMaintenanceCompletion(body),
        )
        val result = evaluateWriteResponse(response.json, response.code, "Changes saved.", "Update failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return null
        decodePayloadOrRoot<AssetMaintenance>(response.body)?.let { record ->
            withContext(Dispatchers.Main) { replaceCachedMaintenance(record) }
        }
        scope.launch { fetchAllMaintenances() }
        return id
    }

    /** Boolean wrapper for callers that ignore the returned id. */
    suspend fun updateMaintenance(id: Int, body: Map<String, Any?>): Boolean {
        val assetId = body["asset_id"] as? Int
            ?: _maintenances.value.firstOrNull { it.id == id }?.assetId
            ?: return false
        return updateMaintenance(id = id, assetId = assetId, body = body) != null
    }

    private suspend fun updateMaintenanceRecreatingForImage(
        id: Int,
        assetId: Int,
        body: Map<String, Any?>,
        image: UploadFile?,
        wasCompleted: Boolean,
    ): Int? {
        val name = (body["name"] as? String)?.trim().orEmpty()
        val startDate = (body["start_date"] as? String)?.trim().orEmpty()
        if (name.isEmpty() || startDate.isEmpty() || assetId <= 0) {
            withContext(Dispatchers.Main) { _lastApiMessage.value = L10n.string("error") }
            return null
        }
        val createBody = body.toMutableMap()
        createBody["asset_id"] = assetId
        createBody.remove("image_delete")
        val newId = createMaintenanceReturningId(createBody, image) ?: return null
        if (wasCompleted) {
            completeMaintenance(newId)
        }
        if (!deleteMaintenance(id)) return null
        return newId
    }

    suspend fun deleteMaintenance(id: Int): Boolean {
        val response = executeDeleteWithFallback("$baseUrl/api/v1/maintenances/$id")
        val result = evaluateWriteResponse(response.json, response.code, "Deleted.", "Delete failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (result.success) scope.launch { fetchAllMaintenances() }
        return result.success
    }

    suspend fun deleteAsset(assetId: Int): Boolean {
        val asset = _assets.value.find { it.id == assetId } ?: fetchHardwareDetails(assetId)

        val childAssets = fetchAssetAssignedAssets(assetId)
        for (child in childAssets) {
            val ok = checkinAssetCustom(
                assetId = child.id,
                body = mapOf("note" to "Auto check-in before parent asset delete"),
            )
            if (!ok) {
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                }
                return false
            }
        }

        if (asset?.assignedTo != null) {
            val checkedIn = checkinAssetCustom(
                assetId = assetId,
                body = mapOf("note" to "Auto check-in before delete"),
            )
            if (!checkedIn) {
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                }
                return false
            }
        }

        if (!prepareAssetRelationsForDelete(assetId)) return false

        val ok = performDelete(
            path = "/api/v1/hardware/$assetId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _assets.value = _assets.value.filter { it.id != assetId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(_lastApiMessage.value)
                    ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    suspend fun deleteAccessory(accessoryId: Int): Boolean {
        val rows = fetchAccessoryCheckedOutList(accessoryId)
        for (row in rows) {
            val checkedoutId = row.id ?: continue
            val ok = checkinAccessory(accessoryId = accessoryId, checkedoutId = checkedoutId)
            if (!ok) {
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                }
                return false
            }
        }

        val ok = performDelete(
            path = "/api/v1/accessories/$accessoryId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _accessories.value = _accessories.value.filter { it.id != accessoryId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(_lastApiMessage.value)
                    ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    suspend fun deleteComponent(componentId: Int): Boolean {
        repeat(5) {
            val rows = fetchComponentAssetsList(componentId)
            if (rows.isEmpty()) return@repeat

            var checkedAny = false
            for (row in rows) {
                val pivotId = row.assignedPivotId
                if (pivotId == null) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = L10n.string("delete_component_missing_pivot")
                    }
                    return false
                }
                val qty = maxOf(1, row.assignedQty ?: 1)
                val error = checkinComponent(
                    componentId = componentId,
                    componentAssetId = pivotId,
                    quantity = qty,
                )
                if (error != null) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(error)
                    }
                    return false
                }
                checkedAny = true
            }
            if (!checkedAny) return@repeat
        }

        val remaining = fetchComponentAssetsList(componentId)
        if (remaining.isNotEmpty()) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = L10n.string("delete_component_still_checked_out")
            }
            return false
        }

        val ok = performDelete(
            path = "/api/v1/components/$componentId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _components.value = _components.value.filter { it.id != componentId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(
                    _lastApiMessage.value,
                    DeleteFailureKind.Component,
                ) ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    suspend fun deleteConsumable(consumableId: Int): Boolean {
        val ok = performDelete(
            path = "/api/v1/consumables/$consumableId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _consumables.value = _consumables.value.filter { it.id != consumableId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(
                    _lastApiMessage.value,
                    DeleteFailureKind.Consumable,
                ) ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    suspend fun deleteLicense(licenseId: Int): Boolean {
        val seats = fetchLicenseSeats(licenseId)
        for (seat in seats) {
            if (seat.assignedUser == null && seat.assignedAsset == null) continue
            val error = checkinLicenseSeat(licenseId = licenseId, seatId = seat.id)
            if (error != null) {
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = localizedDeleteCheckinFailure(error)
                }
                return false
            }
        }

        val ok = performDelete(
            path = "/api/v1/licenses/$licenseId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _licenses.value = _licenses.value.filter { it.id != licenseId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(_lastApiMessage.value)
                    ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    suspend fun deleteUser(userId: Int): Boolean {
        val me = _currentUser.value
        if (me?.id == userId) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = L10n.string("delete_user_cannot_delete_yourself")
            }
            return false
        }

        val userAssets = fetchUserAssets(userId)
        for (asset in userAssets) {
            if (!prepareAssetRelationsForDelete(asset.id)) return false
            val ok = checkinAssetCustom(
                assetId = asset.id,
                body = mapOf("note" to "Auto check-in before user delete"),
            )
            if (!ok) {
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                }
                return false
            }
        }

        val userAccessories = fetchUserAccessories(userId)
        for (accessory in userAccessories) {
            val rows = fetchAccessoryCheckedOutList(accessory.id)
            for (row in rows) {
                if (row.assignedTo?.id != userId) continue
                val checkedoutId = row.id ?: continue
                val ok = checkinAccessory(accessoryId = accessory.id, checkedoutId = checkedoutId)
                if (!ok) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                    }
                    return false
                }
            }
        }

        val userLicenses = fetchUserLicenses(userId)
        for (license in userLicenses) {
            val licenseSeats = fetchLicenseSeats(license.id)
            for (seat in licenseSeats) {
                if (seat.assignedUser?.id != userId) continue
                val error = checkinLicenseSeat(licenseId = license.id, seatId = seat.id)
                if (error != null) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(error)
                    }
                    return false
                }
            }
        }

        val ok = performDelete(
            path = "/api/v1/users/$userId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _users.value = _users.value.filter { it.id != userId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(
                    _lastApiMessage.value,
                    DeleteFailureKind.User,
                ) ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    suspend fun deleteLocation(locationId: Int): Boolean {
        val locationAssets = fetchLocationAssets(locationId)
        for (asset in locationAssets) {
            if (!prepareAssetRelationsForDelete(asset.id)) return false
            val ok = checkinAssetCustom(
                assetId = asset.id,
                body = mapOf("note" to "Auto check-in before location delete"),
            )
            if (!ok) {
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                }
                return false
            }
        }

        val locationAccessories = fetchLocationAccessoryCheckouts(locationId)
        if (locationAccessories.isNotEmpty()) {
            for (item in locationAccessories) {
                val ok = checkinAccessory(accessoryId = item.accessoryId, checkedoutId = item.checkoutId)
                if (!ok) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                    }
                    return false
                }
            }
        } else {
            val accessories = fetchLocationAccessories(locationId)
            for (accessory in accessories) {
                val rows = fetchAccessoryCheckedOutList(accessory.id)
                for (row in rows) {
                    if (row.assignedTo?.id != locationId) continue
                    val checkedoutId = row.id ?: continue
                    val ok = checkinAccessory(accessoryId = accessory.id, checkedoutId = checkedoutId)
                    if (!ok) {
                        withContext(Dispatchers.Main) {
                            _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                        }
                        return false
                    }
                }
            }
        }

        val ok = performDelete(
            path = "/api/v1/locations/$locationId",
            onSuccess = {
                withContext(Dispatchers.Main) {
                    _locations.value = _locations.value.filter { it.id != locationId }
                    scheduleCacheSave()
                }
            },
        )
        if (!ok) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = userFacingDeleteMessage(
                    _lastApiMessage.value,
                    DeleteFailureKind.Location,
                ) ?: L10n.string("delete_failed")
            }
        }
        return ok
    }

    private suspend fun prepareAssetRelationsForDelete(assetId: Int): Boolean {
        val directCheckouts = fetchAssetAccessoryCheckouts(assetId)
        if (directCheckouts.isNotEmpty()) {
            for (item in directCheckouts) {
                val ok = checkinAccessory(accessoryId = item.accessoryId, checkedoutId = item.checkoutId)
                if (!ok) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                    }
                    return false
                }
            }
        } else {
            val accessories = fetchAssetAccessories(assetId)
            for (accessory in accessories) {
                val rows = fetchAccessoryCheckedOutList(accessory.id)
                for (row in rows) {
                    if (row.assignedTo?.id != assetId) continue
                    val checkedoutId = row.id ?: continue
                    val ok = checkinAccessory(accessoryId = accessory.id, checkedoutId = checkedoutId)
                    if (!ok) {
                        withContext(Dispatchers.Main) {
                            _lastApiMessage.value = localizedDeleteCheckinFailure(_lastApiMessage.value)
                        }
                        return false
                    }
                }
            }
        }

        val components = fetchAssetComponents(assetId)
        for (item in components) {
            val rows = fetchComponentAssetsList(componentId = item.component.id)
            for (row in rows) {
                if (row.assetId != assetId) continue
                val pivotId = row.assignedPivotId ?: continue
                val error = checkinComponent(
                    componentId = item.component.id,
                    componentAssetId = pivotId,
                    quantity = maxOf(1, row.assignedQty ?: item.assignedQty),
                )
                if (error != null) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(error)
                    }
                    return false
                }
            }
        }

        val licenses = fetchAssetLicenses(assetId)
        for (license in licenses) {
            val licenseSeats = fetchLicenseSeats(license.id)
            for (seat in licenseSeats) {
                if (seat.assignedAsset?.id != assetId) continue
                val error = checkinLicenseSeat(licenseId = license.id, seatId = seat.id)
                if (error != null) {
                    withContext(Dispatchers.Main) {
                        _lastApiMessage.value = localizedDeleteCheckinFailure(error)
                    }
                    return false
                }
            }
        }

        return true
    }

    private suspend fun performDelete(path: String, onSuccess: suspend () -> Unit): Boolean {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            withContext(Dispatchers.Main) {
                _lastApiMessage.value = L10n.string("settings_not_configured")
            }
            return false
        }
        val url = "$baseUrl$path"
        val response = executeDeleteWithFallback(url)
        val result = evaluateWriteResponse(
            json = response.json,
            httpStatus = response.code,
            defaultSuccessMessage = L10n.string("delete_success"),
            defaultFailureMessage = L10n.string("delete_failed"),
        )
        val message = if (!result.success) {
            extractApiErrorMessage(response.json)?.takeIf { it.isNotEmpty() } ?: result.message
        } else {
            result.message
        }
        withContext(Dispatchers.Main) { _lastApiMessage.value = message }
        if (!result.success) return false
        onSuccess()
        syncAllInBackground()
        return true
    }

    private fun localizedDeleteCheckinFailure(message: String?): String {
        val trimmed = message?.trim().orEmpty()
        if (trimmed.isNotEmpty()) return trimmed
        return L10n.string("delete_checkin_failed")
    }

    enum class DeleteFailureKind {
        Generic,
        Location,
        Management,
        Component,
        Consumable,
        User,
    }

    fun userFacingDeleteMessage(
        raw: String?,
        kind: DeleteFailureKind = DeleteFailureKind.Generic,
    ): String? {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return L10n.string("delete_failed")
        val lower = trimmed.lowercase()

        if (kind == DeleteFailureKind.User) {
            if ("yourself" in lower || "jezelf" in lower) {
                return L10n.string("delete_user_cannot_delete_yourself")
            }
            if ("manages" in lower || "managed" in lower || "manager" in lower) {
                return L10n.string("delete_user_still_manager")
            }
        }

        val looksCheckedOut =
            "still checked out" in lower ||
                "error_qty" in lower ||
                "check them in" in lower ||
                (kind == DeleteFailureKind.Component && "checked out" in lower)
        if (looksCheckedOut || (kind == DeleteFailureKind.Component && (
                "associated" in lower || "cannot be deleted" in lower
                ))
        ) {
            return L10n.string("delete_component_still_checked_out")
        }

        val looksInUse =
            "associated" in lower ||
                "cannot be deleted" in lower ||
                "can't be deleted" in lower ||
                "in use" in lower ||
                "still has" in lower ||
                "has assets" in lower ||
                "has users" in lower ||
                "has models" in lower ||
                "has accessories" in lower ||
                "has license" in lower ||
                "delete_disabled" in lower ||
                "assoc_" in lower ||
                "assoc " in lower ||
                "gekoppeld" in lower ||
                "in gebruik" in lower ||
                "niet verwijderd" in lower ||
                "check their" in lower ||
                "check it in" in lower

        if (looksInUse) {
            return when (kind) {
                DeleteFailureKind.Location -> L10n.string("delete_still_in_use_location")
                DeleteFailureKind.Management -> L10n.string("mgmt_delete_still_in_use")
                DeleteFailureKind.Component -> L10n.string("delete_component_still_checked_out")
                DeleteFailureKind.Consumable -> L10n.string("delete_consumable_failed")
                DeleteFailureKind.User -> L10n.string("delete_user_still_in_use")
                DeleteFailureKind.Generic -> L10n.string("delete_still_in_use")
            }
        }
        return trimmed
    }

    suspend fun completeMaintenance(id: Int, note: String? = null): Boolean {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return false
        val body = note?.trim()?.takeIf { it.isNotEmpty() }?.let { mapOf("note" to it) } ?: emptyMap()
        val response = executeJsonPost("$baseUrl/api/v1/maintenances/$id/complete", body)
        val result = evaluateWriteResponse(response.json, response.code, "Onderhoud afgerond.", "Afronden mislukt.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (result.success) scope.launch { fetchAllMaintenances() }
        return result.success
    }

    suspend fun fetchMaintenanceTypes() {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return
        val probe = executeGet("$baseUrl/api/v1/maintenance-types?limit=1&offset=0")
        if (probe.code == 404) {
            withContext(Dispatchers.Main) {
                _maintenanceTypesMode.value = MaintenanceTypesMode.Legacy
                _maintenanceTypes.value = emptyList()
            }
            return
        }
        if (!isSnipeApiHttpSuccess(probe.code)) return
        withContext(Dispatchers.Main) { _maintenanceTypesMode.value = MaintenanceTypesMode.TypeIds }
        val rows = fetchAllPaginated("/api/v1/maintenance-types", MaintenanceType.serializer()) ?: return
        withContext(Dispatchers.Main) {
            _maintenanceTypes.value = rows.sortedBy { it.name.lowercase() }
        }
    }

    suspend fun managementFetchRows(path: String): Pair<List<JsonObject>?, String?> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return null to "API niet geconfigureerd."
        }
        val collected = mutableListOf<JsonObject>()
        var offset = 0
        val limit = 200
        while (true) {
            val url = "$baseUrl$path?limit=$limit&offset=$offset"
            val response = try {
                executeGet(url)
            } catch (e: Exception) {
                return null to localizedConnectionFailureMessage(e)
            }
            if (!isSnipeApiHttpSuccess(response.code)) {
                return null to (extractApiErrorMessage(response.json) ?: "HTTP ${response.code}")
            }
            if (isSnipeApiErrorResponse(response.json)) {
                return null to (extractApiErrorMessage(response.json) ?: "Verzoek mislukt.")
            }
            val json = response.json ?: return null to "Ongeldig antwoord."
            val rows = json["rows"]?.jsonArray.orEmpty()
            rows.forEach { element ->
                if (element is JsonObject) collected.add(element)
            }
            val total = json["total"]?.jsonPrimitive?.intOrNull
            if (rows.size < limit) break
            if (total != null && collected.size >= total) break
            if (rows.isEmpty()) break
            offset += limit
            delay(PAGE_DELAY_MS)
        }
        return collected to null
    }

    suspend fun managementFetchRow(path: String, id: Int): JsonObject? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        return runCatching {
            val response = executeGet("$baseUrl$path/$id")
            if (!isSnipeApiHttpSuccess(response.code)) return null
            val json = response.json ?: return null
            when (val payload = json["payload"]) {
                is JsonObject -> payload
                else -> json.takeIf { it["id"]?.jsonPrimitive?.intOrNull != null }
            }
        }.getOrNull()
    }

    suspend fun managementCreate(path: String, body: Map<String, Any?>): ManagementWriteResult =
        managementWrite("$baseUrl$path", "POST", body)

    suspend fun managementUpdate(path: String, id: Int, body: Map<String, Any?>): ManagementWriteResult =
        managementWrite("$baseUrl$path/$id", "PATCH", body)

    suspend fun managementDelete(path: String, id: Int): ManagementWriteResult =
        managementWrite("$baseUrl$path/$id", "DELETE", null)

    private suspend fun managementWrite(
        url: String,
        method: String,
        body: Map<String, Any?>?,
    ): ManagementWriteResult {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return ManagementWriteResult(false, "API niet geconfigureerd.")
        }
        suspend fun send(httpMethod: String, formOverride: String? = null): HttpResult {
            if (formOverride != null) {
                return withContext(Dispatchers.IO) {
                    val requestBody = "_method=$formOverride".toRequestBody("application/x-www-form-urlencoded".toMediaType())
                    val request = authorizedRequest(url).method(httpMethod, requestBody).build()
                    val response = client.newCall(request).execute()
                    val responseBody = response.body?.string().orEmpty()
                    HttpResult(response.code, responseBody, parseJsonObject(responseBody))
                }
            }
            return when (httpMethod) {
                "POST" -> executeJsonPost(url, body.orEmpty())
                "PATCH" -> executeJsonPatch(url, body.orEmpty())
                "DELETE" -> executeDelete(url)
                else -> executeJsonRequest(httpMethod, url, body.orEmpty())
            }
        }

        var response = send(method)
        if (method == "DELETE" && response.code == 405) {
            response = send("POST", formOverride = "DELETE")
        }
        val success = isSnipeApiHttpSuccess(response.code) && !isSnipeApiErrorResponse(response.json)
        val message = extractApiErrorMessage(response.json)
            ?: if (success) {
                when (method) {
                    "POST" -> "Aangemaakt."
                    "DELETE" -> "Verwijderd."
                    else -> "Opgeslagen."
                }
            } else {
                "Opslaan mislukt."
            }
        val newId = if (success && method == "POST") idFromPayload(response.json) else null
        return ManagementWriteResult(success, message, newId)
    }

    suspend fun fetchLicenseSeats(licenseId: Int): List<LicenseSeatRow> =
        fetchAllPaginated(
            path = "/api/v1/licenses/$licenseId/seats",
            serializer = LicenseSeatRow.serializer(),
        ).orEmpty()

    suspend fun fetchActivityPage(
        limit: Int = 50,
        offset: Int = 0,
        order: String = "desc",
    ): List<Activity> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        val url = "$baseUrl/api/v1/reports/activity?limit=$limit&offset=$offset&order=$order"
        return runCatching {
            SnipeJson.decodeFromString(ActivityResponse.serializer(), executeGet(url).body).rows.orEmpty()
        }.getOrDefault(emptyList())
    }

    suspend fun fetchActivityForItem(
        itemType: String,
        itemId: Int,
        limit: Int = 50,
        offset: Int = 0,
        order: String = "desc",
    ): List<Activity> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        val url = "$baseUrl/api/v1/reports/activity?limit=$limit&offset=$offset" +
            "&item_type=$itemType&item_id=$itemId&order=$order"
        return runCatching {
            SnipeJson.decodeFromString(ActivityResponse.serializer(), executeGet(url).body).rows.orEmpty()
        }.getOrDefault(emptyList())
    }

    suspend fun fetchAssetFiles(assetId: Int): List<AssetFile> {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return emptyList()
        val url = "$baseUrl/api/v1/hardware/$assetId/files" +
            "?limit=500&offset=0&sort=created_at&order=desc"
        return runCatching {
            SnipeJson.decodeFromString(AssetFileResponse.serializer(), executeGet(url).body).rows.orEmpty()
        }.getOrDefault(emptyList())
    }

    /** GET …/files/{fileId} (Bearer). */
    suspend fun downloadObjectFile(
        objectType: String,
        objectId: Int,
        fileId: Int,
        preferredFilename: String,
    ): java.io.File? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        val type = apiFilesObjectType(objectType)
        return downloadToCache(
            url = "$baseUrl/api/v1/$type/$objectId/files/$fileId",
            preferredFilename = preferredFilename,
            fileId = fileId,
        )
    }

    /** Authenticated GET of a file URL. */
    suspend fun downloadRemoteFile(url: String, preferredFilename: String): java.io.File? {
        if (apiToken.isEmpty()) return null
        val resolved = when {
            url.startsWith("http://", ignoreCase = true) ||
                url.startsWith("https://", ignoreCase = true) -> url
            url.startsWith("/") -> "${baseUrl.trimEnd('/')}$url"
            else -> "${baseUrl.trimEnd('/')}/$url"
        }
        return downloadToCache(resolved, preferredFilename, fileId = 0)
    }

    suspend fun refreshHardwareAfterWrite(assetId: Int) {
        refreshAssetInCache(assetId)
    }

    /** POST /hardware/{id}/files (`file[]` multipart). */
    suspend fun uploadAssetFiles(assetId: Int, files: List<UploadFile>, notes: String? = null): Boolean {
        if (files.isEmpty()) return true
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return false
        return withContext(Dispatchers.IO) {
            runCatching {
                val multipartBuilder = MultipartBody.Builder().setType(MultipartBody.FORM)
                notes?.trim()?.takeIf { it.isNotEmpty() }?.let { multipartBuilder.addFormDataPart("notes", it) }
                files.forEach { file ->
                    val mediaType = file.mimeType.toMediaTypeOrNull()
                    multipartBuilder.addFormDataPart(
                        "file[]",
                        file.filename,
                        file.data.toRequestBody(mediaType),
                    )
                }
                val url = "$baseUrl/api/v1/hardware/$assetId/files"
                val request = authorizedRequest(url).post(multipartBuilder.build()).build()
                val httpResponse = client.newCall(request).execute()
                val body = httpResponse.body?.string().orEmpty()
                val json = parseJsonObject(body)
                val result = evaluateWriteResponse(
                    json,
                    httpResponse.code,
                    L10n.string("file_upload_success"),
                    L10n.string("file_upload_failed"),
                )
                withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
                result.success
            }.getOrElse { error ->
                withContext(Dispatchers.Main) {
                    _lastApiMessage.value = "${L10n.string("file_upload_failed")}: ${error.message.orEmpty()}"
                }
                false
            }
        }
    }

    /** DELETE /hardware/{id}/files/{fileId}/delete. */
    suspend fun deleteAssetFile(assetId: Int, fileId: Int): Boolean {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return false
        val url = "$baseUrl/api/v1/hardware/$assetId/files/$fileId/delete"
        val response = executeDelete(url)
        val result = evaluateWriteResponse(
            response.json,
            response.code,
            L10n.string("file_delete_success"),
            L10n.string("file_delete_failed"),
        )
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        return result.success
    }

    // endregion

    // region Cache refresh helpers

    private suspend fun refreshAssetInCache(assetId: Int, responseJson: JsonObject? = null) {
        synchronized(assetsPendingDetailRefresh) { assetsPendingDetailRefresh.add(assetId) }
        if (responseJson != null) {
            withContext(Dispatchers.Main) { runCatching { mergeAssetFromResponseJson(responseJson) } }
        }
        fetchHardwareDetails(assetId)?.let { withContext(Dispatchers.Main) { applyUpdatedAsset(it) } }
    }

    private suspend fun reconcilePendingAssetDetails() {
        val ids = synchronized(assetsPendingDetailRefresh) { assetsPendingDetailRefresh.toSet() }
        if (ids.isEmpty()) return
        ids.forEach { id ->
            fetchHardwareDetails(id)?.let { withContext(Dispatchers.Main) { applyUpdatedAsset(it) } }
        }
        synchronized(assetsPendingDetailRefresh) { assetsPendingDetailRefresh.removeAll(ids) }
    }

    private fun applyUpdatedAsset(asset: Asset) {
        val list = _assets.value.toMutableList()
        val idx = list.indexOfFirst { it.id == asset.id }
        if (idx >= 0) list[idx] = asset else list.add(0, asset)
        _assets.value = list
        scheduleCacheSave()
    }

    private suspend fun refreshAccessoryInCache(accessoryId: Int) {
        fetchEntity<Accessory>("$baseUrl/api/v1/accessories/$accessoryId")?.let {
            withContext(Dispatchers.Main) { replaceCachedItem(it) }
        }
    }

    private suspend fun refreshComponentInCache(componentId: Int) {
        fetchEntity<Component>("$baseUrl/api/v1/components/$componentId")?.let {
            withContext(Dispatchers.Main) { replaceCachedItem(it) }
        }
    }

    private suspend fun refreshConsumableInCache(consumableId: Int) {
        fetchEntity<Consumable>("$baseUrl/api/v1/consumables/$consumableId")?.let {
            withContext(Dispatchers.Main) { replaceCachedItem(it) }
        }
    }

    private suspend fun refreshLicenseInCache(licenseId: Int) {
        fetchEntity<License>("$baseUrl/api/v1/licenses/$licenseId")?.let {
            withContext(Dispatchers.Main) { replaceCachedItem(it) }
        }
    }

    private suspend fun deployedStatusIdForCheckout(): Int? {
        if (_statusLabels.value.isEmpty()) fetchStatusLabels()
        return _statusLabels.value.firstOrNull {
            it.statusMeta?.lowercase() == "deployed"
        }?.id
    }

    private fun replaceCachedItem(item: Accessory) {
        val list = _accessories.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _accessories.value = list
        scheduleCacheSave()
    }

    private fun replaceCachedItem(item: Component) {
        val list = _components.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _components.value = list
        scheduleCacheSave()
    }

    private fun replaceCachedItem(item: Consumable) {
        val list = _consumables.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _consumables.value = list
        scheduleCacheSave()
    }

    private fun replaceCachedItem(item: License) {
        val list = _licenses.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _licenses.value = list
        scheduleCacheSave()
    }

    private fun replaceCachedUser(item: User) {
        val list = _users.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _users.value = list
        if (_currentUser.value?.id == item.id) _currentUser.value = item
        scheduleCacheSave()
    }

    private fun replaceCachedLocation(item: Location) {
        val list = _locations.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _locations.value = list
        scheduleCacheSave()
    }

    private fun replaceCachedMaintenance(item: AssetMaintenance) {
        val list = _maintenances.value.toMutableList()
        val idx = list.indexOfFirst { it.id == item.id }
        if (idx >= 0) list[idx] = item else list.add(0, item)
        _maintenances.value = list
        scheduleCacheSave()
    }

    private fun mergeAssetFromResponseJson(json: JsonObject) {
        val payload = json["payload"] as? JsonObject ?: return
        // Check-in/out payload may use `asset` as a name string, not an object.
        val obj = (payload["asset"] as? JsonObject) ?: payload
        val incoming = decodeJsonElementValue<Asset>(obj) ?: return
        if (incoming.id <= 0) return
        val existing = _assets.value.find { it.id == incoming.id }
        val merged = if (existing == null) incoming else existing.mergedWithPayload(incoming, obj)
        applyUpdatedAsset(merged)
    }

    // PATCH/check-in payload can omit fields; keep cached values for missing keys.
    private fun Asset.mergedWithPayload(incoming: Asset, obj: JsonObject): Asset = copy(
        name = if (obj.containsKey("name")) incoming.name else name,
        assetTag = if (obj.containsKey("asset_tag")) incoming.assetTag else assetTag,
        serial = if (obj.containsKey("serial")) incoming.serial else serial,
        model = if (obj.containsKey("model")) incoming.model else model,
        statusLabel = if (obj.containsKey("status_label")) incoming.statusLabel else statusLabel,
        category = if (obj.containsKey("category")) incoming.category else category,
        manufacturer = if (obj.containsKey("manufacturer")) incoming.manufacturer else manufacturer,
        supplier = if (obj.containsKey("supplier")) incoming.supplier else supplier,
        notes = if (obj.containsKey("notes")) incoming.notes else notes,
        orderNumber = if (obj.containsKey("order_number")) incoming.orderNumber else orderNumber,
        company = if (obj.containsKey("company")) incoming.company else company,
        location = if (obj.containsKey("location")) incoming.location else location,
        rtdLocation = if (obj.containsKey("rtd_location")) incoming.rtdLocation else rtdLocation,
        image = if (obj.containsKey("image")) incoming.image else image,
        assignedTo = if (obj.containsKey("assigned_to")) incoming.assignedTo else assignedTo,
        warrantyMonths = if (obj.containsKey("warranty_months")) incoming.warrantyMonths else warrantyMonths,
        warrantyExpires = if (obj.containsKey("warranty_expires")) incoming.warrantyExpires else warrantyExpires,
        purchaseDate = if (obj.containsKey("purchase_date")) incoming.purchaseDate else purchaseDate,
        assetEolDate = if (obj.containsKey("asset_eol_date") || obj.containsKey("eol_date")) incoming.assetEolDate else assetEolDate,
        nextAuditDate = if (obj.containsKey("next_audit_date")) incoming.nextAuditDate else nextAuditDate,
        lastAuditDate = if (obj.containsKey("last_audit_date")) incoming.lastAuditDate else lastAuditDate,
        lastCheckout = if (obj.containsKey("last_checkout")) incoming.lastCheckout else lastCheckout,
        lastCheckin = if (obj.containsKey("last_checkin")) incoming.lastCheckin else lastCheckin,
        expectedCheckin = if (obj.containsKey("expected_checkin")) incoming.expectedCheckin else expectedCheckin,
        purchaseCost = if (obj.containsKey("purchase_cost")) incoming.purchaseCost else purchaseCost,
        bookValue = if (obj.containsKey("book_value")) incoming.bookValue else bookValue,
        customFields = if (obj.containsKey("custom_fields")) incoming.customFields else customFields,
        userCanCheckout = if (obj.containsKey("user_can_checkout")) incoming.userCanCheckout else userCanCheckout,
        availableActions = if (obj.containsKey("available_actions")) incoming.availableActions else availableActions,
        updatedAt = if (obj.containsKey("updated_at")) incoming.updatedAt else updatedAt,
    )

    // endregion

    // region HTTP layer

    private data class HttpResult(val code: Int, val body: String, val json: JsonObject?)

    private suspend fun <T> fetchAllPaginated(
        path: String,
        serializer: KSerializer<T>,
        reportProgress: Boolean = false,
        reportConnectionError: Boolean = false,
        extraQuery: Map<String, String> = emptyMap(),
        isCancelled: () -> Boolean = { false },
    ): List<T>? = fetchAllPaginatedInternal(path, serializer, reportProgress, reportConnectionError, extraQuery, isCancelled)

    private suspend fun <T> fetchAllPaginatedInternal(
        path: String,
        serializer: KSerializer<T>,
        reportProgress: Boolean,
        reportConnectionError: Boolean,
        extraQuery: Map<String, String>,
        isCancelled: () -> Boolean,
    ): List<T>? {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) return null
        val collected = mutableListOf<T>()
        var offset = 0
        var serverTotal: Int? = null
        if (reportProgress) withContext(Dispatchers.Main) { _loadingProgress.value = LoadingProgress(0, -1) }
        try {
            while (true) {
                if (isCancelled()) return null
                val query = buildString {
                    append("limit=$API_PAGE_SIZE&offset=$offset")
                    extraQuery.forEach { (k, v) -> append("&$k=$v") }
                }
                val url = "$baseUrl$path?$query"
                val response = try {
                    executeGet(url, reportConnectionError = reportConnectionError)
                } catch (e: Exception) {
                    if (reportConnectionError) {
                        withContext(Dispatchers.Main) {
                            reportRefreshError(localizedConnectionFailureMessage(e))
                        }
                    }
                    throw e
                }
                if (response.code == 429) {
                    delay(RATE_LIMIT_RETRY_MS)
                    continue
                }
                if (response.code !in 200..299) {
                    if (reportConnectionError) {
                        withContext(Dispatchers.Main) {
                            reportHttpRefreshFailure(response.code)
                        }
                    }
                    return null
                }
                val pageJson = parseJsonObject(response.body)
                val rowsElement = pageJson?.get("rows")
                val rows = if (rowsElement is JsonArray) {
                    rowsElement.mapNotNull { element ->
                        runCatching { SnipeJson.decodeFromJsonElement(serializer, element) }.getOrNull()
                    }
                } else {
                    // Unexpected page body shape.
                    runCatching {
                        SnipeJson.decodeFromString(PagedResponse.serializer(serializer), response.body).rows.orEmpty()
                    }.getOrElse { emptyList() }
                }
                collected.addAll(rows)
                serverTotal = pageJson?.get("total")?.jsonPrimitive?.intOrNull ?: serverTotal
                if (reportProgress) {
                    withContext(Dispatchers.Main) {
                        _loadingProgress.value = LoadingProgress(collected.size, serverTotal ?: -1)
                    }
                }
                if (rows.size < API_PAGE_SIZE) break
                if (serverTotal != null && collected.size >= serverTotal) break
                if (rows.isEmpty()) break
                offset += API_PAGE_SIZE
                delay(PAGE_DELAY_MS)
            }
            return collected
        } finally {
            if (reportProgress) withContext(Dispatchers.Main) { _loadingProgress.value = null }
        }
    }

    private suspend fun executeGet(
        url: String,
        reportConnectionError: Boolean = false,
        bypassCache: Boolean = false,
    ): HttpResult =
        withContext(Dispatchers.IO) {
            val request = authorizedRequest(url, bypassCache = bypassCache).build()
            val response = client.newCall(request).execute()
            val body = response.body?.string().orEmpty()
            HttpResult(response.code, body, parseJsonObject(body))
        }

    private suspend fun executeJsonPost(url: String, body: Map<String, Any?>): HttpResult =
        executeJsonRequest("POST", url, body)

    private suspend fun executeJsonPatch(url: String, body: Map<String, Any?>): HttpResult =
        executeJsonRequest("PATCH", url, body)

    private suspend fun executeJsonPut(url: String, body: Map<String, Any?>): HttpResult {
        val response = executeJsonRequest("PUT", url, body)
        if (response.code != 405) return response
        // Hosts that block PUT accept POST + _method.
        return executeJsonRequest("POST", url, body + ("_method" to "PUT"))
    }

    private suspend fun executeDelete(url: String): HttpResult =
        withContext(Dispatchers.IO) {
            val request = authorizedRequest(url).delete().build()
            val response = client.newCall(request).execute()
            val body = response.body?.string().orEmpty()
            HttpResult(response.code, body, parseJsonObject(body))
        }

    private suspend fun executeDeleteWithFallback(url: String): HttpResult {
        var response = executeDelete(url)
        if (response.code == 405) {
            response = withContext(Dispatchers.IO) {
                val formMediaType = "application/x-www-form-urlencoded".toMediaType()
                val requestBody = "_method=DELETE".toRequestBody(formMediaType)
                val request = authorizedRequest(url).post(requestBody).build()
                val httpResponse = client.newCall(request).execute()
                val body = httpResponse.body?.string().orEmpty()
                HttpResult(httpResponse.code, body, parseJsonObject(body))
            }
        }
        return response
    }

    private suspend fun executeJsonRequest(method: String, url: String, body: Map<String, Any?>): HttpResult =
        withContext(Dispatchers.IO) {
            val jsonBody = mapToJson(body).toString().toRequestBody(jsonMediaType)
            val builder = authorizedRequest(url).method(method, jsonBody)
            val response = client.newCall(builder.build()).execute()
            val responseBody = response.body?.string().orEmpty()
            HttpResult(response.code, responseBody, parseJsonObject(responseBody))
        }

    /** Multipart hardware write (POST + `_method` for PUT/PATCH). */
    private suspend fun sendHardwareMultipart(
        url: String,
        method: String,
        body: Map<String, Any?>,
        image: UploadFile?,
    ): HttpResult = withContext(Dispatchers.IO) {
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
        var httpMethod = method
        if (method == "PUT" || method == "PATCH") {
            builder.addFormDataPart("_method", method)
            httpMethod = "POST"
        }
        body.forEach { (key, value) ->
            val stringValue = when (value) {
                null -> return@forEach
                is Boolean -> if (value) "1" else "0"
                else -> value.toString()
            }
            builder.addFormDataPart(key, stringValue)
        }
        image?.let { file ->
            val mediaType = file.mimeType.toMediaTypeOrNull()
            builder.addFormDataPart("image", file.filename, file.data.toRequestBody(mediaType))
        }
        val request = authorizedRequest(url).method(httpMethod, builder.build()).build()
        val httpResponse = client.newCall(request).execute()
        val responseBody = httpResponse.body?.string().orEmpty()
        HttpResult(httpResponse.code, responseBody, parseJsonObject(responseBody))
    }

    private suspend fun putLicenseSeatUpdate(
        licenseId: Int,
        seatId: Int,
        body: Map<String, Any?>,
    ): String? {
        val response = executeJsonPut("$baseUrl/api/v1/licenses/$licenseId/seats/$seatId", body)
        if (!isSnipeApiHttpSuccess(response.code)) {
            return "HTTP ${response.code}: ${response.body.take(300)}"
        }
        if (isSnipeApiErrorResponse(response.json)) {
            return extractApiErrorMessage(response.json) ?: "Request failed."
        }
        return null
    }

    private suspend fun createEntity(
        url: String,
        body: Map<String, Any?>,
        onSuccess: suspend (Int?) -> Unit,
    ): CreateResult {
        if (baseUrl.isEmpty() || apiToken.isEmpty()) {
            return CreateResult(false, message = "API not configured.")
        }
        val response = executeJsonPost(url, body)
        if (!isSnipeApiHttpSuccess(response.code)) {
            return CreateResult(false, message = "HTTP ${response.code}: ${response.body.take(300)}")
        }
        if (isSnipeApiErrorResponse(response.json)) {
            return CreateResult(false, message = extractApiErrorMessage(response.json) ?: "Create failed.")
        }
        val newId = idFromPayload(response.json)
        onSuccess(newId)
        return CreateResult(true, id = newId)
    }

    private suspend fun patchEntity(url: String, body: Map<String, Any?>, onSuccess: suspend () -> Unit): Boolean {
        val response = executeJsonPatch(url, body)
        val result = evaluateWriteResponse(response.json, response.code, "Saved.", "Save failed.")
        withContext(Dispatchers.Main) { _lastApiMessage.value = result.message }
        if (!result.success) return false
        onSuccess()
        return true
    }

    private suspend inline fun <reified T> fetchEntity(url: String): T? {
        val response = executeGet(url, bypassCache = true)
        if (response.code !in 200..299) return null
        val json = response.json ?: return null
        if (isSnipeApiErrorResponse(json)) return null
        if (json.containsKey("id")) {
            decodeJsonElementValue<T>(json)?.let { return it }
        }
        val payload = json["payload"] as? JsonObject ?: return null
        return decodeJsonElementValue<T>(payload)
    }

    private suspend fun downloadToCache(url: String, preferredFilename: String, fileId: Int): java.io.File? =
        withContext(Dispatchers.IO) {
            val request = Request.Builder()
                .url(url)
                .header("Authorization", "Bearer $apiToken")
                .header("Accept", "*/*")
                .header("User-Agent", USER_AGENT)
                .build()
            val response = client.newCall(request).execute()
            response.use { http ->
                if (http.code != 200) return@withContext null
                val bytes = http.body?.bytes() ?: return@withContext null
                if (!isBinaryFilePayload(bytes)) return@withContext null
                val dir = java.io.File(appContext.cacheDir, "snipe-files").apply { mkdirs() }
                val name = sanitizedDownloadFilename(preferredFilename, fileId)
                val file = java.io.File(dir, "${java.util.UUID.randomUUID()}-$name")
                file.writeBytes(bytes)
                file
            }
        }

    private fun apiFilesObjectType(itemType: String): String =
        when (itemType.trim().lowercase(Locale.US)) {
            "asset", "assets", "hardware" -> "hardware"
            "accessory", "accessories" -> "accessories"
            "component", "components" -> "components"
            "consumable", "consumables" -> "consumables"
            "license", "licenses" -> "licenses"
            "user", "users" -> "users"
            "location", "locations" -> "locations"
            "model", "models", "asset_models" -> "models"
            "maintenance", "maintenances" -> "maintenances"
            else -> itemType.trim()
        }

    private fun isBinaryFilePayload(bytes: ByteArray): Boolean {
        if (bytes.isEmpty()) return false
        val first = bytes[0].toInt().toChar()
        if (first == '{' || first == '[') return false
        val headLen = minOf(200, bytes.size)
        val head = bytes.copyOfRange(0, headLen).toString(Charsets.UTF_8).lowercase(Locale.US)
        return !head.contains("<!doctype html") && !head.contains("<html")
    }

    private fun sanitizedDownloadFilename(preferred: String, fileId: Int): String {
        val raw = preferred.substringAfterLast('/').substringAfterLast('\\')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
        return raw.ifBlank { "file-$fileId" }.take(120)
    }

    private fun authorizedRequest(url: String, bypassCache: Boolean = false): Request.Builder {
        val builder = Request.Builder()
            .url(url)
            .header("Authorization", "Bearer $apiToken")
            .header("Accept", "application/json")
            .header("User-Agent", USER_AGENT)
        if (bypassCache) {
            builder.header("Cache-Control", "no-cache")
            builder.header("Pragma", "no-cache")
        }
        return builder
    }

    /**
     * Snipe-IT 8.7+ prefers `expected_completion_date`; older servers only know
     * `completion_date`. Mirror whichever key the caller set so both work.
     */
    private fun withMirroredMaintenanceCompletion(body: Map<String, Any?>): Map<String, Any?> {
        if (!body.containsKey("completion_date") && !body.containsKey("expected_completion_date")) {
            return body
        }
        val mutable = body.toMutableMap()
        when {
            mutable.containsKey("completion_date") ->
                mutable["expected_completion_date"] = mutable["completion_date"]
            else ->
                mutable["completion_date"] = mutable["expected_completion_date"]
        }
        return mutable
    }

    // endregion

    // region JSON helpers

    private inline fun <reified T> decodePayloadOrRoot(body: String): T? {
        parseJsonObject(body)?.let { json ->
            if (isSnipeApiErrorResponse(json)) return null
            json["payload"]?.let { payload ->
                if (payload !is JsonNull) {
                    decodeJsonElementValue<T>(payload)?.let { return it }
                }
            }
        }
        return runCatching { SnipeJson.decodeFromString<T>(body) }.getOrNull()
    }

    private inline fun <reified T> decodeFirstRow(body: String): T? {
        val json = parseJsonObject(body) ?: return null
        val rowsElement = json["rows"] ?: return null
        return runCatching {
            SnipeJson.decodeFromJsonElement(kotlinx.serialization.builtins.ListSerializer(kotlinx.serialization.serializer<T>()), rowsElement)
        }.getOrNull()?.firstOrNull()
    }

    private inline fun <reified T> decodeJsonElementValue(element: JsonElement): T? =
        runCatching {
            SnipeJson.decodeFromJsonElement(kotlinx.serialization.serializer<T>(), element)
        }.getOrNull()

    private fun parseJsonObject(body: String): JsonObject? =
        runCatching { SnipeJson.parseToJsonElement(body).jsonObject }.getOrNull()

    private fun mapToJson(map: Map<String, Any?>): JsonObject = buildJsonObject {
        map.forEach { (key, value) ->
            when (value) {
                null -> put(key, JsonNull)
                is Boolean -> put(key, value)
                is Number -> put(key, value)
                is String -> put(key, value)
                is JsonElement -> put(key, value)
                else -> put(key, value.toString())
            }
        }
    }

    private fun jsonObjectToMap(json: JsonObject): Map<String, Any?> =
        json.entries.associate { (key, value) ->
            key to when {
                value is JsonNull -> null
                value.jsonPrimitive.isString -> value.jsonPrimitive.content
                value.jsonPrimitive.intOrNull != null -> value.jsonPrimitive.intOrNull
                value.jsonPrimitive.contentOrNull == "true" -> true
                value.jsonPrimitive.contentOrNull == "false" -> false
                else -> value.jsonPrimitive.contentOrNull
            }
        }

    private fun idFromPayload(json: JsonObject?): Int? {
        json ?: return null
        json["id"]?.jsonPrimitive?.intOrNull?.let { return it }
        json["payload"]?.jsonObject?.get("id")?.jsonPrimitive?.intOrNull?.let { return it }
        return null
    }

    // endregion

    // region URL normalization & response parsing

    companion object {
        private const val API_PAGE_SIZE = 500
        private const val PAGE_DELAY_MS = 60L
        private const val RATE_LIMIT_RETRY_MS = 1500L
        private const val CACHE_SAVE_DEBOUNCE_MS = 700L

        /** Identifies the app to Snipe-IT (avoids default `okhttp/` UA blocked in 8.7+). */
        private val USER_AGENT: String =
            "SnipeMobile/${BuildConfig.VERSION_NAME} (Android)"

        fun normalizeBaseUrl(value: String): String {
            var trimmed = value.trim()
            while (trimmed.endsWith("/")) trimmed = trimmed.dropLast(1)
            if (trimmed.isEmpty()) return trimmed
            val lower = trimmed.lowercase()
            if (!lower.startsWith("http://") && !lower.startsWith("https://")) {
                trimmed = "https://$trimmed"
            }
            // Prefer `/account/api` over bare `/api` (tokens page paste).
            val suffixes = listOf(
                "/index.php/account/api",
                "/account/api",
                "/index.php/api/v1",
                "/index.php/api",
                "/api/v1",
                "/api",
                "/index.php",
            )
            for (suffix in suffixes) {
                if (trimmed.lowercase().endsWith(suffix)) {
                    trimmed = trimmed.dropLast(suffix.length)
                    break
                }
            }
            while (trimmed.endsWith("/")) trimmed = trimmed.dropLast(1)
            return trimmed
        }

        fun normalizeApiToken(value: String): String {
            var token = value.trim()
            if (token.length >= 7 && token.substring(0, 7).equals("bearer ", ignoreCase = true)) {
                token = token.substring(7).trim()
            }
            return token
        }

        fun isSnipeApiHttpSuccess(statusCode: Int): Boolean = statusCode in 200..299

        fun isSnipeApiErrorResponse(json: JsonObject?): Boolean {
            json ?: return false
            val status = (json["status"] as? JsonPrimitive)?.contentOrNull?.lowercase()
            if (status == "error") return true
            if (json["errors"] is JsonObject) {
                if (status == null || status == "error") return true
            }
            return false
        }

        fun extractApiErrorMessage(json: JsonObject?): String? {
            json ?: return null
            json["message"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { return it }
            json["error"]?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotEmpty() }?.let { return it }
            return null
        }

        fun evaluateWriteResponse(
            json: JsonObject?,
            httpStatus: Int,
            defaultSuccessMessage: String,
            defaultFailureMessage: String,
        ): WriteResult {
            val success = isSnipeApiHttpSuccess(httpStatus) && !isSnipeApiErrorResponse(json)
            val message = extractApiErrorMessage(json)
                ?: if (success) defaultSuccessMessage else defaultFailureMessage
            return WriteResult(success = success, message = message)
        }

        fun localizedHttpFailureMessage(statusCode: Int): String = when (statusCode) {
            401, 403 -> L10n.string("api_validate_unauthorized")
            404 -> L10n.string("api_validate_not_found")
            429 -> L10n.string("api_connect_rate_limited")
            502, 504 -> L10n.string("api_connect_bad_gateway")
            503 -> L10n.string("refresh_failed_maintenance")
            else -> L10n.string("api_validate_http", statusCode)
        }

        private fun parseAssetTagSettings(json: JsonObject): AssetTagGenerationSettings? {
            val dict = json["payload"]?.jsonObject ?: json
            val hasKeys = dict.containsKey("auto_increment_prefix")
                || dict.containsKey("next_auto_tag_base")
                || dict.containsKey("auto_increment_assets")
                || dict.containsKey("zerofill_count")
            if (!hasKeys) return null
            return AssetTagGenerationSettings(
                autoIncrementAssets = parseSnipeBool(dict["auto_increment_assets"]),
                prefix = dict["auto_increment_prefix"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                zerofillCount = parseSnipeInt(dict["zerofill_count"]) ?: 0,
                nextAutoTagBase = parseSnipeInt(dict["next_auto_tag_base"]) ?: 1,
            )
        }

        private fun parseSnipeBool(value: JsonElement?): Boolean {
            if (value == null || value is JsonNull) return false
            val primitive = value.jsonPrimitive
            primitive.contentOrNull?.let { content ->
                return content == "1" || content.equals("true", ignoreCase = true)
            }
            return (primitive.intOrNull ?: 0) != 0
        }

        private fun parseSnipeInt(value: JsonElement?): Int? {
            if (value == null || value is JsonNull) return null
            value.jsonPrimitive.intOrNull?.let { return it }
            return value.jsonPrimitive.contentOrNull?.trim()?.toIntOrNull()
        }

        private val taggedNumberRegex = Regex("^(.*?)(\\d+)$")

        private fun parseTaggedNumber(tag: String): Triple<String, Int, Int>? {
            val match = taggedNumberRegex.matchEntire(tag) ?: return null
            val prefix = match.groupValues[1]
            val numStr = match.groupValues[2]
            val number = numStr.toIntOrNull() ?: return null
            return Triple(prefix, number, numStr.length)
        }

        fun formatNextAssetTag(tags: List<String>, settings: AssetTagGenerationSettings): String {
            val prefix = settings.prefix
            val relevantTags = if (prefix.isEmpty()) tags else tags.filter { it.startsWith(prefix) }
            val suffixNumbers = mutableListOf<Pair<Int, Int>>()
            for (tag in relevantTags) {
                val suffix = if (prefix.isEmpty()) tag else tag.drop(prefix.length)
                val digits = suffix.filter { it.isDigit() }
                if (digits.isNotEmpty()) {
                    digits.toIntOrNull()?.let { suffixNumbers.add(it to digits.length) }
                } else {
                    parseTaggedNumber(tag)?.let { (_, number, width) ->
                        suffixNumbers.add(number to width)
                    }
                }
            }
            val maxFromTags = suffixNumbers.maxOfOrNull { it.first } ?: 0
            val nextNum = maxOf(settings.nextAutoTagBase, maxFromTags + 1)
            val widthFromTags = suffixNumbers.maxOfOrNull { it.second } ?: 0
            val numeric = when {
                settings.zerofillCount > 0 -> "%0${settings.zerofillCount}d".format(nextNum)
                widthFromTags > 0 -> "%0${widthFromTags}d".format(nextNum)
                else -> nextNum.toString()
            }
            return prefix + numeric
        }

        fun inferNextAssetTag(tags: List<String>): String {
            val byPrefix = mutableMapOf<String, MutableList<Pair<Int, Int>>>()
            for (tag in tags) {
                parseTaggedNumber(tag)?.let { (prefix, number, width) ->
                    byPrefix.getOrPut(prefix) { mutableListOf() }.add(number to width)
                }
            }
            val best = byPrefix.maxByOrNull { it.value.size }
            if (best != null && best.value.isNotEmpty()) {
                val nextNum = (best.value.maxOf { it.first }) + 1
                val width = maxOf(best.value.maxOf { it.second }, nextNum.toString().length)
                return best.key + "%0${width}d".format(nextNum)
            }
            val numbers = tags.mapNotNull { tag ->
                val digits = tag.filter { it.isDigit() }
                digits.takeIf { it.isNotEmpty() }?.toIntOrNull()
            }
            val nextNum = (numbers.maxOrNull() ?: 0) + 1
            val digitLengths = tags.mapNotNull { tag ->
                val digits = tag.filter { it.isDigit() }
                digits.takeIf { it.isNotEmpty() }?.length
            }
            val width = digitLengths.maxOrNull() ?: 5
            return "%0${width}d".format(nextNum)
        }

        fun localizedConnectionFailureMessage(error: Throwable): String {
            val kind = connectionFailureKind(error)
            AppLog.network("Connection failed kind=${kind.name.lowercase(Locale.US)}")
            return when (kind) {
                ConnectionFailureKind.NoNetwork -> L10n.string("api_connect_no_network")
                ConnectionFailureKind.Dns -> L10n.string("api_connect_dns")
                ConnectionFailureKind.HostUnreachable -> L10n.string("api_connect_host_unreachable")
                ConnectionFailureKind.Timeout -> L10n.string("api_connect_timeout")
                ConnectionFailureKind.Tls -> L10n.string("api_connect_tls")
                ConnectionFailureKind.HttpBlocked -> L10n.string("api_validate_http_blocked")
                ConnectionFailureKind.Cancelled -> L10n.string("api_connect_cancelled")
                ConnectionFailureKind.Other -> L10n.string("api_validate_connect_failed")
            }
        }

        private enum class ConnectionFailureKind {
            NoNetwork,
            Dns,
            HostUnreachable,
            Timeout,
            Tls,
            HttpBlocked,
            Cancelled,
            Other,
        }

        private fun connectionFailureKind(error: Throwable): ConnectionFailureKind {
            val chain = generateSequence(error) { it.cause }.toList()
            if (chain.any { it is CancellationException }) return ConnectionFailureKind.Cancelled

            val message = chain.mapNotNull { it.message }.joinToString(" ").lowercase(Locale.US)
            if (message.contains("cleartext")) {
                return ConnectionFailureKind.HttpBlocked
            }
            if (
                chain.any {
                    it is javax.net.ssl.SSLException ||
                        it is java.security.cert.CertificateException
                } ||
                message.contains("certificate") ||
                message.contains("trust anchor") ||
                message.contains("ssl handshake")
            ) {
                return ConnectionFailureKind.Tls
            }
            if (chain.any { it is UnknownHostException }) return ConnectionFailureKind.Dns
            if (chain.any { it is SocketTimeoutException }) return ConnectionFailureKind.Timeout
            if (
                chain.any {
                    it is ConnectException ||
                        it is java.net.NoRouteToHostException ||
                        it is java.net.PortUnreachableException
                }
            ) {
                return ConnectionFailureKind.HostUnreachable
            }
            if (
                message.contains("unable to resolve host") ||
                message.contains("network is unreachable") ||
                message.contains("failed to connect")
            ) {
                return ConnectionFailureKind.HostUnreachable
            }
            if (message.contains("unknownhost") || message.contains("nodename nor servname")) {
                return ConnectionFailureKind.Dns
            }
            if (chain.any { it is IOException } &&
                (message.contains("software caused connection abort") ||
                    message.contains("connection reset") ||
                    message.contains("broken pipe") ||
                    message.contains("enotconn") ||
                    message.contains("network"))
            ) {
                return ConnectionFailureKind.NoNetwork
            }
            return ConnectionFailureKind.Other
        }
    }

    // endregion
}

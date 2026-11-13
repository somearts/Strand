package com.strand.strand

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity for Strand.
 *
 * A [FlutterFragmentActivity] is required, not merely preferred: the Health
 * Connect permission contract registers itself as an activity result launcher
 * on an `androidx.activity.ComponentActivity`. FlutterFragmentActivity is one;
 * a plain FlutterActivity is not, and casting it to one crashed the app during
 * onCreate in the previous build.
 *
 * Health Connect permission is requested here rather than through the plugin's
 * own launcher. Both request the same record type, but this path logs exactly
 * what was asked for and what came back, and it can fall back to Health
 * Connect's own app when Android refuses to show the in-app sheet. The health
 * plugin is still used for the actual sleep reads.
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL = "strand/health"
        private const val TAG = "STRAND_HEALTH"
        private const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"
    }

    private var permissionLauncher: ActivityResultLauncher<Set<String>>? = null
    private var pendingResult: MethodChannel.Result? = null

    /** All record types Strand reads. Sleep session plus every overnight metric. */
    private val sleepPermissions: Set<String>
        get() = setOf(
            HealthPermission.getReadPermission(SleepSessionRecord::class),
            HealthPermission.getReadPermission(HeartRateRecord::class),
            HealthPermission.getReadPermission(RestingHeartRateRecord::class),
            HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
            HealthPermission.getReadPermission(OxygenSaturationRecord::class),
            HealthPermission.getReadPermission(RespiratoryRateRecord::class),
        )

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Registered in onCreate, before the activity is started, which is the
        // only safe point for an activity-result launcher.
        permissionLauncher = registerForActivityResult(
            PermissionController.createRequestPermissionResultContract(),
        ) { granted ->
            Log.i(TAG, "permission result: granted=$granted")
            val result = pendingResult
            pendingResult = null
            result?.success(granted.containsAll(sleepPermissions))
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermissions" -> requestSleepPermission(result)
                    "openHealthConnect" -> {
                        openHealthConnect()
                        result.success(true)
                    }
                    "healthConnectInstalled" -> {
                        result.success(isHealthConnectInstalled())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestSleepPermission(result: MethodChannel.Result) {
        val launcher = permissionLauncher
        if (launcher == null) {
            Log.e(TAG, "no permission launcher")
            result.success(false)
            return
        }
        if (pendingResult != null) {
            Log.w(TAG, "a permission request is already in flight")
            result.success(false)
            return
        }

        val permissions = sleepPermissions
        val contract = PermissionController.createRequestPermissionResultContract()
        val intent = contract.createIntent(this, permissions)
        Log.i(TAG, "requesting $permissions")
        Log.i(TAG, "contract intent=$intent")
        Log.i(
            TAG,
            "intent resolves to=${intent.resolveActivity(packageManager)}",
        )

        // If the system has nothing that can show the sheet, do not launch and
        // silently report a refusal: send the person to Health Connect itself.
        if (intent.resolveActivity(packageManager) == null) {
            Log.w(TAG, "no activity resolves the permission sheet")
        }

        pendingResult = result
        try {
            launcher.launch(permissions)
        } catch (error: Throwable) {
            Log.e(TAG, "permission sheet could not be shown", error)
            pendingResult = null
            openHealthConnect()
            result.success(false)
        }
    }

    /**
     * Reports what Health Connect says is granted right now.
     */
    private fun isHealthConnectInstalled(): Boolean {
        return try {
            HealthConnectClient.getSdkStatus(this) == HealthConnectClient.SDK_AVAILABLE
        } catch (_: Throwable) {
            false
        }
    }

    /**
     * Opens Health Connect's own UI. This is the only route left when Android
     * has decided not to show the in-app permission sheet, and it is also where
     * a permanently refused permission has to be changed.
     */
    private fun openHealthConnect() {
        val candidates = listOf(
            packageManager.getLaunchIntentForPackage(HEALTH_CONNECT_PACKAGE),
            packageManager.getLaunchIntentForPackage(
                "com.google.android.healthconnect.controller",
            ),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", packageName, null)
            },
        )
        for (intent in candidates) {
            if (intent == null) continue
            try {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                Log.i(TAG, "opened $intent")
                return
            } catch (error: Throwable) {
                Log.w(TAG, "could not open $intent", error)
            }
        }
    }
}

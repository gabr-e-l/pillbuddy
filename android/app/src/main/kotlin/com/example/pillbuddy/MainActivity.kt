package com.example.pillbuddy

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.pillbuddy/system"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Timezone ───────────────────────────────────────────
                    // Returns the IANA timezone ID for the device's current
                    // default timezone (e.g. "Asia/Manila").
                    "getTimezone" -> {
                        result.success(java.util.TimeZone.getDefault().id)
                    }

                    // ── DND status ─────────────────────────────────────────
                    // Returns true if the device is currently in a DND mode
                    // that would silence alarms (INTERRUPTION_FILTER_NONE or
                    // INTERRUPTION_FILTER_PRIORITY on older APIs).
                    "isDndActive" -> {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager
                        val filter = nm.currentInterruptionFilter
                        result.success(
                            filter == NotificationManager.INTERRUPTION_FILTER_NONE ||
                            filter == NotificationManager.INTERRUPTION_FILTER_PRIORITY
                        )
                    }

                    // ── DND permission grant ───────────────────────────────
                    // Opens the system screen where the user can whitelist
                    // this app for DND access (ACCESS_NOTIFICATION_POLICY).
                    "requestDndAccess" -> {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager
                        if (!nm.isNotificationPolicyAccessGranted) {
                            val intent = Intent(
                                Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS
                            )
                            startActivity(intent)
                        }
                        result.success(nm.isNotificationPolicyAccessGranted)
                    }

                    // ── Exact-alarm permission (Android 12+) ───────────────
                    // Returns true if exact alarms are already permitted.
                    // If not, opens the system settings page so the user can
                    // grant it.  flutter_local_notifications also calls
                    // requestExactAlarmsPermission(), but only at notification-
                    // schedule time; calling this early gives us a chance to
                    // guide the user before the first alarm is missed.
                    "isExactAlarmPermitted" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val am = getSystemService(
                                Context.ALARM_SERVICE
                            ) as android.app.AlarmManager
                            result.success(am.canScheduleExactAlarms())
                        } else {
                            // Below Android 12 exact alarms are always allowed.
                            result.success(true)
                        }
                    }

                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            val intent = Intent(
                                Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM
                            )
                            startActivity(intent)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
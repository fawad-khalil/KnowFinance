package com.knowfinance.know_finance

import android.provider.Telephony
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "knowfinance/sms")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "inbox" -> {
                        val since = call.argument<Number>("sinceMillis")?.toLong() ?: 0L
                        // Reading the inbox can take a moment on phones with
                        // years of messages, so keep it off the UI thread.
                        Thread {
                            try {
                                val messages = readInbox(since)
                                runOnUiThread { result.success(messages) }
                            } catch (e: SecurityException) {
                                runOnUiThread { result.error("permission", e.message, null) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("failed", e.message, null) }
                            }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun readInbox(sinceMillis: Long): List<Map<String, Any?>> {
        val out = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            Telephony.Sms.Inbox.CONTENT_URI,
            arrayOf(Telephony.Sms.ADDRESS, Telephony.Sms.BODY, Telephony.Sms.DATE),
            "${Telephony.Sms.DATE} > ?",
            arrayOf(sinceMillis.toString()),
            "${Telephony.Sms.DATE} DESC",
        )?.use { c ->
            val address = c.getColumnIndexOrThrow(Telephony.Sms.ADDRESS)
            val body = c.getColumnIndexOrThrow(Telephony.Sms.BODY)
            val date = c.getColumnIndexOrThrow(Telephony.Sms.DATE)
            while (c.moveToNext()) {
                out.add(
                    mapOf(
                        "sender" to c.getString(address),
                        "body" to c.getString(body),
                        "date" to c.getLong(date),
                    ),
                )
            }
        }
        return out
    }
}

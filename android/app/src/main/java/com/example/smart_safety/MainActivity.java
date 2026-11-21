package com.example.smart_safety;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.os.Build;
import android.os.Bundle;
import android.content.Intent;
import android.provider.Settings;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String BATTERY_SETTINGS_CHANNEL =
        "com.example.smart_safety/battery_settings";

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        new MethodChannel(
            flutterEngine.getDartExecutor().getBinaryMessenger(),
            BATTERY_SETTINGS_CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if (!call.method.equals("open")) {
                result.notImplemented();
                return;
            }
            try {
                startActivity(new Intent(
                    Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                ));
            } catch (Exception error) {
                startActivity(new Intent(Settings.ACTION_SETTINGS));
            }
            result.success(null);
        });
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                "safehelmet_alerts",
                "Safety alerts",
                NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("Critical and warning helmet incidents");
            NotificationManager manager = getSystemService(NotificationManager.class);
            manager.createNotificationChannel(channel);
        }
    }
}

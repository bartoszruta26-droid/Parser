package com.example.parserapp;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.preference.PreferenceManager;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Główna aktywność aplikacji Android.
 * Wyświetla status daemona i umożliwia wysyłanie podstawowych poleceń.
 */
public class MainActivity extends AppCompatActivity {

    private static final String TAG = "MainActivity";
    
    private TextView tvStatus;
    private TextView tvResponse;
    private Button btnPing;
    private Button btnStatus;
    private Button btnRefresh;
    
    private Handler handler;
    private ExecutorService executor;
    private SharedPreferences prefs;
    
    // Domyślne wartości (nadpisywane z konfiguracji)
    private String serverHost = "192.168.1.100";
    private int serverPort = 8080;
    private String serverProtocol = "http";
    private String apiBasePath = "/api/v1";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // Inicjalizacja widoków
        tvStatus = findViewById(R.id.tvStatus);
        tvResponse = findViewById(R.id.tvResponse);
        btnPing = findViewById(R.id.btnPing);
        btnStatus = findViewById(R.id.btnStatus);
        btnRefresh = findViewById(R.id.btnRefresh);
        
        // Inicjalizacja handlerów i executorów
        handler = new Handler(Looper.getMainLooper());
        executor = Executors.newSingleThreadExecutor();
        prefs = PreferenceManager.getDefaultSharedPreferences(this);
        
        // Ładowanie konfiguracji
        loadConfiguration();
        
        // Konfiguracja przycisków
        btnPing.setOnClickListener(v -> sendPingCommand());
        btnStatus.setOnClickListener(v -> sendStatusCommand());
        btnRefresh.setOnClickListener(v -> refreshStatus());
        
        // Automatyczne odświeżanie statusu
        refreshStatus();
    }
    
    /**
     * Ładuje konfigurację serwera z SharedPreferences.
     * Wartości powinny być ustawione w ConfigActivity.
     */
    private void loadConfiguration() {
        serverHost = prefs.getString("server_host", "192.168.1.100");
        serverPort = Integer.parseInt(prefs.getString("server_port", "8080"));
        serverProtocol = prefs.getString("server_protocol", "http");
        apiBasePath = prefs.getString("api_base_path", "/api/v1");
        
        tvStatus.setText("Serwer: " + serverHost + ":" + serverPort);
    }
    
    /**
     * Wysyła polecenie ping do daemona.
     */
    private void sendPingCommand() {
        tvResponse.setText("Wysyłanie ping...");
        
        executor.execute(() -> {
            try {
                String response = sendHttpRequest("ping", "{}");
                handler.post(() -> tvResponse.setText("Ping: " + response));
            } catch (Exception e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd ping: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Błąd komunikacji", Toast.LENGTH_SHORT).show();
                });
            }
        });
    }
    
    /**
     * Wysyła polecenie status do daemona.
     */
    private void sendStatusCommand() {
        tvResponse.setText("Pobieranie statusu...");
        
        executor.execute(() -> {
            try {
                String response = sendHttpRequest("status", "{}");
                handler.post(() -> tvResponse.setText("Status: " + response));
            } catch (Exception e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd status: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Błąd komunikacji", Toast.LENGTH_SHORT).show();
                });
            }
        });
    }
    
    /**
     * Odświeża status połączenia z serwerem.
     */
    private void refreshStatus() {
        executor.execute(() -> {
            try {
                String response = sendHttpRequest("status", "{}");
                handler.post(() -> {
                    tvStatus.setText("Daemon: ONLINE\nSerwer: " + serverHost + ":" + serverPort);
                    tvResponse.setText("Status: " + response);
                });
            } catch (Exception e) {
                handler.post(() -> {
                    tvStatus.setText("Daemon: OFFLINE");
                    tvResponse.setText("Błąd: " + e.getMessage());
                });
            }
        });
    }
    
    /**
     * Wysyła żądanie HTTP do serwera.
     * 
     * @param command Nazwa polecenia (np. "ping", "status")
     * @param payload Dane JSON do wysłania
     * @return Odpowiedź z serwera
     * @throws Exception Błąd komunikacji
     */
    private String sendHttpRequest(String command, String payload) throws Exception {
        String urlString = serverProtocol + "://" + serverHost + ":" + serverPort + apiBasePath + "/command/" + command;
        
        URL url = new URL(urlString);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "application/json");
        connection.setConnectTimeout(Integer.parseInt(prefs.getString("connection_timeout", "5000")));
        connection.setReadTimeout(Integer.parseInt(prefs.getString("read_timeout", "10000")));
        connection.setDoOutput(true);
        
        try (OutputStream os = connection.getOutputStream()) {
            byte[] input = payload.getBytes("utf-8");
            os.write(input, 0, input.length);
        }
        
        int responseCode = connection.getResponseCode();
        if (responseCode != HttpURLConnection.HTTP_OK) {
            throw new Exception("HTTP error: " + responseCode);
        }
        
        try (BufferedReader br = new BufferedReader(new InputStreamReader(connection.getInputStream(), "utf-8"))) {
            StringBuilder response = new StringBuilder();
            String responseLine;
            while ((responseLine = br.readLine()) != null) {
                response.append(responseLine.trim());
            }
            return response.toString();
        } finally {
            connection.disconnect();
        }
    }
    
    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        getMenuInflater().inflate(R.menu.main_menu, menu);
        return true;
    }
    
    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        int id = item.getItemId();
        
        if (id == R.id.action_config) {
            startActivity(new Intent(this, ConfigActivity.class));
            return true;
        }
        
        return super.onOptionsItemSelected(item);
    }
    
    @Override
    protected void onDestroy() {
        super.onDestroy();
        if (executor != null) {
            executor.shutdown();
        }
    }
}

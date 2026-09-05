package com.example.parserapp;

import android.content.SharedPreferences;
import android.os.Bundle;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.preference.PreferenceManager;

/**
 * Aktywność konfiguracji serwera.
 * Umożliwia użytkownikowi ustawienie parametrów połączenia z serwerem.
 */
public class ConfigActivity extends AppCompatActivity {

    private EditText etServerHost;
    private EditText etServerPort;
    private EditText etServerProtocol;
    private EditText etApiBasePath;
    private EditText etConnectionTimeout;
    private EditText etReadTimeout;
    private Button btnSave;
    private Button btnReset;
    
    private SharedPreferences prefs;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_config);
        
        // Inicjalizacja widoków
        etServerHost = findViewById(R.id.etServerHost);
        etServerPort = findViewById(R.id.etServerPort);
        etServerProtocol = findViewById(R.id.etServerProtocol);
        etApiBasePath = findViewById(R.id.etApiBasePath);
        etConnectionTimeout = findViewById(R.id.etConnectionTimeout);
        etReadTimeout = findViewById(R.id.etReadTimeout);
        btnSave = findViewById(R.id.btnSave);
        btnReset = findViewById(R.id.btnReset);
        
        prefs = PreferenceManager.getDefaultSharedPreferences(this);
        
        // Ładowanie zapisanej konfiguracji
        loadConfiguration();
        
        // Konfiguracja przycisków
        btnSave.setOnClickListener(v -> saveConfiguration());
        btnReset.setOnClickListener(v -> resetConfiguration());
    }
    
    /**
     * Ładuje zapisaną konfigurację z SharedPreferences.
     */
    private void loadConfiguration() {
        etServerHost.setText(prefs.getString("server_host", "192.168.1.100"));
        etServerPort.setText(prefs.getString("server_port", "8080"));
        etServerProtocol.setText(prefs.getString("server_protocol", "http"));
        etApiBasePath.setText(prefs.getString("api_base_path", "/api/v1"));
        etConnectionTimeout.setText(prefs.getString("connection_timeout", "5000"));
        etReadTimeout.setText(prefs.getString("read_timeout", "10000"));
    }
    
    /**
     * Zapisuje konfigurację do SharedPreferences.
     */
    private void saveConfiguration() {
        String host = etServerHost.getText().toString().trim();
        String port = etServerPort.getText().toString().trim();
        String protocol = etServerProtocol.getText().toString().trim();
        String basePath = etApiBasePath.getText().toString().trim();
        String connTimeout = etConnectionTimeout.getText().toString().trim();
        String readTimeout = etReadTimeout.getText().toString().trim();
        
        // Walidacja danych
        if (host.isEmpty()) {
            Toast.makeText(this, "Adres hosta nie może być pusty", Toast.LENGTH_SHORT).show();
            return;
        }
        
        if (port.isEmpty() || !port.matches("\\d+")) {
            Toast.makeText(this, "Port musi być liczbą", Toast.LENGTH_SHORT).show();
            return;
        }
        
        if (!protocol.equalsIgnoreCase("http") && !protocol.equalsIgnoreCase("https")) {
            Toast.makeText(this, "Protokół musi to być http lub https", Toast.LENGTH_SHORT).show();
            return;
        }
        
        // Zapis konfiguracji
        SharedPreferences.Editor editor = prefs.edit();
        editor.putString("server_host", host);
        editor.putString("server_port", port);
        editor.putString("server_protocol", protocol);
        editor.putString("api_base_path", basePath.startsWith("/") ? basePath : "/" + basePath);
        editor.putString("connection_timeout", connTimeout.isEmpty() ? "5000" : connTimeout);
        editor.putString("read_timeout", readTimeout.isEmpty() ? "10000" : readTimeout);
        editor.apply();
        
        Toast.makeText(this, "Konfiguracja zapisana", Toast.LENGTH_SHORT).show();
        finish();
    }
    
    /**
     * Przywraca domyślne wartości konfiguracji.
     */
    private void resetConfiguration() {
        etServerHost.setText("192.168.1.100");
        etServerPort.setText("8080");
        etServerProtocol.setText("http");
        etApiBasePath.setText("/api/v1");
        etConnectionTimeout.setText("5000");
        etReadTimeout.setText("10000");
        
        Toast.makeText(this, "Przywrócono wartości domyślne", Toast.LENGTH_SHORT).show();
    }
}

package com.example.parserapp;

import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;
import android.widget.AdapterView;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;
import androidx.preference.PreferenceManager;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Główna aktywność aplikacji Android.
 * Wyświetla status daemona i umożliwia wysyłanie danych medycznych zgodnych z protokołem medical-daemon.
 */
public class MainActivity extends AppCompatActivity {

    private static final String TAG = "MainActivity";
    
    // Widoki podstawowe
    private TextView tvStatus;
    private TextView tvResponse;
    private Button btnPing;
    private Button btnStatus;
    private Button btnRefresh;
    
    // Widoki dla Spinnerów
    private Spinner spinnerDataType;
    private Spinner spinnerSensorType;
    private Spinner spinnerFeedbackType;
    
    // Widoki dla Patient Data
    private EditText etPatientId;
    private EditText etProvider;
    private EditText etChiefComplaint;
    private EditText etMedicalHistory;
    private EditText etMedications;
    private EditText etAllergies;
    private Button btnSendPatientData;
    
    // Widoki dla Biosensor Data
    private EditText etSensorId;
    private EditText etSensorValue;
    private EditText etSensorUnit;
    private EditText etSampleRate;
    private EditText etQuality;
    private Button btnSendBiosensorData;
    
    // Widoki dla Biofeedback Data
    private EditText etFeedbackSensorId;
    private EditText etFeedbackValue;
    private EditText etFeedbackUnit;
    private EditText etSessionId;
    private EditText etTargetValue;
    private EditText etProgressPercent;
    private Button btnSendBiofeedbackData;
    
    private Handler handler;
    private ExecutorService executor;
    private SharedPreferences prefs;
    
    // Domyślne wartości (nadpisywane z konfiguracji)
    private String serverHost = "192.168.1.100";
    private int serverPort = 8080;
    private String serverProtocol = "http";
    private String apiBasePath = "/api/v1";
    
    // Dane dla Spinnerów
    private final String[] dataTypes = {"podmiotowe", "przedmiotowe"};
    private final String[] sensorTypes = {"ecg", "eeg", "emg", "eog", "ppg", "spo2", "temperature", "humidity", "pressure", "accelerometer", "gyroscope"};
    private final String[] feedbackTypes = {"hrv", "gsr", "temperature", "respiration", "alpha_waves", "beta_waves", "theta_waves", "delta_waves"};

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        
        // Inicjalizacja widoków podstawowych
        tvStatus = findViewById(R.id.tvStatus);
        tvResponse = findViewById(R.id.tvResponse);
        btnPing = findViewById(R.id.btnPing);
        btnStatus = findViewById(R.id.btnStatus);
        btnRefresh = findViewById(R.id.btnRefresh);
        
        // Inicjalizacja widoków Patient Data
        etPatientId = findViewById(R.id.etPatientId);
        etProvider = findViewById(R.id.etProvider);
        spinnerDataType = findViewById(R.id.spinnerDataType);
        etChiefComplaint = findViewById(R.id.etChiefComplaint);
        etMedicalHistory = findViewById(R.id.etMedicalHistory);
        etMedications = findViewById(R.id.etMedications);
        etAllergies = findViewById(R.id.etAllergies);
        btnSendPatientData = findViewById(R.id.btnSendPatientData);
        
        // Inicjalizacja widoków Biosensor Data
        etSensorId = findViewById(R.id.etSensorId);
        spinnerSensorType = findViewById(R.id.spinnerSensorType);
        etSensorValue = findViewById(R.id.etSensorValue);
        etSensorUnit = findViewById(R.id.etSensorUnit);
        etSampleRate = findViewById(R.id.etSampleRate);
        etQuality = findViewById(R.id.etQuality);
        btnSendBiosensorData = findViewById(R.id.btnSendBiosensorData);
        
        // Inicjalizacja widoków Biofeedback Data
        etFeedbackSensorId = findViewById(R.id.etFeedbackSensorId);
        spinnerFeedbackType = findViewById(R.id.spinnerFeedbackType);
        etFeedbackValue = findViewById(R.id.etFeedbackValue);
        etFeedbackUnit = findViewById(R.id.etFeedbackUnit);
        etSessionId = findViewById(R.id.etSessionId);
        etTargetValue = findViewById(R.id.etTargetValue);
        etProgressPercent = findViewById(R.id.etProgressPercent);
        btnSendBiofeedbackData = findViewById(R.id.btnSendBiofeedbackData);
        
        // Konfiguracja adapterów dla Spinnerów
        setupSpinners();
        
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
        
        btnSendPatientData.setOnClickListener(v -> sendPatientData());
        btnSendBiosensorData.setOnClickListener(v -> sendBiosensorData());
        btnSendBiofeedbackData.setOnClickListener(v -> sendBiofeedbackData());
        
        // Automatyczne odświeżanie statusu
        refreshStatus();
    }
    
    /**
     * Konfiguruje adaptory dla Spinnerów.
     */
    private void setupSpinners() {
        ArrayAdapter<String> dataTypeAdapter = new ArrayAdapter<>(this, 
            android.R.layout.simple_spinner_item, dataTypes);
        dataTypeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinnerDataType.setAdapter(dataTypeAdapter);
        
        ArrayAdapter<String> sensorTypeAdapter = new ArrayAdapter<>(this, 
            android.R.layout.simple_spinner_item, sensorTypes);
        sensorTypeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinnerSensorType.setAdapter(sensorTypeAdapter);
        
        ArrayAdapter<String> feedbackTypeAdapter = new ArrayAdapter<>(this, 
            android.R.layout.simple_spinner_item, feedbackTypes);
        feedbackTypeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinnerFeedbackType.setAdapter(feedbackTypeAdapter);
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
                MedicalMessage message = new MedicalMessage(MedicalMessage.COMMAND_PING, MedicalMessage.SOURCE_ANDROID);
                String response = sendHttpRequest(message);
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
                MedicalMessage message = new MedicalMessage(MedicalMessage.COMMAND_STATUS, MedicalMessage.SOURCE_ANDROID);
                String response = sendHttpRequest(message);
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
                MedicalMessage message = new MedicalMessage(MedicalMessage.COMMAND_STATUS, MedicalMessage.SOURCE_ANDROID);
                String response = sendHttpRequest(message);
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
     * Wysyła dane pacjenta (podmiotowe/przedmiotowe).
     */
    private void sendPatientData() {
        String patientId = etPatientId.getText().toString().trim();
        String provider = etProvider.getText().toString().trim();
        String dataType = spinnerDataType.getSelectedItem().toString();
        
        if (patientId.isEmpty()) {
            Toast.makeText(this, "Podaj ID pacjenta", Toast.LENGTH_SHORT).show();
            return;
        }
        
        executor.execute(() -> {
            try {
                // Budowanie Map z danymi - obsługuje dowolną liczbę pól
                Map<String, Object> data = new HashMap<>();
                
                String chiefComplaint = etChiefComplaint.getText().toString().trim();
                if (!chiefComplaint.isEmpty()) {
                    data.put("chief_complaint", chiefComplaint);
                }
                
                String medicalHistory = etMedicalHistory.getText().toString().trim();
                if (!medicalHistory.isEmpty()) {
                    // Parsowanie listy oddzielonej przecinkami
                    String[] historyArray = medicalHistory.split(",");
                    JSONArray jsonArray = new JSONArray();
                    for (String item : historyArray) {
                        jsonArray.put(item.trim());
                    }
                    data.put("past_medical_history", jsonArray);
                }
                
                String medications = etMedications.getText().toString().trim();
                if (!medications.isEmpty()) {
                    String[] medsArray = medications.split(",");
                    JSONArray jsonArray = new JSONArray();
                    for (String med : medsArray) {
                        jsonArray.put(med.trim());
                    }
                    data.put("medications", jsonArray);
                }
                
                String allergies = etAllergies.getText().toString().trim();
                if (!allergies.isEmpty()) {
                    String[] allergyArray = allergies.split(",");
                    JSONArray jsonArray = new JSONArray();
                    for (String allergy : allergyArray) {
                        jsonArray.put(allergy.trim());
                    }
                    data.put("allergies", jsonArray);
                }
                
                // Tworzenie wiadomości z użyciem MedicalMessage
                MedicalMessage message = new MedicalMessage(MedicalMessage.COMMAND_PATIENT_DATA, MedicalMessage.SOURCE_ANDROID);
                message.setPatientData(patientId, dataType, provider, data);
                message.setCorrelationId("visit-" + System.currentTimeMillis());
                
                String response = sendHttpRequest(message);
                handler.post(() -> {
                    tvResponse.setText("Dane pacjenta wysłane:\n" + response);
                    Toast.makeText(MainActivity.this, "Dane pacjenta wysłane", Toast.LENGTH_SHORT).show();
                });
            } catch (JSONException e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd JSON: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Błąd formatowania danych", Toast.LENGTH_SHORT).show();
                });
            } catch (Exception e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Błąd komunikacji", Toast.LENGTH_SHORT).show();
                });
            }
        });
    }
    
    /**
     * Wysyła dane z biosensora.
     */
    private void sendBiosensorData() {
        String sensorId = etSensorId.getText().toString().trim();
        String sensorType = spinnerSensorType.getSelectedItem().toString();
        String valueStr = etSensorValue.getText().toString().trim();
        String unit = etSensorUnit.getText().toString().trim();
        String sampleRateStr = etSampleRate.getText().toString().trim();
        String qualityStr = etQuality.getText().toString().trim();
        
        if (sensorId.isEmpty() || valueStr.isEmpty()) {
            Toast.makeText(this, "Podaj ID sensora i wartość", Toast.LENGTH_SHORT).show();
            return;
        }
        
        executor.execute(() -> {
            try {
                double value = Double.parseDouble(valueStr);
                
                // Dodatkowe parametry - obsługuje dowolną liczbę pól
                Map<String, Object> additionalParams = new HashMap<>();
                
                if (!sampleRateStr.isEmpty()) {
                    additionalParams.put("sample_rate", Double.parseDouble(sampleRateStr));
                }
                if (!qualityStr.isEmpty()) {
                    additionalParams.put("quality", Double.parseDouble(qualityStr));
                }
                
                // Tworzenie wiadomości z użyciem MedicalMessage
                MedicalMessage message = new MedicalMessage(MedicalMessage.COMMAND_BIOSENSOR_DATA, MedicalMessage.SOURCE_BIOSENSOR);
                message.setBiosensorData(sensorId, sensorType, value, unit, additionalParams);
                message.setCorrelationId("biosensor-" + System.currentTimeMillis());
                
                String response = sendHttpRequest(message);
                handler.post(() -> {
                    tvResponse.setText("Dane biosensora wysłane:\n" + response);
                    Toast.makeText(MainActivity.this, "Dane biosensora wysłane", Toast.LENGTH_SHORT).show();
                });
            } catch (NumberFormatException e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd formatu liczby: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Nieprawidłowy format liczby", Toast.LENGTH_SHORT).show();
                });
            } catch (Exception e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Błąd komunikacji", Toast.LENGTH_SHORT).show();
                });
            }
        });
    }
    
    /**
     * Wysyła dane biofeedback.
     */
    private void sendBiofeedbackData() {
        String sensorId = etFeedbackSensorId.getText().toString().trim();
        String feedbackType = spinnerFeedbackType.getSelectedItem().toString();
        String valueStr = etFeedbackValue.getText().toString().trim();
        String unit = etFeedbackUnit.getText().toString().trim();
        String sessionId = etSessionId.getText().toString().trim();
        String targetValueStr = etTargetValue.getText().toString().trim();
        String progressPercentStr = etProgressPercent.getText().toString().trim();
        
        if (sensorId.isEmpty() || valueStr.isEmpty()) {
            Toast.makeText(this, "Podaj ID sensora i wartość", Toast.LENGTH_SHORT).show();
            return;
        }
        
        executor.execute(() -> {
            try {
                double value = Double.parseDouble(valueStr);
                
                // Dodatkowe parametry - obsługuje dowolną liczbę pól
                Map<String, Object> additionalParams = new HashMap<>();
                
                if (!targetValueStr.isEmpty()) {
                    additionalParams.put("target_value", Double.parseDouble(targetValueStr));
                }
                if (!progressPercentStr.isEmpty()) {
                    additionalParams.put("progress_percent", Double.parseDouble(progressPercentStr));
                }
                
                // Tworzenie wiadomości z użyciem MedicalMessage
                MedicalMessage message = new MedicalMessage(MedicalMessage.COMMAND_BIOFEEDBACK_DATA, MedicalMessage.SOURCE_BIOFEEDBACK);
                message.setBiofeedbackData(sensorId, feedbackType, value, unit, sessionId, additionalParams);
                message.setCorrelationId("biofeedback-" + System.currentTimeMillis());
                
                String response = sendHttpRequest(message);
                handler.post(() -> {
                    tvResponse.setText("Dane biofeedback wysłane:\n" + response);
                    Toast.makeText(MainActivity.this, "Dane biofeedback wysłane", Toast.LENGTH_SHORT).show();
                });
            } catch (NumberFormatException e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd formatu liczby: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Nieprawidłowy format liczby", Toast.LENGTH_SHORT).show();
                });
            } catch (Exception e) {
                handler.post(() -> {
                    tvResponse.setText("Błąd: " + e.getMessage());
                    Toast.makeText(MainActivity.this, "Błąd komunikacji", Toast.LENGTH_SHORT).show();
                });
            }
        });
    }
    
    /**
     * Wysyła żądanie HTTP do serwera z użyciem MedicalMessage.
     * 
     * @param message Obiekt MedicalMessage do wysłania
     * @return Odpowiedź z serwera
     * @throws Exception Błąd komunikacji
     */
    private String sendHttpRequest(MedicalMessage message) throws Exception {
        String urlString = serverProtocol + "://" + serverHost + ":" + serverPort + apiBasePath + "/command/" + message.getCommand();
        
        URL url = new URL(urlString);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setRequestMethod("POST");
        connection.setRequestProperty("Content-Type", "application/json");
        connection.setConnectTimeout(Integer.parseInt(prefs.getString("connection_timeout", "5000")));
        connection.setReadTimeout(Integer.parseInt(prefs.getString("read_timeout", "10000")));
        connection.setDoOutput(true);
        
        String payload = message.toJson();
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

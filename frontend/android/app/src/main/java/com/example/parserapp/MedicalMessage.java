package com.example.parserapp;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map;
import java.util.UUID;

/**
 * Model wiadomości zgodny z protokołem medical-daemon.
 * Obsługuje dane podmiotowe/przedmiotowe pacjenta, biosensor i biofeedback.
 */
public class MedicalMessage {
    
    // Stałe dla komend
    public static final String COMMAND_PING = "ping";
    public static final String COMMAND_STATUS = "status";
    public static final String COMMAND_PATIENT_DATA = "patient.data";
    public static final String COMMAND_BIOSENSOR_DATA = "biosensor.data";
    public static final String COMMAND_BIOFEEDBACK_DATA = "biofeedback.data";
    public static final String COMMAND_MEDICAL_FHIR = "medical.fhir";
    public static final String COMMAND_MEDICAL_HL7 = "medical.hl7";
    
    // Stałe dla źródeł
    public static final String SOURCE_ANDROID = "frontend";
    public static final String SOURCE_WEBUI = "webui";
    public static final String SOURCE_BIOSENSOR = "biosensor-device";
    public static final String SOURCE_BIOFEEDBACK = "biofeedback-device";
    
    // Wersja protokołu
    private static final String PROTOCOL_VERSION = "1";
    
    private String protocol;
    private String requestId;
    private String source;
    private String command;
    private JSONObject payload;
    private JSONObject meta;
    
    /**
     * Tworzy nową wiadomość z podstawowymi parametrami.
     */
    public MedicalMessage(String command, String source) {
        this.protocol = PROTOCOL_VERSION;
        this.requestId = generateRequestId();
        this.source = source;
        this.command = command;
        this.payload = new JSONObject();
        this.meta = new JSONObject();
        
        // Dodaj timestamp do meta
        try {
            meta.put("timestamp_utc", getUTCTimestamp());
            meta.put("content_type", "application/json");
            meta.put("schema", "medical-daemon-message");
        } catch (JSONException e) {
            e.printStackTrace();
        }
    }
    
    /**
     * Generuje unikalny request ID.
     */
    private String generateRequestId() {
        return UUID.randomUUID().toString();
    }
    
    /**
     * Zwraca aktualny timestamp w formacie ISO 8601 UTC.
     */
    private String getUTCTimestamp() {
        java.text.SimpleDateFormat sdf = new java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
        sdf.setTimeZone(java.util.TimeZone.getTimeZone("UTC"));
        return sdf.format(new java.util.Date());
    }
    
    // ==================== Metody pomocnicze dla Patient Data ====================
    
    /**
     * Konfiguruje payload dla danych pacjenta (podmiotowe/przedmiotowe).
     * 
     * @param patientId Unikalny identyfikator pacjenta
     * @param dataType Typ danych: "podmiotowe" lub "przedmiotowe"
     * @param provider Źródło danych (lekarz, pielęgniarka, itp.)
     * @param data Dane medyczne jako Map<String, Object> - obsługuje dowolną liczbę pól
     * @return Ten obiekt MedicalMessage dla chainingu
     */
    public MedicalMessage setPatientData(String patientId, String dataType, String provider, Map<String, Object> data) {
        try {
            payload.put("patient_id", patientId);
            payload.put("data_type", dataType);
            payload.put("timestamp", getUTCTimestamp());
            payload.put("provider", provider);
            
            // Konwersja Map na JSONObject - obsługuje dowolne pola
            JSONObject jsonData = new JSONObject();
            convertMapToJSON(data, jsonData);
            payload.put("data", jsonData);
            
            // Dodaj patient_id do meta
            meta.put("patient_id", patientId);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Alternatywna metoda dla Patient Data z JSONObject.
     */
    public MedicalMessage setPatientData(String patientId, String dataType, String provider, JSONObject data) {
        try {
            payload.put("patient_id", patientId);
            payload.put("data_type", dataType);
            payload.put("timestamp", getUTCTimestamp());
            payload.put("provider", provider);
            payload.put("data", data);
            meta.put("patient_id", patientId);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    // ==================== Metody pomocnicze dla Biosensor Data ====================
    
    /**
     * Konfiguruje payload dla danych z biosensora.
     * 
     * @param sensorId Identyfikator czujnika
     * @param sensorType Typ sensora (ecg, eeg, emg, spo2, temperature, itp.)
     * @param value Wartość pomiaru
     * @param unit Jednostka pomiaru
     * @param additionalParams Dodatkowe parametry - obsługuje dowolną liczbę pól
     * @return Ten obiekt MedicalMessage dla chainingu
     */
    public MedicalMessage setBiosensorData(String sensorId, String sensorType, double value, 
                                           String unit, Map<String, Object> additionalParams) {
        try {
            payload.put("sensor_id", sensorId);
            payload.put("sensor_type", sensorType);
            payload.put("value", value);
            payload.put("unit", unit);
            payload.put("timestamp", getUTCTimestamp());
            
            // Dodaj dodatkowe parametry (sample_rate, quality, lead, itp.)
            if (additionalParams != null) {
                for (Map.Entry<String, Object> entry : additionalParams.entrySet()) {
                    payload.put(entry.getKey(), entry.getValue());
                }
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Uproszczona wersja dla biosensora bez dodatkowych parametrów.
     */
    public MedicalMessage setBiosensorData(String sensorId, String sensorType, double value, String unit) {
        return setBiosensorData(sensorId, sensorType, value, unit, null);
    }
    
    // ==================== Metody pomocnicze dla Biofeedback Data ====================
    
    /**
     * Konfiguruje payload dla danych biofeedback.
     * 
     * @param sensorId Identyfikator urządzenia
     * @param feedbackType Typ feedbacku (hrv, gsr, temperature, respiration, alpha_waves, itp.)
     * @param value Wartość parametru
     * @param unit Jednostka
     * @param sessionId Identyfikator sesji treningowej
     * @param additionalParams Dodatkowe parametry (target_value, progress_percent, rmssd, sdnn, lf_hf_ratio, itp.)
     * @return Ten obiekt MedicalMessage dla chainingu
     */
    public MedicalMessage setBiofeedbackData(String sensorId, String feedbackType, double value,
                                             String unit, String sessionId, Map<String, Object> additionalParams) {
        try {
            payload.put("sensor_id", sensorId);
            payload.put("feedback_type", feedbackType);
            payload.put("value", value);
            payload.put("unit", unit);
            payload.put("timestamp", getUTCTimestamp());
            payload.put("session_id", sessionId);
            
            // Dodaj dodatkowe parametry
            if (additionalParams != null) {
                for (Map.Entry<String, Object> entry : additionalParams.entrySet()) {
                    payload.put(entry.getKey(), entry.getValue());
                }
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    // ==================== Metody pomocnicze dla FHIR/HL7 ====================
    
    /**
     * Konfiguruje payload dla wiadomości FHIR.
     */
    public MedicalMessage setFHIRData(String resourceType, JSONObject resource) {
        try {
            payload.put("resourceType", resourceType);
            // Scal zasób z payload
            Iterator<String> keys = resource.keys();
            while (keys.hasNext()) {
                String key = keys.next();
                payload.put(key, resource.get(key));
            }
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Konfiguruje payload dla wiadomości HL7.
     */
    public MedicalMessage setHL7Data(String messageType, String rawMessage) {
        try {
            payload.put("message_type", messageType);
            payload.put("raw_message", rawMessage);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    // ==================== Metody wspólne ====================
    
    /**
     * Dodaje patient_id do meta.
     */
    public MedicalMessage setPatientId(String patientId) {
        try {
            meta.put("patient_id", patientId);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Dodaje correlation_id do meta.
     */
    public MedicalMessage setCorrelationId(String correlationId) {
        try {
            meta.put("correlation_id", correlationId);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Ustawia flagę szyfrowania.
     */
    public MedicalMessage setEncryption(boolean encrypted) {
        try {
            meta.put("encryption", encrypted);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Dodaje dowolne pole do payload - dla przyszłych rozszerzeń.
     */
    public MedicalMessage addPayloadField(String key, Object value) {
        try {
            payload.put(key, value);
        } catch (JSONException e) {
            e.printStackTrace();
        }
        return this;
    }
    
    /**
     * Konwertuje Map<String, Object> na JSONObject, obsługując zagnieżdżone struktury.
     */
    private void convertMapToJSON(Map<String, Object> map, JSONObject json) {
        for (Map.Entry<String, Object> entry : map.entrySet()) {
            try {
                Object value = entry.getValue();
                if (value instanceof Map) {
                    JSONObject nestedJson = new JSONObject();
                    convertMapToJSON((Map<String, Object>) value, nestedJson);
                    json.put(entry.getKey(), nestedJson);
                } else if (value instanceof JSONArray) {
                    json.put(entry.getKey(), value);
                } else {
                    json.put(entry.getKey(), value);
                }
            } catch (JSONException e) {
                e.printStackTrace();
            }
        }
    }
    
    /**
     * Serializuje całą wiadomość do JSON String.
     */
    @Override
    public String toString() {
        try {
            JSONObject message = new JSONObject();
            message.put("protocol", protocol);
            message.put("request_id", requestId);
            message.put("source", source);
            message.put("command", command);
            message.put("payload", payload);
            message.put("meta", meta);
            return message.toString(2); // Formatowanie z wcięciami
        } catch (JSONException e) {
            e.printStackTrace();
            return "{}";
        }
    }
    
    /**
     * Zwraca surowy JSON bez formatowania (do wysyłki HTTP).
     */
    public String toJson() {
        try {
            JSONObject message = new JSONObject();
            message.put("protocol", protocol);
            message.put("request_id", requestId);
            message.put("source", source);
            message.put("command", command);
            message.put("payload", payload);
            message.put("meta", meta);
            return message.toString();
        } catch (JSONException e) {
            e.printStackTrace();
            return "{}";
        }
    }
    
    /**
     * Parsuje wiadomość z JSON String.
     */
    public static MedicalMessage fromJson(String jsonString) throws JSONException {
        JSONObject json = new JSONObject(jsonString);
        
        MedicalMessage message = new MedicalMessage(
            json.getString("command"),
            json.getString("source")
        );
        
        message.protocol = json.getString("protocol");
        message.requestId = json.getString("request_id");
        message.payload = json.optJSONObject("payload");
        message.meta = json.optJSONObject("meta");
        
        return message;
    }
    
    // Gettery
    public String getProtocol() { return protocol; }
    public String getRequestId() { return requestId; }
    public String getSource() { return source; }
    public String getCommand() { return command; }
    public JSONObject getPayload() { return payload; }
    public JSONObject getMeta() { return meta; }
}

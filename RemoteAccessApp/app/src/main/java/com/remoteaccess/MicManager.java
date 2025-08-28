package com.remoteaccess;

import android.content.Context;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import androidx.annotation.Nullable;

import org.json.JSONObject; // <-- needed

import java.io.File;
import java.util.concurrent.atomic.AtomicBoolean;

import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;
import okhttp3.WebSocket;
import okhttp3.WebSocketListener;

import okio.ByteString; // <-- needed

public class MicManager {
    private static final String TAG = "RemoteAccessMic";

    private final Context ctx;
    private final OkHttpClient http;
    private final Handler main = new Handler(Looper.getMainLooper());

    // Streaming (AudioRecord -> WS)
    private @Nullable AudioRecord recorder;
    private @Nullable Thread streamThread;
    private final AtomicBoolean streaming = new AtomicBoolean(false);
    private @Nullable WebSocket streamWs;

    // File recording (MediaRecorder -> .m4a)
    private @Nullable MediaRecorder media;
    private final AtomicBoolean recording = new AtomicBoolean(false);

    public MicManager(Context ctx) {
        this.ctx = ctx.getApplicationContext();
        this.http = new OkHttpClient.Builder()
                .retryOnConnectionFailure(true)
                .build();
    }

    // ---------- STREAM PCM → WebSocket ----------
    public synchronized JSONObject startStream(String wsUrl, int sampleRate, int frameMs) {
        JSONObject out = new JSONObject();
        try {
            if (streaming.get()) return out.put("ok", true).put("note", "already streaming");

            int channelConfig = AudioFormat.CHANNEL_IN_MONO;
            int audioFormat   = AudioFormat.ENCODING_PCM_16BIT;
            int minBuf = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat);
            if (minBuf <= 0) minBuf = sampleRate * 2; // ~1s fallback (16-bit mono)

            int frameBytes = (sampleRate * frameMs / 1000) * 2; // 2 bytes/sample
            int bufSize = Math.max(minBuf, frameBytes * 4);

            recorder = new AudioRecord(
                    MediaRecorder.AudioSource.MIC, sampleRate, channelConfig, audioFormat, bufSize);
            if (recorder.getState() != AudioRecord.STATE_INITIALIZED) {
                recorder.release(); recorder = null;
                return out.put("error", "AudioRecord init failed");
            }

            Request req = new Request.Builder().url(wsUrl).build();
            streamWs = http.newWebSocket(req, new WebSocketListener() {
                @Override public void onOpen(WebSocket ws, Response r) {
                    Log.i(TAG, "WS stream open");
                    streaming.set(true);
                    recorder.startRecording();
                    streamThread = new Thread(() -> {
                        byte[] frame = new byte[frameBytes];
                        try {
                            while (streaming.get()) {
                                int want = frame.length, off = 0;
                                while (off < want && streaming.get()) {
                                    int n = recorder.read(frame, off, want - off);
                                    if (n <= 0) break;
                                    off += n;
                                }
                                if (!streaming.get()) break;
                                try {
                                    ws.send(ByteString.of(frame, 0, off));
                                } catch (Throwable ignored) {}
                            }
                        } catch (Throwable t) {
                            Log.w(TAG, "stream loop error: " + t.getMessage());
                        } finally {
                            try { recorder.stop(); } catch (Throwable ignore) {}
                            try { recorder.release(); } catch (Throwable ignore) {}
                            recorder = null;
                            try { ws.close(1000, "done"); } catch (Throwable ignore) {}
                            streamWs = null;
                            streaming.set(false);
                            Log.i(TAG, "stream stopped");
                        }
                    }, "MicStream");
                    streamThread.start();
                }

                @Override public void onFailure(WebSocket ws, Throwable t, @Nullable Response r) {
                    Log.w(TAG, "WS stream failure: " + (t != null ? t.getMessage() : "unknown"));
                    stopStream();
                }

                @Override public void onClosed(WebSocket ws, int code, String reason) {
                    Log.i(TAG, "WS stream closed: " + code + " " + reason);
                    stopStream();
                }
            });

            return out.put("ok", true).put("sampleRate", sampleRate).put("frameMs", frameMs);
        } catch (Throwable t) {
            Log.w(TAG, "startStream error: " + t.getMessage());
            stopStream();
            try { return out.put("error", t.getMessage()); } catch (Exception ignore) {}
            return out;
        }
    }

    public synchronized JSONObject stopStream() {
        JSONObject out = new JSONObject();
        try {
            streaming.set(false);
            if (streamThread != null) { try { streamThread.interrupt(); } catch (Throwable ignore) {} }
            if (recorder != null) {
                try { recorder.stop(); } catch (Throwable ignore) {}
                try { recorder.release(); } catch (Throwable ignore) {}
            }
            if (streamWs != null) { try { streamWs.close(1000, "stop"); } catch (Throwable ignore) {} }
            streamThread = null; recorder = null; streamWs = null;
            return out.put("ok", true);
        } catch (Throwable t) {
            Log.w(TAG, "stopStream error: " + t.getMessage());
            try { return out.put("error", t.getMessage()); } catch (Exception ignore) {}
            return out;
        }
    }

    public boolean isStreaming() { return streaming.get(); }

    // ---------- FILE RECORD → .m4a ----------
    public synchronized JSONObject startRecord(File outFile, int secondsLimit) {
        JSONObject out = new JSONObject();
        try {
            if (recording.get()) return out.put("ok", true).put("note", "already recording");
            if (media != null) { try { media.release(); } catch (Throwable ignore) {} }

            media = new MediaRecorder();
            media.setAudioSource(MediaRecorder.AudioSource.MIC);
            media.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4);
            media.setAudioEncoder(MediaRecorder.AudioEncoder.AAC);
            media.setAudioEncodingBitRate(96_000);
            media.setAudioChannels(1);
            media.setAudioSamplingRate(16_000); // keep in sync with sink defaults
            ensureParent(outFile);
            media.setOutputFile(outFile.getAbsolutePath());
            media.prepare();
            media.start();
            recording.set(true);

            if (secondsLimit > 0) {
                main.postDelayed(this::stopRecord, secondsLimit * 1000L);
            }
            return out.put("ok", true).put("path", outFile.getAbsolutePath());
        } catch (Throwable t) {
            Log.w(TAG, "startRecord error: " + t.getMessage());
            stopRecord();
            try { return out.put("error", t.getMessage()); } catch (Exception ignore) {}
            return out;
        }
    }

    public synchronized JSONObject stopRecord() {
        JSONObject out = new JSONObject();
        try {
            if (media != null) {
                try { media.stop(); } catch (Throwable ignore) {}
                try { media.release(); } catch (Throwable ignore) {}
            }
            media = null;
            recording.set(false);
            return out.put("ok", true);
        } catch (Throwable t) {
            Log.w(TAG, "stopRecord error: " + t.getMessage());
            try { return out.put("error", t.getMessage()); } catch (Exception ignore) {}
            return out;
        }
    }

    public boolean isRecording() { return recording.get(); }

    private static void ensureParent(File f) {
        File p = f.getParentFile();
        if (p != null && !p.exists()) p.mkdirs();
    }
}

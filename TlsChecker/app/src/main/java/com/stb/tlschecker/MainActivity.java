package com.stb.tlschecker;

import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.View;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.appcompat.app.AppCompatActivity;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.security.KeyManagementException;
import java.security.NoSuchAlgorithmException;
import java.security.Provider;
import java.security.Security;
import java.security.cert.Certificate;
import java.security.cert.X509Certificate;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

public class MainActivity extends AppCompatActivity {

    private static final String TAG = "TlsChecker";

    private TextView tvResult;
    private EditText etHost;
    private EditText etPort;
    private Button btnCheck;
    private Button btnCopy;
    private Button btnClear;
    private ScrollView scrollView;

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private final StringBuilder logBuffer = new StringBuilder();

    // Trust-all manager (인증서 검증 없이 핸드셰이크만 테스트)
    private static final TrustManager[] TRUST_ALL = new TrustManager[]{
        new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] c, String a) {}
            public void checkServerTrusted(X509Certificate[] c, String a) {}
        }
    };

    // 테스트할 TLS 버전 목록
    private static final String[] TLS_VERSIONS = {
        "SSLv3", "TLSv1", "TLSv1.1", "TLSv1.2", "TLSv1.3"
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        tvResult  = findViewById(R.id.tvResult);
        etHost    = findViewById(R.id.etHost);
        etPort    = findViewById(R.id.etPort);
        btnCheck  = findViewById(R.id.btnCheck);
        btnCopy   = findViewById(R.id.btnCopy);
        btnClear  = findViewById(R.id.btnClear);
        scrollView = findViewById(R.id.scrollView);

        btnCheck.setOnClickListener(v -> startCheck());
        btnCopy.setOnClickListener(v -> copyToClipboard());
        btnClear.setOnClickListener(v -> clearLog());
    }

    // ─── 메인 진입점 ────────────────────────────────────────────────
    private void startCheck() {
        String host = etHost.getText().toString().trim();
        String portStr = etPort.getText().toString().trim();

        if (host.isEmpty()) {
            toast("호스트를 입력해주세요.");
            return;
        }

        int port;
        try {
            port = Integer.parseInt(portStr);
        } catch (NumberFormatException e) {
            port = 443;
        }

        hideKeyboard();
        btnCheck.setEnabled(false);
        clearLog();

        final int finalPort = port;
        executor.execute(() -> runAllChecks(host, finalPort));
    }

    // ─── 전체 검사 루틴 ─────────────────────────────────────────────
    private void runAllChecks(String host, int port) {
        String ts = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.getDefault()).format(new Date());

        appendLine("╔══════════════════════════════════════════════╗");
        appendLine("║          TLS Checker — BFX-UA300             ║");
        appendLine("╚══════════════════════════════════════════════╝");
        appendLine("실행 시각 : " + ts);
        appendLine("대상 호스트: " + host + ":" + port);
        appendLine("");

        // 1. 디바이스 / 플랫폼 정보
        checkDeviceInfo();

        // 2. Security Provider 목록
        checkSecurityProviders();

        // 3. SSLContext 지원/활성 프로토콜
        checkSSLContextProtocols();

        // 4. 지원 Cipher Suite 목록
        checkCipherSuites();

        // 5. 각 TLS 버전별 실제 핸드셰이크
        for (String ver : TLS_VERSIONS) {
            testHandshake(host, port, ver);
        }

        // 6. 기본 TLS 설정으로 핸드셰이크 (실제 negotiated 버전 확인)
        testDefaultHandshake(host, port);

        appendLine("");
        appendLine("════════════════ 검사 완료 ════════════════");

        mainHandler.post(() -> {
            btnCheck.setEnabled(true);
            scrollToBottom();
        });
    }

    // ─── 1. 디바이스 정보 ────────────────────────────────────────────
    private void checkDeviceInfo() {
        appendLine("┌─ [1] 디바이스 / 플랫폼 정보");
        appendLine("│  Android version : " + android.os.Build.VERSION.RELEASE);
        appendLine("│  API Level       : " + android.os.Build.VERSION.SDK_INT);
        appendLine("│  Device          : " + android.os.Build.MODEL);
        appendLine("│  Board           : " + android.os.Build.BOARD);
        appendLine("│  Hardware        : " + android.os.Build.HARDWARE);
        appendLine("│  Fingerprint     : " + android.os.Build.FINGERPRINT);
        appendLine("└─────────────────────────────────────────────");
        appendLine("");
    }

    // ─── 2. Security Provider ────────────────────────────────────────
    private void checkSecurityProviders() {
        appendLine("┌─ [2] Security Provider 목록");
        Provider[] providers = Security.getProviders();
        for (Provider p : providers) {
            appendLine("│  " + p.getName() + " v" + p.getVersion());
        }
        appendLine("└─────────────────────────────────────────────");
        appendLine("");
    }

    // ─── 3. SSLContext 지원/활성 프로토콜 ───────────────────────────
    private void checkSSLContextProtocols() {
        appendLine("┌─ [3] SSLContext 지원 / 활성 프로토콜");
        try {
            SSLContext ctx = SSLContext.getInstance("TLS");
            ctx.init(null, TRUST_ALL, new java.security.SecureRandom());
            SSLSocketFactory factory = ctx.getSocketFactory();
            SSLSocket socket = (SSLSocket) factory.createSocket();

            String[] supported = socket.getSupportedProtocols();
            String[] enabled   = socket.getEnabledProtocols();

            appendLine("│  [지원 Supported]");
            for (String p : supported) appendLine("│    ✔ " + p);

            appendLine("│  [활성 Enabled]");
            for (String p : enabled)   appendLine("│    ★ " + p);

            socket.close();
        } catch (Exception e) {
            appendLine("│  오류: " + e.getMessage());
        }
        appendLine("└─────────────────────────────────────────────");
        appendLine("");
    }

    // ─── 4. Cipher Suite ─────────────────────────────────────────────
    private void checkCipherSuites() {
        appendLine("┌─ [4] 지원 Cipher Suite (활성화된 것만)");
        try {
            SSLContext ctx = SSLContext.getInstance("TLS");
            ctx.init(null, TRUST_ALL, new java.security.SecureRandom());
            SSLSocketFactory factory = ctx.getSocketFactory();
            SSLSocket socket = (SSLSocket) factory.createSocket();

            String[] enabledCiphers = socket.getEnabledCipherSuites();
            Arrays.sort(enabledCiphers);
            for (String c : enabledCiphers) {
                appendLine("│  " + c);
            }
            socket.close();
        } catch (Exception e) {
            appendLine("│  오류: " + e.getMessage());
        }
        appendLine("└─────────────────────────────────────────────");
        appendLine("");
    }

    // ─── 5. 버전별 실제 핸드셰이크 테스트 ──────────────────────────
    private void testHandshake(String host, int port, String tlsVersion) {
        appendLine("┌─ [핸드셰이크] " + tlsVersion + " → " + host + ":" + port);
        SSLSocket socket = null;
        try {
            SSLContext ctx = SSLContext.getInstance(tlsVersion.equals("SSLv3") ? "SSLv3" : "TLS");
            ctx.init(null, TRUST_ALL, new java.security.SecureRandom());
            SSLSocketFactory factory = ctx.getSocketFactory();

            socket = (SSLSocket) factory.createSocket();
            socket.connect(new InetSocketAddress(host, port), 5000);
            socket.setSoTimeout(5000);
            socket.setEnabledProtocols(new String[]{tlsVersion});
            socket.startHandshake();

            SSLSession session = socket.getSession();
            appendLine("│  ✅ 성공!");
            appendLine("│  negotiated  : " + session.getProtocol());
            appendLine("│  cipher      : " + session.getCipherSuite());
            appendLine("│  server cert : " + getPeerCertInfo(session));

        } catch (SSLHandshakeException e) {
            appendLine("│  ❌ 핸드셰이크 실패: " + e.getMessage());
        } catch (IllegalArgumentException e) {
            appendLine("│  ⚠️  미지원 프로토콜: " + tlsVersion);
        } catch (IOException e) {
            appendLine("│  ❌ 연결 오류: " + e.getMessage());
        } catch (Exception e) {
            appendLine("│  ❌ 오류: " + e.getMessage());
        } finally {
            if (socket != null) {
                try { socket.close(); } catch (IOException ignored) {}
            }
        }
        appendLine("└─────────────────────────────────────────────");
        appendLine("");
    }

    // ─── 6. 기본 설정으로 핸드셰이크 (실제 negotiated 버전) ─────────
    private void testDefaultHandshake(String host, int port) {
        appendLine("┌─ [기본 TLS] 시스템 기본값으로 핸드셰이크");
        SSLSocket socket = null;
        try {
            SSLContext ctx = SSLContext.getDefault();
            SSLSocketFactory factory = ctx.getSocketFactory();

            socket = (SSLSocket) factory.createSocket();
            socket.connect(new InetSocketAddress(host, port), 5000);
            socket.setSoTimeout(5000);
            socket.startHandshake();

            SSLSession session = socket.getSession();
            appendLine("│  ✅ 성공!");
            appendLine("│  negotiated  : " + session.getProtocol());
            appendLine("│  cipher      : " + session.getCipherSuite());
            appendLine("│  peer host   : " + session.getPeerHost());
            appendLine("│  server cert : " + getPeerCertInfo(session));

        } catch (Exception e) {
            appendLine("│  ❌ 오류: " + e.getMessage());
        } finally {
            if (socket != null) {
                try { socket.close(); } catch (IOException ignored) {}
            }
        }
        appendLine("└─────────────────────────────────────────────");
    }

    // ─── 인증서 정보 요약 ────────────────────────────────────────────
    private String getPeerCertInfo(SSLSession session) {
        try {
            Certificate[] certs = session.getPeerCertificates();
            if (certs.length > 0 && certs[0] instanceof X509Certificate) {
                X509Certificate cert = (X509Certificate) certs[0];
                return cert.getSubjectDN().getName()
                       + " (until " + cert.getNotAfter() + ")";
            }
        } catch (Exception e) {
            return "(cert 정보 없음)";
        }
        return "(없음)";
    }

    // ─── 유틸 ─────────────────────────────────────────────────────────
    private void appendLine(String line) {
        Log.d(TAG, line);
        logBuffer.append(line).append("\n");
        mainHandler.post(() -> {
            tvResult.append(line + "\n");
        });
    }

    private void clearLog() {
        logBuffer.setLength(0);
        tvResult.setText("");
    }

    private void scrollToBottom() {
        scrollView.post(() -> scrollView.fullScroll(View.FOCUS_DOWN));
    }

    private void copyToClipboard() {
        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        cm.setPrimaryClip(ClipData.newPlainText("TLS Check Result", logBuffer.toString()));
        toast("클립보드에 복사되었습니다.");
    }

    private void toast(String msg) {
        mainHandler.post(() -> Toast.makeText(this, msg, Toast.LENGTH_SHORT).show());
    }

    private void hideKeyboard() {
        View view = getCurrentFocus();
        if (view != null) {
            InputMethodManager imm = (InputMethodManager) getSystemService(Context.INPUT_METHOD_SERVICE);
            imm.hideSoftInputFromWindow(view.getWindowToken(), 0);
        }
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdownNow();
    }
}

import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyStore;
import java.security.cert.X509Certificate;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

class CheckTrustStore {
    static KeyStore store(Path path) throws Exception {
        var result = KeyStore.getInstance(KeyStore.getDefaultType());
        try (InputStream in = Files.newInputStream(path)) { result.load(in, "changeit".toCharArray()); }
        return result;
    }
    static boolean trusts(KeyStore store, X509Certificate certificate) throws Exception {
        var factory = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        factory.init(store);
        for (var manager : factory.getTrustManagers()) if (manager instanceof X509TrustManager x509) {
            try { x509.checkServerTrusted(new X509Certificate[] { certificate }, "EC"); return true; }
            catch (java.security.cert.CertificateException failure) { return false; }
        }
        throw new IllegalStateException("No X509 trust manager");
    }
    public static void main(String[] args) throws Exception {
        var oldStore = store(Path.of(args[0]));
        var newStore = store(Path.of(args[1]));
        var certificate = (X509Certificate) oldStore.getCertificate("emsigneccrootca-g3");
        if (certificate == null || !trusts(oldStore, certificate) || trusts(newStore, certificate)) {
            throw new IllegalStateException("Unexpected trust decision for the affected root");
        }
        System.out.println("Old system Java truststore accepts the affected emSign G3 root; the updated system Java truststore rejects it.");
        System.out.println("This local default-truststore test does not establish Keycloak's effective DEV configuration or cover other truststores.");
    }
}

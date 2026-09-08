// Run through the authenticated Jenkins Script Console only after provisioning
// a closed Dependency-Check 13.0.0 snapshot in every JVM Gradle cache subdirectory.
import jenkins.model.Jenkins
import hudson.slaves.EnvironmentVariablesNodeProperty

def instance = Jenkins.get()
def properties = instance.globalNodeProperties
def environment = properties.get(EnvironmentVariablesNodeProperty)
if (environment == null) {
    environment = new EnvironmentVariablesNodeProperty()
    properties.add(environment)
}
environment.envVars.put('DEPENDENCY_SECURITY_CACHE_SEED', '/home/gradle/.gradle/dependency-security-seed')
instance.save()
println('JVM dependency security read-only seed configured; per-run advisory refresh remains mandatory.')

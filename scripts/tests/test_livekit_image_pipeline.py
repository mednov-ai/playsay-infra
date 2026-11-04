"""Safety contracts for the LiveKit image-only Jenkins pipeline."""
import pathlib
import unittest
import xml.etree.ElementTree as ET


ROOT = pathlib.Path(__file__).resolve().parents[2]


class LiveKitImagePipelineTest(unittest.TestCase):
    def test_job_is_manual_and_publication_is_off_by_default(self):
        job = ET.parse(ROOT / "jenkins/jobs/playsay-livekit-image.xml").getroot()
        self.assertEqual(len(job.find("triggers")), 0)
        self.assertEqual(job.findtext("definition/scriptPath"), "Jenkinsfile.livekit-image")
        self.assertEqual(
            job.findtext("definition/scm/userRemoteConfigs/hudson.plugins.git.UserRemoteConfig/url"),
            "https://github.com/mednov-ai/playsay-infra.git",
        )
        params = job.find("properties/hudson.model.ParametersDefinitionProperty/parameterDefinitions")
        publish = next(param for param in params if param.findtext("name") == "PUBLISH_CANDIDATE")
        self.assertEqual(publish.findtext("defaultValue"), "false")

    def test_publish_requires_full_scans_archived_before_it_and_cannot_deploy(self):
        pipeline = (ROOT / "Jenkinsfile.livekit-image").read_text()
        checkout = pipeline.index("stage('Checkout exact sources')")
        build = pipeline.index("stage('Build unpublished image')")
        scan = pipeline.index("stage('Scan exact image')")
        publish = pipeline.index("stage('Publish candidate only')")
        self.assertLess(checkout, build)
        self.assertLess(build, scan)
        self.assertLess(scan, publish)
        self.assertIn("scan-livekit-image.sh", pipeline[scan:publish])
        self.assertIn("archiveArtifacts", pipeline[scan:publish])
        self.assertIn("prepare-and-publish-image.sh", pipeline[publish:])
        self.assertIn("params.PUBLISH_CANDIDATE", pipeline[publish:])
        self.assertIn("Security-check branches cannot publish", pipeline)
        self.assertIn("DEPLOY_TO_PROD = 'false'", pipeline)
        self.assertNotIn("kubectl", pipeline)
        self.assertNotIn("update-routed-image-reference", pipeline)
        self.assertNotIn("dev-kubeconfig", pipeline)

    def test_job_is_wired_into_the_supported_jenkins_configurator(self):
        script = (ROOT / "scripts/configure-jenkins-jobs.sh").read_text()
        self.assertIn("  playsay-livekit-image\n", script)
        self.assertIn('"$REPO_ROOT/jenkins/jobs/playsay-livekit-image.xml"', script)


if __name__ == "__main__":
    unittest.main()

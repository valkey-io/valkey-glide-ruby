const fs = require("fs");

module.exports = async function createReleaseDraft({ github, context, core }) {
  const releaseTag = process.env.RELEASE_TAG;
  const releaseVersion = process.env.RELEASE_VERSION;
  // Assumes caller validated the release tag format.
  const isPrerelease = releaseVersion.includes("-rc");
  const releaseName = `Valkey GLIDE Ruby ${releaseTag}`;
  let body;

  if (isPrerelease) {
    body = fs.readFileSync(".github/RELEASE_TEMPLATE/RC_RELEASE_TEMPLATE.md", "utf8");

    // Replace placeholders in the template
    body = body.replaceAll("{{RC_TAG}}", releaseTag);
    body = body.replaceAll("{{RC_VERSION}}", releaseVersion);
    body = body.replaceAll("{{WORKFLOW_RUN_URL}}", process.env.WORKFLOW_RUN_URL);
  } else {
    body = fs.readFileSync(".github/RELEASE_TEMPLATE/RELEASE_TEMPLATE.md", "utf8");
    body = body.replaceAll("{{VERSION}}", releaseTag);
  }

  // Helper
  async function findRelease() {
    try {
      const response = await github.rest.repos.getReleaseByTag({
        ...context.repo,
        tag: releaseTag,
      });
      return response.data;
    } catch (error) {
      if (error.status === 404) {
        return null;
      }
      throw error;
    }
  }

  const existingRelease = await findRelease();
  if (existingRelease) {
    core.info(
      `Release ${releaseTag} already exists. Nothing to do...`,
    );
    return;
  }

  await github.rest.git.getRef({
    ...context.repo,
    ref: `tags/${releaseTag}`,
  });

  const response = await github.rest.repos.createRelease({
    ...context.repo,
    tag_name: releaseTag,
    name: releaseName,
    body,
    draft: true,
    prerelease: isPrerelease,
    generate_release_notes: true,
  });
  core.info(`Created draft release: ${response.data.html_url}`);
};

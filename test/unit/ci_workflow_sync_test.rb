# frozen_string_literal: true

require "test_helper"

# CI-sync guard: single-source .github/workflows/ci.yml's module-tests job
# against utils/run-modules-ci-locally.sh and the test file this job
# actually runs, so the two cannot silently drift apart (the port rules
# require one of these for every port; mirrors
# valkey-glide/python/tests/test_ci_workflow_sync.py's approach). This
# test does not run either script or workflow -- it only asserts that both
# sides reference the same test file, and that the CI job's "Run
# valkey-search 1.3 FT.* tests" step actually exists and targets the file
# the local 3-configuration proof also runs
# (test/integration/modules/ft_1_3_test.rb). A future edit that renames or
# removes the file on one side without mirroring it on the other fails
# here instead of only showing up as a silent CI gap (the exact class of
# finding this guard exists to catch: M2 in QA-W3-RUBY.md found the new
# 1.3 suite wired into the local runner but never into CI at all).
class TestCiWorkflowSync < Minitest::Test
  REPO_ROOT = File.expand_path("../..", __dir__)
  CI_WORKFLOW_FILE = File.join(REPO_ROOT, ".github", "workflows", "ci.yml")
  LOCAL_RUNNER_FILE = File.join(REPO_ROOT, "utils", "run-modules-ci-locally.sh")
  FT_1_3_TEST_PATH = "test/integration/modules/ft_1_3_test.rb"

  def test_ft_1_3_suite_file_exists
    assert File.exist?(File.join(REPO_ROOT, FT_1_3_TEST_PATH)),
           "#{FT_1_3_TEST_PATH} must exist -- both CI and the local runner reference it by this path"
  end

  def test_ci_workflow_module_tests_job_runs_the_1_3_suite
    workflow_text = File.read(CI_WORKFLOW_FILE)
    assert_match(/module-tests:/, workflow_text, "ci.yml must still define the module-tests job")
    assert_includes workflow_text, FT_1_3_TEST_PATH,
                    "ci.yml's module-tests job must run #{FT_1_3_TEST_PATH} -- if the file moved, " \
                    "update ci.yml's \"Run valkey-search 1.3 FT.* tests\" step to match"
  end

  def test_ci_workflow_module_tests_job_passes_both_module_endpoints
    workflow_text = File.read(CI_WORKFLOW_FILE)
    # The comment preceding the step also names the file; skip past it to
    # the `run:` line's own occurrence so the slice below starts at the
    # actual step body, not the explanatory comment above it.
    run_line_index = workflow_text.index("run: bundle exec ruby -Itest -Ilib #{FT_1_3_TEST_PATH}")
    refute_nil run_line_index, "could not find the FT.* 1.3 step's run: line in ci.yml"
    ft13_step = workflow_text[run_line_index..]
    ft13_step = ft13_step[0, ft13_step.index(/\n {6}- name:|\n {2}\S/) || ft13_step.length]
    assert_match(/MODULES_STANDALONE_ENDPOINT/, ft13_step,
                 "the FT.* 1.3 step must forward MODULES_STANDALONE_ENDPOINT (standalone tests read it)")
    assert_match(/MODULES_CLUSTER_ENDPOINTS/, ft13_step,
                 "the FT.* 1.3 step must forward MODULES_CLUSTER_ENDPOINTS (cluster tests read it)")
  end

  def test_local_runner_invokes_rake_test_modules_which_includes_the_1_3_suite
    runner_text = File.read(LOCAL_RUNNER_FILE)
    assert_match(/bundle exec rake test:modules/, runner_text,
                 "utils/run-modules-ci-locally.sh must invoke `rake test:modules`, whose " \
                 "FileList[\"test/integration/modules/**/*_test.rb\"] picks up #{FT_1_3_TEST_PATH} " \
                 "automatically -- if the task name changes, update this guard and the runner together")
  end

  def test_rake_modules_task_file_glob_covers_the_1_3_suite
    rakefile_text = File.read(File.join(REPO_ROOT, "Rakefile"))
    assert_match(%r{integration/modules}, rakefile_text,
                 "the Rakefile's test:modules task must still glob test/integration/modules/**/*_test.rb")
  end
end

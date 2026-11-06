require "spec_helper"
require "etc"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "shellwords"
require "tmpdir"

RSpec.describe "bin/deploy-production" do
  let(:script_path) { Pathname.new(File.expand_path("../../bin/deploy-production", __dir__)) }

  it "has valid bash syntax" do
    stdout, status = Open3.capture2e("bash", "-n", script_path.to_s)

    expect(status.success?).to be(true), <<~MESSAGE
      Expected #{script_path} to pass bash -n.
      Output:
      #{stdout}
    MESSAGE
  rescue Errno::ENOENT
    skip "bash is not available in this environment"
  end

  it "documents the production deploy defaults and safety controls" do
    stdout, status = Open3.capture2e(script_path.to_s, "--help")

    expect(status.success?).to be(true)
    expect(stdout).to include("APP_ROOT=/home/esquarenews/apps/notae")
    expect(stdout).to include("ENV_FILE=/etc/notae/notae.env")
    expect(stdout).to include("RUNTIME_ENV_FILE=/etc/notae/ruby-3.4.12.env")
    expect(stdout).to include("--check")
    expect(stdout).to include("RUN_TESTS=1")
    expect(stdout).to include("RESTART_TIMERS=0")
    expect(stdout).to include('OPTIONAL_TIMERS="notae-kalendarium-sync.timer"')
    expect(stdout).to include('OPTIONAL_ONESHOTS="notae-kalendarium-sync.service"')
    expect(stdout).not_to include("epistularium", "calendar/mail")
  end

  it "only schedules calendar sync units by default after retiring email" do
    source = script_path.read.sub(/^main "\$@"\s*\z/, "")
    stdout, status = Open3.capture2e(
      { "OPTIONAL_TIMERS" => nil, "OPTIONAL_ONESHOTS" => nil },
      "bash", "-c", source + "\n" + 'printf "%s\\n" "$OPTIONAL_TIMERS" "$OPTIONAL_ONESHOTS"'
    )

    expect(status.success?).to be(true), stdout
    expect(stdout.lines.map(&:strip)).to eq([
      "notae-kalendarium-sync.timer",
      "notae-kalendarium-sync.service"
    ])
  end

  it "checks systemd unit existence through LoadState resolution" do
    source = script_path.read

    expect(source).to include("systemctl show")
    expect(source).to include("-p LoadState --value")
    expect(source).to include('[[ "$load_state" == "loaded" ]]')
    expect(source).not_to include("list-unit-files")
  end

  it "runs the full workflow with the configured runtime and forwards it to every production job" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture)

      expect(status.success?).to be(true), stdout
      expect(stdout).to include("Deployment complete: before -> release")
      bundle_calls = calls.select { |call| call["command"] == "bundle" }
      expect(bundle_calls).not_to be_empty
      expect(bundle_calls.map { |call| call["program"] }.uniq).to eq([ fixture[:bundle] ])
      expect(bundle_calls.map { |call| call["runtime_loaded"] }.uniq).to eq([ "yes" ])

      jobs = calls.select { |call| call["command"] == "systemd-run" }
      expect(jobs.length).to eq(2)
      jobs.each do |job|
        expect(job["argv"]).to include("EnvironmentFile=#{fixture[:runtime_env]}", "EnvironmentFile=#{fixture[:env]["ENV_FILE"]}", fixture[:bundle])
        expect(job["argv"]).not_to include("/usr/bin/bash", "-lc")
      end
      expect(jobs[0]["argv"].last(4)).to eq([ fixture[:bundle], "exec", "rails", "db:migrate" ])
      expect(jobs[1]["argv"].last(5)).to eq([ fixture[:bundle], "exec", "rails", "assets:clobber", "assets:precompile" ])

      milestones = [
        calls.index { |call| call["command"] == "sudo" && call["argv"] == [ "-v" ] },
        calls.index { |call| call["command"] == "git" && call["argv"].first == "fetch" },
        calls.index { |call| call["command"] == "bundle" && call["argv"] == [ "install" ] },
        calls.index { |call| call["command"] == "systemctl" && call["argv"] == [ "stop", "notae-sidekiq" ] },
        calls.index(jobs[0]),
        calls.index(jobs[1]),
        calls.index { |call| call["command"] == "systemctl" && call["argv"] == [ "restart", "notae" ] },
        calls.index { |call| call["command"] == "curl" }
      ]
      expect(milestones).to all(be_a(Integer))
      expect(milestones).to eq(milestones.sort)
    end
  end

  it "checks the runtime, lock, services and HTTP assets without deploying or requesting sudo" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, "--check")

      expect(status.success?).to be(true), stdout
      expect(stdout).to include("Deployment checks passed")
      expect(calls.map { |call| call["command"] }).not_to include("sudo", "systemd-run")
      expect(calls.select { |call| call["command"] == "git" }.map { |call| call["argv"].first }).not_to include("fetch", "pull", "checkout")
      expect(calls.select { |call| call["command"] == "bundle" }.map { |call| call["argv"] }).to include([ "check" ])
      expect(calls.select { |call| call["command"] == "bundle" }.map { |call| call["argv"].first }).not_to include("install", "config")
      expect(calls.select { |call| call["command"] == "systemctl" }.map { |call| call["argv"].first }).to all(eq("show"))
      expect(calls.count { |call| call["command"] == "curl" }).to eq(4)
      expect(File.read(fixture[:revision])).to eq("before")
    end
  end

  it "installs test dependencies and runs both test commands in the test environment when requested" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, env: { "RUN_TESTS" => "1" })

      expect(status.success?).to be(true), stdout
      install = calls.find { |call| call["command"] == "bundle" && call["argv"] == [ "install" ] }
      expect(install["bundle_without"]).to eq("")
      test_calls = calls.select { |call| call["command"] == "bundle" && [ [ "exec", "rails", "db:prepare" ], [ "exec", "rspec" ] ].include?(call["argv"]) }
      expect(test_calls.length).to eq(2)
      expect(test_calls.map { |call| call["rails_env"] }).to eq([ "test", "test" ])
    end
  end

  it "fails before changing production when its runtime environment is missing" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, env: { "RUNTIME_ENV_FILE" => "#{fixture[:root]}/missing.env" })

      expect(status.success?).to be(false)
      expect(stdout).to include("Runtime env file is not readable")
      expect(calls).to be_empty
    end
  end

  it "rejects a root or other user invocation before creating a shared lock" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, env: { "APP_USER" => "another-deploy-user" })

      expect(status.success?).to be(false)
      expect(stdout).to include("Run this script as another-deploy-user")
      expect(File.exist?(fixture[:env]["LOCK_FILE"])).to be(false)
      expect(calls).to be_empty
    end
  end

  it "refuses symlink locks without modifying their target" do
    with_deploy_fixture do |fixture|
      target = File.join(fixture[:root], "unrelated-file")
      File.write(target, "preserve me")
      File.symlink(target, fixture[:env]["LOCK_FILE"])
      stdout, status, = run_deploy(fixture)

      expect(status.success?).to be(false)
      expect(stdout).to include("Refusing a symlink deploy lock")
      expect(File.read(target)).to eq("preserve me")
    end
  end

  it "stops before fetching or changing services when another deployment holds the lock" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, env: { "DEPLOY_TEST_LOCK_BUSY" => "1" })

      expect(status.success?).to be(false)
      expect(stdout).to include("Another deploy is already running")
      expect(calls.map { |call| call["command"] }).to eq([ "flock" ])
    end
  end

  it "rejects a service runtime mismatch before installing gems or restarting services" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, env: { "DEPLOY_TEST_SERVICE_MISMATCH" => "1" })

      expect(status.success?).to be(false)
      expect(stdout).to include("does not load runtime env file")
      expect(calls.map { |call| call["command"] }).not_to include("sudo", "bundle", "systemd-run", "curl")
      expect(calls.select { |call| call["command"] == "git" }.map { |call| call["argv"].first }).not_to include("fetch", "pull", "checkout")
    end
  end

  it "preserves a dirty production checkout without fetching or authenticating for service changes" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, env: { "DEPLOY_TEST_DIRTY" => "1" })

      expect(status.success?).to be(false)
      expect(stdout).to include("Working tree is dirty")
      expect(calls.map { |call| call["command"] }).not_to include("sudo", "bundle", "systemd-run", "curl")
      expect(calls.select { |call| call["command"] == "git" }.map { |call| call["argv"].first }).not_to include("fetch", "pull", "checkout")
      expect(File.read(fixture[:revision])).to eq("before")
    end
  end

  it "rejects an unsupported option before starting a deployment" do
    with_deploy_fixture do |fixture|
      stdout, status, calls = run_deploy(fixture, "--dry-run")

      expect(status.exitstatus).to eq(2)
      expect(stdout).to include("Use --check")
      expect(calls).to be_empty
      expect(File.exist?(fixture[:env]["LOCK_FILE"])).to be(false)
    end
  end

  def run_deploy(fixture, *args, env: {})
    stdout, status = Open3.capture2e(fixture[:env].merge(env), script_path.to_s, *args)
    calls = File.exist?(fixture[:log]) ? File.readlines(fixture[:log]).map { |line| JSON.parse(line) } : []
    [ stdout, status, calls ]
  end

  def with_deploy_fixture
    Dir.mktmpdir("notae-deploy-") do |root|
      shim = File.join(root, "shim")
      runtime_bin = File.join(root, "runtime", "bin")
      app_root = File.join(root, "app")
      FileUtils.mkdir_p([ shim, runtime_bin, File.join(app_root, ".git") ])
      File.write(File.join(app_root, "Gemfile"), "")
      log = File.join(root, "calls.jsonl")
      revision = File.join(root, "revision")
      File.write(revision, "before")
      dispatcher = File.join(root, "dispatch")
      File.write(dispatcher, "#!#{RbConfig.ruby}\n" + <<~'RUBY')
        require "json"
        command = File.basename($PROGRAM_NAME)
        File.open(ENV.fetch("DEPLOY_TEST_LOG"), "a") do |file|
          file.puts JSON.generate(command: command, program: $PROGRAM_NAME, argv: ARGV, runtime_loaded: ENV["DEPLOY_RUNTIME_LOADED"], bundle_without: ENV["BUNDLE_WITHOUT"], rails_env: ENV["RAILS_ENV"])
        end
        case command
        when "git"
          if ARGV.first == "status" && ENV["DEPLOY_TEST_DIRTY"] == "1"
            puts " M app/unrelated_work.rb"
          elsif ARGV == ["rev-parse", "--show-toplevel"]
            puts ENV.fetch("APP_ROOT")
          elsif ARGV == ["rev-parse", "HEAD"]
            puts File.read(ENV.fetch("DEPLOY_TEST_REVISION"))
          elsif ARGV.first == "pull"
            File.write(ENV.fetch("DEPLOY_TEST_REVISION"), "release")
          end
        when "flock"
          exit 1 if ENV["DEPLOY_TEST_LOCK_BUSY"] == "1"
        when "sudo"
          exec(*ARGV) unless ARGV == ["-v"]
        when "systemctl"
          if ARGV.include?("LoadState")
            puts "loaded"
          elsif ARGV.include?("EnvironmentFiles")
            puts(ENV["DEPLOY_TEST_SERVICE_MISMATCH"] == "1" ? "/other-runtime.env" : ENV.fetch("RUNTIME_ENV_FILE"))
          elsif ARGV.include?("ExecStart")
            puts "path=#{ENV.fetch('DEPLOY_TEST_BUNDLE')}"
          elsif ARGV.include?("--value")
            puts(ARGV.include?("Result") ? "success" : "active")
          end
        when "curl"
          puts '<link href="/assets/application-test.css"><script src="/assets/application-test.js"></script>' if ARGV.last.end_with?("/users/sign_in")
        end
      RUBY
      File.chmod(0o755, dispatcher)
      %w[git flock sudo systemctl systemd-run curl].each { |name| File.symlink(dispatcher, File.join(shim, name)) }
      bundle = File.join(runtime_bin, "bundle")
      File.symlink(dispatcher, bundle)
      File.write(File.join(shim, "bundle"), "#!/bin/sh\necho 'Wrong login-shell bundle selected' >&2\nexit 70\n")
      File.chmod(0o755, File.join(shim, "bundle"))
      runtime_env = File.join(root, "runtime.env")
      File.write(runtime_env, "PATH=#{Shellwords.escape("#{runtime_bin}:#{shim}:#{ENV.fetch('PATH')}")}\nDEPLOY_RUNTIME_LOADED=yes\nBUNDLE_WITHOUT=development:test\n")
      env_file = File.join(root, "production.env")
      File.write(env_file, "")
      env = ENV.keys.grep(/\ABUNDLE_/).to_h { |key| [ key, nil ] }.merge(
        "RUBYOPT" => nil, "RUBYLIB" => nil, "RAILS_ENV" => nil,
        "PATH" => "#{shim}:#{ENV.fetch('PATH')}", "PRODUCTION_PATH" => nil,
        "APP_ROOT" => app_root, "APP_USER" => Etc.getpwuid(Process.uid).name,
        "ENV_FILE" => env_file, "RUNTIME_ENV_FILE" => runtime_env,
        "LOCK_FILE" => File.join(root, "deploy.lock"),
        "RUN_TESTS" => "0", "RUN_ASSET_CLOBBER" => "1", "RUN_OPTIONAL_SYNC" => "1", "RESTART_TIMERS" => "1",
        "REQUIRED_SERVICES" => "notae", "OPTIONAL_SERVICES" => "notae-sidekiq notae-meeting-bot-worker",
        "OPTIONAL_TIMERS" => "notae-kalendarium-sync.timer", "OPTIONAL_ONESHOTS" => "notae-kalendarium-sync.service",
        "DEPLOY_TEST_LOG" => log, "DEPLOY_TEST_REVISION" => revision, "DEPLOY_TEST_BUNDLE" => bundle
      )
      yield root: root, env: env, log: log, revision: revision, runtime_env: runtime_env, bundle: bundle
    end
  end
end

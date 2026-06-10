# frozen_string_literal: true

require "open3"

class Valkey
  class TestCluster
    class ScriptNotFoundError < StandardError; end

    class PythonNotFoundError < StandardError; end

    class ClusterStartError < StandardError; end

    class OutputParseError < StandardError; end

    attr_reader :addresses, :cluster_folder, :tls_cert_path, :tls_key_path, :tls_ca_cert_path

    def initialize(
      cluster_mode: false,
      tls: false,
      shard_count: 3,
      replica_count: 1,
      load_module: nil,
      addresses: nil
    )
      @cluster_mode = cluster_mode
      @tls = tls
      @shard_count = shard_count
      @replica_count = replica_count
      @load_module = load_module
      @cluster_folder = nil
      @tls_cert_path = nil
      @tls_key_path = nil
      @tls_ca_cert_path = nil

      if addresses
        @addresses = addresses
      else
        start_cluster
        ObjectSpace.define_finalizer(self, self.class.cleanup_proc(@cluster_folder, @tls))
      end
    end

    def close
      return unless @cluster_folder

      ObjectSpace.undefine_finalizer(self)

      cmd = ["python3", script_path]
      cmd << "--tls" if @tls
      cmd += ["stop", "--cluster-folder", @cluster_folder]

      system(*cmd, out: File::NULL, err: File::NULL)

      @cluster_folder = nil
      @addresses = nil
    end

    def self.build_stop_command(cluster_folder, tls:)
      root_dir = File.expand_path("../..", __dir__)
      script = File.join(root_dir, "valkey-glide", "utils", "cluster_manager.py")
      cmd = ["python3", script]
      cmd << "--tls" if tls
      cmd += ["stop", "--cluster-folder", cluster_folder]
      cmd
    end

    def self.cleanup_proc(cluster_folder, tls)
      proc do
        return unless cluster_folder

        root_dir = File.expand_path("../..", __dir__)
        script = File.join(root_dir, "valkey-glide", "utils", "cluster_manager.py")
        return unless File.exist?(script)

        cmd = ["python3", script]
        cmd << "--tls" if tls
        cmd += ["stop", "--cluster-folder", cluster_folder]
        system(*cmd, out: File::NULL, err: File::NULL)
      end
    end

    def self.build_start_args(script_path:, cluster_mode:, tls:, shard_count:, replica_count:, load_module:)
      [
        "python3",
        script_path,
        *(tls ? ["--tls"] : []),
        "start",
        *(cluster_mode ? ["--cluster-mode"] : []),
        "-n", shard_count.to_s,
        "-r", replica_count.to_s,
        *load_module&.flat_map { |m| ["--load-module", m] }
      ]
    end

    def self.parse_output(output)
      cluster_folder = extract_output_value(output, "CLUSTER_FOLDER")
      cluster_nodes = extract_output_value(output, "CLUSTER_NODES")

      raise OutputParseError, "Missing CLUSTER_FOLDER in output" unless cluster_folder
      raise OutputParseError, "Missing CLUSTER_NODES in output" unless cluster_nodes

      addresses = parse_cluster_nodes(cluster_nodes)

      { cluster_folder: cluster_folder, addresses: addresses }
    end

    class << self
      private

      def extract_output_value(output, key)
        match = output.match(/^#{key}=(.+)$/)
        match&.[](1)&.strip
      end

      def parse_cluster_nodes(nodes_str)
        nodes_str.split(",").map do |node|
          parts = node.strip.rpartition(":")
          host = parts[0]
          port_str = parts[2]
          raise OutputParseError, "Invalid node format: #{node}" if host.empty? || port_str.empty?

          { host: host, port: port_str.to_i }
        end
      end
    end

    private

    def start_cluster
      check_python_available
      path = script_path

      cmd = self.class.build_start_args(
        script_path: path,
        cluster_mode: @cluster_mode,
        tls: @tls,
        shard_count: @shard_count,
        replica_count: @replica_count,
        load_module: @load_module
      )

      stdout, stderr, status = Open3.capture3(*cmd)

      raise ClusterStartError, "cluster_manager.py failed: #{stderr}" unless status.success?

      result = self.class.parse_output(stdout)
      @cluster_folder = result[:cluster_folder]
      @addresses = result[:addresses]

      return unless @tls

      root_dir = File.expand_path("../..", __dir__)
      @tls_cert_path = File.join(root_dir, "valkey-glide", "utils", "tls_crts", "server.crt")
      @tls_key_path = File.join(root_dir, "valkey-glide", "utils", "tls_crts", "server.key")
      @tls_ca_cert_path = File.join(root_dir, "valkey-glide", "utils", "tls_crts", "ca.crt")
    end

    def script_path
      root_dir = File.expand_path("../..", __dir__)
      submodule_dir = File.join(root_dir, "valkey-glide")
      path = File.join(submodule_dir, "utils", "cluster_manager.py")

      unless Dir.exist?(submodule_dir) && Dir.children(submodule_dir).any?
        raise ScriptNotFoundError,
              "valkey-glide submodule not initialized at #{submodule_dir}. " \
              "Run: git submodule update --init --recursive"
      end

      unless File.exist?(path)
        raise ScriptNotFoundError,
              "cluster_manager.py not found at #{path}. " \
              "Ensure the valkey-glide submodule is up to date: git submodule update --init --recursive"
      end

      path
    end

    def check_python_available
      success = system("python3", "--version", out: File::NULL, err: File::NULL)
      return if success

      raise PythonNotFoundError,
            "Python 3 is required but not found. " \
            "Please install Python 3 and ensure 'python3' is available in your PATH."
    end
  end
end

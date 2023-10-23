module Rack
  class MiniProfiler
    module ClassMethods
      def self.extended(base)
        base.extend Rack::MiniProfiler::ProfilingMethods

        class << base
          attr_accessor :subscribe_sql_active_record
        end
      end

      def patch_rails?
        !!defined?(Rack::MINI_PROFILER_ENABLE_RAILS_PATCHES)
      end

      def generate_id
        rand(36**20).to_s(36)
      end

      def reset_config
        @config = Config.default
      end

      # So we can change the configuration if we want
      def config
        @config ||= Config.default
      end

      def resources_root
        @resources_root ||= ::File.expand_path("../html", __FILE__)
      end

      def share_template
        @share_template ||= ERB.new(::File.read(::File.expand_path("html/share.html", ::File.dirname(__FILE__))))
      end

      def current
        Thread.current[:mini_profiler_private]
      end

      def current=(c)
        # we use TLS cause we need access to this from sql blocks and code blocks that have no access to env
        Thread.current[:mini_profiler_snapshot_custom_fields] = nil
        Thread.current[:mp_ongoing_snapshot] = nil
        Thread.current[:mini_profiler_private] = c
      end

      def add_snapshot_custom_field(key, value)
        thread_var_key = :mini_profiler_snapshot_custom_fields
        Thread.current[thread_var_key] ||= {}
        Thread.current[thread_var_key][key] = value
      end

      def get_snapshot_custom_fields
        Thread.current[:mini_profiler_snapshot_custom_fields]
      end

      # discard existing results, don't track this request
      def discard_results
        self.current.discard = true if current
      end

      def create_current(env = {}, options = {})
        # profiling the request
        context               = Context.new
        context.inject_js     = config.auto_inject && (!env['HTTP_X_REQUESTED_WITH'].eql? 'XMLHttpRequest')
        context.page_struct   = TimerStruct::Page.new(env)
        context.current_timer = context.page_struct[:root]
        self.current          = context
      end

      def authorize_request
        Thread.current[:mp_authorized] = true
      end

      def deauthorize_request
        Thread.current[:mp_authorized] = nil
      end

      def request_authorized?
        Thread.current[:mp_authorized]
      end

      def advanced_tools_message
        <<~TEXT
          This feature is disabled by default, to enable set the enable_advanced_debugging_tools option to true in Mini Profiler config.
        TEXT
      end

      def binds_to_params(binds)
        return if binds.nil? || config.max_sql_param_length == 0
        # map ActiveRecord::Relation::QueryAttribute to [name, value]
        params = binds.map { |c| c.kind_of?(Array) ? [c.first, c.last] : [c.name, c.value] }
        if (skip = config.skip_sql_param_names)
          params.map { |(n, v)| n =~ skip ? [n, nil] : [n, v] }
        else
          params
        end
      end

      def snapshots_transporter?
        !!config.snapshots_transport_destination_url &&
        !!config.snapshots_transport_auth_key
      end

      def redact_sql_queries?
        Thread.current[:mp_ongoing_snapshot] == true &&
        Rack::MiniProfiler.config.snapshots_redact_sql_queries
      end
    end
  end
end

module RedmineProjectImporter
  class ContextManager
    attr_reader :source_project, :executed_at, :DEFAULTS
    attr_accessor :target_project, :mappings, :headers, :warnings, :errors, :options, :issue_id_map, :version_id_map, :summary

    DEFAULTS = {
      roles_mapping: {},           # ロールマッピング (例: { source_role_id: { target_role_id: 移行先ID } })
      groups_mapping: {},          # グループマッピング (例: { source_group_id: { target_group_id: 移行先ID, roles: [ロールID] } })
      members_mapping: {},         # ユーザーマッピング (例: { source_user_id: { email_address: メールアドレス, target_user_id: 移行先ユーザID } })
      trackers_mapping: {},        # トラッカーマッピング
      statuses_mapping: {},        # チケットステータスマッピング
      custom_fields_mapping: {}    # カスタムフィールドのマッピング
    }.freeze
    
    def initialize(source_project)
      logger.debug("Initializing ContextManager with source_project: #{source_project.id}")
      @headers = {
        tool_version: fetch_tool_version # プラグインのバージョンを取得
      }
      @executed_at = Time.now # 実行日時をインスタンス変数に保存
      logger.debug("ContextManager initialized with headers: #{@headers}, executed_at: #{@executed_at}")
      @source_project = source_project
      @target_project = nil
      @mappings = DEFAULTS.dup # DEFAULTS を複製して代入
      @warnings = []
      @errors = []
      @options = {}
      @issue_id_map = {} # 初期化
      @version_id_map = {} # バージョンIDマッピングを初期化
      @summary = {} # サマリデータを初期化
    end

    def logger
      @logger ||= RedmineProjectImporter.logger
    end

    # サマリデータをストアするメソッド
    def store_summary(summary_data)
      @summary = summary_data
      logger.debug("Summary data stored: #{@summary}")
    end

    def add_warning(warning)
      @warnings << warning

      # `:message` を取り出し、残りのキーと値をフォーマット
      message = warning[:message]
      additional_info = warning.reject { |key, _| key == :message }
                               .map { |key, value| "#{key}: #{value}" }
                               .join(", ")

      # ログに出力
      if additional_info.empty?
        logger.warn("      Warning: #{message}")
      else
        logger.warn("      Warning: #{message} (#{additional_info})")
      end
    end

    def add_error(error)
      @errors << error

      # `:message` を取り出し、残りのキーと値をフォーマット
      message = error[:message]
      additional_info = error.reject { |key, _| key == :message }
                             .map { |key, value| "#{key}: #{value}" }
                             .join(", ")

      # ログに出力
      if additional_info.empty?
        logger.error("      Error: #{message}")
      else
        logger.error("      Error: #{message} (#{additional_info})")
      end
    end

    def clear_warnings
      @warnings.clear
      logger.debug("Warnings cleared")
    end

    def clear_errors
      @errors.clear
      logger.debug("Errors cleared")
    end

    def generate_mappings
      logger.info("  Generating mappings for project ID: #{@source_project.id}")
      roles_result = Mappers::RoleMapper.generate(self)
      @mappings[:roles_mapping] = roles_result[:mappings]

      groups_result = Mappers::GroupMapper.generate(self)
      @mappings[:groups_mapping] = groups_result[:mappings]

      members_result = Mappers::MemberMapper.generate(self)
      @mappings[:members_mapping] = members_result[:mappings]

      trackers_result = Mappers::TrackerMapper.generate(self)
      @mappings[:trackers_mapping] = trackers_result[:mappings]

      statuses_result = Mappers::StatusMapper.generate(self)
      @mappings[:statuses_mapping] = statuses_result[:mappings]

      custom_fields_result = Mappers::CustomFieldMapper.generate(self)
      @mappings[:custom_fields_mapping] = custom_fields_result[:mappings]
    end

    # データをストアするメソッド
    def store_data(data)
      @mappings = data[:mappings] || {}
      @headers = data[:headers] || {}
      @warnings = data[:warnings] || []
      @errors = data[:errors] || []
      @options = data[:options] || {}
    end

    private

    def fetch_tool_version
      # Redmine のプラグイン情報からバージョンを取得
      plugin = Redmine::Plugin.find(:redmine_project_importer)
      plugin.version
    rescue StandardError => e
      logger.error("Failed to fetch plugin version: #{e.message}")
      'unknown' # バージョンが取得できない場合のデフォルト値
    end
  end
end
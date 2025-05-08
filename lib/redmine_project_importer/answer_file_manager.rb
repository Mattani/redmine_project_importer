# lib/redmine_project_importer/answer_file_manager.rb
module RedmineProjectImporter
  ANSWER_FILE_NAME_TEMPLATE = "redmine_project_importer.answer.%{identifier}.yml"

  class AnswerFileManager
    require 'yaml'

    attr_reader :file_path, :data, :context_mgr

    def initialize(context_mgr)
      @context_mgr = context_mgr
      @data = RedmineProjectImporter::ContextManager::DEFAULTS

      # ユーザーファイルのパスを環境変数から取得
      user_file_path = ENV['REDMINE_PROJECT_IMPORTER_USER_FILE_PATH'] || Dir.pwd
      @file_path = File.join(user_file_path, ANSWER_FILE_NAME_TEMPLATE % { identifier: context_mgr.source_project.identifier })
    end

    def logger
      @logger ||= RedmineProjectImporter.logger
    end

    # アンサーファイルを読み込む
    def load
      logger.debug("load: #{@file_path}")
      if File.exist?(@file_path)
        raw_data = YAML.safe_load(
          File.read(@file_path),
          permitted_classes: [Symbol],
          symbolize_names: true
        ) || {}
        @data = raw_data.transform_values { |v| v.nil? ? {} : v }
        validate!

        # @data を context_mgr にストア
        context_mgr.store_data(@data)
      else
        logger.error("Answer file not found: #{@file_path}")
        raise "Answer file not found: #{@file_path}"
      end
    end

    # @dataの内容でアンサーファイルを作成する
    def create_answer_file
      logger.debug("create_answer_file: #{@file_path}")
      logger.debug context_mgr.mappings if context_mgr.mappings.present?

      @data = context_mgr.mappings if context_mgr.mappings.present?

      # コメント付きYAMLを生成
      yaml_with_comments = <<~YAML
        # Redmine Project Importer Answer File
        headers:
        #{generate_comment_block(context_mgr.headers || {})}

        mappings:
        # マッピング情報
          groups_mapping:
          # グループユーザーのマッピング
          # source_group_id:
          #   group_name: グループ名
          #   target_group_id: 移行先のグループID
          #   roles: [ロールIDの配列]
        #{generate_comment_block(@data[:groups_mapping])}

          members_mapping:
          # ユーザーのマッピング
          # source_user_id:
          #   email_address: メールアドレス
          #   target_user_id: 移行先のユーザID
          #   roles: [ロールIDの配列]
        #{generate_comment_block(@data[:members_mapping])}

          trackers_mapping:
          # トラッカーのマッピング
          # source_tracker_id:
          #   target_tracker_id: 移行先のトラッカーID
          #   target_tracker_name: 移行先のトラッカー名
        #{generate_comment_block(@data[:trackers_mapping])}

          statuses_mapping:
          # チケットステータスのマッピング
          # source_status_id:
          #   target_status_id: 移行先のステータスID
          #   target_status_name: 移行先のステータス名
        #{generate_comment_block(@data[:statuses_mapping])}

          custom_fields_mapping:
          # カスタムフィールドのマッピング
          # source_custom_field_id:
          #   custom_field_name: カスタムフィールド名
          #   trackers: [トラッカー名の配列]
          #   target_id: 移行先のカスタムフィールドID
        #{generate_comment_block(@data[:custom_fields_mapping])}
      YAML

      # warnings, errors, options をデータがある場合のみ追加
      yaml_with_comments += <<~YAML if context_mgr.warnings.present?
        warnings:
        # 警告メッセージ
        #{generate_list_block(context_mgr.warnings)}
      YAML

      yaml_with_comments += <<~YAML if context_mgr.errors.present?
        errors:
        # エラーメッセージ
        #{generate_list_block(context_mgr.errors)}
      YAML

      yaml_with_comments += <<~YAML if context_mgr.options.present?
        options:
        # オプション情報
        #{generate_comment_block(context_mgr.options)}
      YAML

      logger.debug("YAML with comments:\n#{yaml_with_comments}")
      # ファイルに書き込む
      File.write(@file_path, yaml_with_comments)
      logger.info("Answer file created: #{@file_path}")

      # 成功した場合 true を返す
      true
    end

    private

    # データのバリデーション
    def validate!
      missing_keys = RedmineProjectImporter::ContextManager::DEFAULTS.keys - data.keys
      return if missing_keys.empty?

      raise "Answer file is missing required keys: #{missing_keys.join(', ')}"
    end

    def validate!
      # 必須のトップレベルキー
      required_top_level_keys = %i[headers mappings]
      optional_top_level_keys = %i[warnings errors options]
      allowed_top_level_keys = required_top_level_keys + optional_top_level_keys

      # mappings の必須キー
      required_mappings_keys = %i[groups_mapping members_mapping trackers_mapping statuses_mapping custom_fields_mapping]

      # トップレベルキーの検証
      missing_keys = required_top_level_keys - @data.keys
      raise "Answer file is missing required keys: #{missing_keys.join(', ')}" unless missing_keys.empty?

      extra_keys = @data.keys - allowed_top_level_keys
      raise "Answer file contains unexpected keys: #{extra_keys.join(', ')}" unless extra_keys.empty?

      # mappings の検証
      mappings = @data[:mappings]
      raise "Answer file is missing 'mappings' section" if mappings.nil? || !mappings.is_a?(Hash)

      missing_mappings_keys = required_mappings_keys - mappings.keys
      raise "Mappings section is missing required keys: #{missing_mappings_keys.join(', ')}" unless missing_mappings_keys.empty?

      # headers の検証
      headers = @data[:headers]
      raise "Answer file is missing 'headers' section" if headers.nil? || !headers.is_a?(Hash)

      tool_version = headers[:tool_version]
      raise "Answer file is missing 'tool_version' in headers" if tool_version.nil?

      # 現在のツールバージョンを ContextManager から取得
      current_version = context_mgr.headers[:tool_version]
      current_major_version = current_version.split('.').first
      file_major_version = tool_version.split('.').first

      if current_major_version != file_major_version
        raise "Tool version mismatch: expected major version #{current_major_version}, but got #{file_major_version}"
      end
    end

    # YAMLマッピングにコメントを追加
    def generate_comment_block(mapping)
      if mapping.nil? || mapping.empty?
        # 空のマッピングでも空のハッシュを出力
        return "  # マッピングがありません\n    {}"
      end
      mapping.map do |source, target|
        formatted_target = if target.is_a?(Hash)
                             target.transform_keys(&:to_s).transform_values do |value|
                               value.is_a?(Array) ? value.to_s : value
                             end
                           else
                             target.to_s # target が文字列の場合はそのまま文字列化
                           end

        if formatted_target.is_a?(Hash)
          "    #{source}:\n" + formatted_target.map { |k, v| "      #{k}: #{v}" }.join("\n")
        else
          "    #{source}: #{formatted_target}"
        end
      end.join("\n")
    end

    def generate_list_block(list)
      return "  # データがありません\n  []" if list.empty?

      list.map do |item|
        if item.is_a?(Hash)
          # ハッシュをネストされた形式で出力
          "  -\n" + item.map { |k, v| "      #{k}: #{v}" }.join("\n")
        else
          "  - #{item}"
        end
      end.join("\n")
    end
  end
end

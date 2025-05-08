module RedmineProjectImporter
  RESULT_FILE_NAME_TEMPLATE = "redmine_project_importer.result.%{identifier}.yml"

  class ResultFileManager
    require 'yaml'

    attr_reader :file_path, :data, :context_mgr

    def initialize(context_mgr)
      @context_mgr = context_mgr
      @data = {}

      # ユーザーファイルのパスを環境変数から取得
      user_file_path = ENV['REDMINE_PROJECT_IMPORTER_USER_FILE_PATH'] || Dir.pwd
      @file_path = File.join(user_file_path, RESULT_FILE_NAME_TEMPLATE % { identifier: context_mgr.target_project.identifier })
    end

    def logger
      @logger ||= RedmineProjectImporter.logger
    end

    # @dataの内容で結果ファイルを作成する
    def create_result_file
      logger.debug("create_result_file: #{@file_path}")
      logger.debug context_mgr.summary if context_mgr.summary.present?

      @data = context_mgr.summary if context_mgr.summary.present?

      # コメント付きYAMLを生成
      yaml_with_comments = <<~YAML
        # Redmine Project Importer Result File
        headers:
        #{generate_comment_block(context_mgr.headers || {})}

        import_summary:
        # インポート結果情報
        #{generate_comment_block(context_mgr.summary)}

        issues_mapping:
        # チケットマッピング情報
        # source_issue_id: target_issue_id
        #{generate_comment_block(context_mgr.issue_id_map || {})}
      YAML

      # warningsが存在する場合のみ追加
      if context_mgr.warnings.any?
        yaml_with_comments += <<~YAML

          warnings:
          # 警告メッセージ
          #{generate_list_block(context_mgr.warnings)}
        YAML
      end

      # errorsが存在する場合のみ追加
      if context_mgr.errors.any?
        yaml_with_comments += <<~YAML

          errors:
          # エラーメッセージ
          #{generate_list_block(context_mgr.errors)}
        YAML
      end

      logger.debug("YAML with comments:\n#{yaml_with_comments}")
      # ファイルに書き込む
      File.write(@file_path, yaml_with_comments)
      logger.info("Result file created: #{@file_path}")

      # 成功した場合 true を返す
      true
    end

    private

    # YAMLマッピングにコメントを追加
    def generate_comment_block(mapping)
      if mapping.nil? || mapping.empty?
        # 空のマッピングでも空のハッシュを出力
        return "  # データがありません\n    {}"
      end
      mapping.map do |key, value|
        formatted_value = if value.is_a?(Hash)
                            value.transform_keys(&:to_s).transform_values do |v|
                              v.is_a?(Array) ? v.to_s : v
                            end
                          else
                            value.to_s
                          end

        if formatted_value.is_a?(Hash)
          "    #{key}:\n" + formatted_value.map { |k, v| "      #{k}: #{v}" }.join("\n")
        else
          "    #{key}: #{formatted_value}"
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
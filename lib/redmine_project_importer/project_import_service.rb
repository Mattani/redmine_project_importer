require_relative 'answer_file_manager'
require_relative 'version_import_service'

module RedmineProjectImporter
  class ProjectImportService
    class << self
      def logger
        @logger ||= RedmineProjectImporter.logger
      end

      # 指定されたプロジェクトIDのインポート前処理をするメソッド
      def pre_import_project(project_id)
        logger.info "  Project Import Service started. Source Project ID: #{project_id}"
        begin
          # ソースプロジェクトを取得する
          source_project = fetch_source_project(project_id)
          unless source_project
            raise "Project with ID #{project_id} not found in the source database." # 例外をスロー
          end

          # コンテキストマネージャを生成する
          context_mgr = RedmineProjectImporter::ContextManager.new(source_project)

          # マッピングを生成する
          context_mgr.generate_mappings

          # AnswerFileManager のインスタンスを生成
          answer_file_manager = RedmineProjectImporter::AnswerFileManager.new(context_mgr)

          # アンサーファイルを作成する
          answer_file_manager.create_answer_file

          # エラーが存在する場合はエラーメッセージを出力して終了
          if context_mgr.errors.any?
            logger.error("Pre-import process failed due to error(s)")
          else # 正常終了メッセージ
            logger.info "Pre-import process completed successfully."
          end
        rescue => e
          logger.fatal("Error during pre-import process: #{e.message}")
          exit(1)
        end
      end

      # 指定されたプロジェクトIDをインポートするメソッド
      def import_project(project_id)
        logger.debug("import_project(#{project_id})")
        begin
          # ソースプロジェクトを取得する
          source_project = fetch_source_project(project_id)
          logger.error "Project with ID #{project_id} not found in the source database." unless source_project

          # ContextManager を生成
          context_mgr = RedmineProjectImporter::ContextManager.new(source_project)

          # AnswerFileManager のインスタンスを生成
          answer_file_manager = RedmineProjectImporter::AnswerFileManager.new(context_mgr)

          # アンサーファイルをロードする
          answer_file_data = answer_file_manager.load
          logger.debug("Answer file data loaded: #{context_mgr.mappings[:members_mapping]}")

          # アンサーファイルからロードしたワーニング／エラーはクリアする
          context_mgr.clear_warnings
          context_mgr.clear_errors

          # プロジェクトインポートを実行する
          logger.info("Starting project import for project ID: #{source_project.id}")
          new_project = create_target_project(source_project)
          logger.info("  New project created with ID: #{new_project.id} #{new_project.name} for importing.")

          # context_mgr にターゲットプロジェクトを登録
          context_mgr.target_project = new_project

          # メンバーインポート処理
          RedmineProjectImporter::MemberImportService.import_members(context_mgr)

          # プロジェクトに関連するトラッカーをProjectに登録・関連しないトラッカーを削除する
          RedmineProjectImporter::ProjectsTrackerImportService.import_trackers(context_mgr)

          # カスタムフィールド関連付け処理
          RedmineProjectImporter::CustomFieldsImportService.associate_custom_fields(context_mgr)

          # バージョンインポート処理
          RedmineProjectImporter::VersionImportService.import_versions(context_mgr)

          # チケットインポート処理
          RedmineProjectImporter::IssueImportService.import_issues(context_mgr)

          # Wikiインポート処理
          RedmineProjectImporter::WikiImportService.import_wiki(context_mgr)

          # インポート結果のサマリを作成・出力
          RedmineProjectImporter::ImportSummaryService.generate_report(context_mgr)

          # リサルトファイルを作成
          result_file_manager = RedmineProjectImporter::ResultFileManager.new(context_mgr)
          result_file_manager.create_result_file

        rescue => e
          logger.error("Error during project import: #{e.message}")
          exit(1)
        end
      end

      # プロジェクト一覧を表示するメソッド
      def list_projects
        logger.debug("list_projects")
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          # DBクエリ時にソート
          projects = SourceProject.order(:id)

          if projects.any?
            logger.info "SOURCE_PROJECT_ID    : PROJECT_NAME"
            logger.info "---------------------:--------------------------"
            projects.each do |project|
              logger.info format("SOURCE_PROJECT_ID=%-3s: %s", project.id, project.name)
            end
          else
            logger.info "No projects found."
          end
        end
      end

      def list_prepared_projects
        logger.debug("list_prepared_projects")
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          projects = SourceProject.all

          prepared_projects = projects.select do |project|
            answer_file_path = File.join(Dir.pwd, RedmineProjectImporter::ANSWER_FILE_NAME_TEMPLATE % { identifier: project.identifier })
            logger.debug("Checking answer file: #{answer_file_path}")
            File.exist?(answer_file_path)
          end

          if prepared_projects.any?
            logger.warn "Prepared Projects are following:\n"
            logger.info "SOURCE_PROJECT_ID    : PROJECT_NAME"
            logger.info "---------------------:--------------------------"
            prepared_projects.each do |project|
              logger.info format("SOURCE_PROJECT_ID=%-3s: %s", project.id, project.name)
            end
            logger.warn "\nPlease set SOURCE_PROJECT_ID to import projects."
          else
            logger.error "No prepared projects found. Please run pre_import task first."
          end
        end
      end

      private

      # ソースDBからプロジェクト情報を取得
      def fetch_source_project(project_id)
        logger.debug("fetch_source_project(#{project_id})")

        # DatabaseConnector を使用して接続を管理
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :import_source
        ) do
          logger.debug "Total projects in source database: #{SourceProject.count}"

          # ソースDBからプロジェクトを取得
          source_project = SourceProject.find_by(id: project_id)

          # プロジェクトが見つからない場合の処理
          if source_project.nil?
            raise "Project with ID #{project_id} not found in the source database."
          end
          source_project
        end
      end

      # ターゲットDBにプロジェクトを作成
      def create_target_project(source_project)
        logger.debug("create_target_project(#{source_project.id})")
        require File.expand_path('../../../../config/environment', __dir__)
        RedmineProjectImporter::DatabaseConnector.with_connection(
          env: Rails.env,
          config_path: File.expand_path('../../config/database.yml', __dir__),
          namespace: :primary
        ) do
          logger.debug "Current database inside with_connection: #{ActiveRecord::Base.connection.current_database}"

          # NEW_IDENTIFIER環境変数を確認し、identifierを設定
          new_identifier = ENV['NEW_IDENTIFIER'] || source_project.identifier

          target_project = Project.new(
            name: source_project.name,
            identifier: new_identifier,
            description: source_project.description,
            is_public: source_project.is_public,
            created_on: source_project.created_on,
            updated_on: source_project.updated_on
          )

          if target_project.save
            logger.debug("Project '#{target_project.name}' created successfully.")
            target_project
          else
            # 使用済み識別子のエラー処理
            if target_project.errors.details[:identifier]&.any? { |e| e[:error] == :taken }
              logger.error "Project identifier '#{target_project.identifier}' is already in use. Cannot import this project."
              logger.error "Please delete the existing project with this identifier from the target."
              logger.error "Alternatively, set the NEW_IDENTIFIER environment variable to use a different identifier."
              exit(1)
            else
              # その他のエラーは例外処理とする
              logger.error("Failed to import project: #{target_project.errors.full_messages.join(', ')}")
              raise "Failed to import project: #{target_project.errors.full_messages.join(', ')}"
            end
          end
        end
      end
    end
  end
end

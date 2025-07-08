namespace :redmine_project_importer do
  desc "Executes the import process"
  task :exec_import => :environment do
    require File.expand_path('../../lib/redmine_project_importer/project_import_service', __dir__)
    plugin = Redmine::Plugin.find(:redmine_project_importer)
    @logger = RedmineProjectImporter.logger
    @logger.info "=================================================================="
    @logger.info "#{plugin.name}/#{plugin.version} Copyright(C)2025 H.Matsutani "
    @logger.info "        This software is released under the MIT License."
    @logger.info "=================================================================="
    
    # コマンドラインで入力されたコマンドをログファイルに記録
    command = "#{$0} #{ARGV.join(' ')}"
    @logger.debug("Executed command: #{command}")

    project_id = ENV['SOURCE_PROJECT_ID']

    if project_id.nil?    # プロジェクト識別子が指定されていない場合
      @logger.warn "SOURCE_PROJECT_ID is not set."
      begin
        # ソースDBからプロジェクトの一覧を表示する
        RedmineProjectImporter::ProjectImportService.list_prepared_projects
      rescue => e
        @logger.error("Error during listing prepared source projects: #{e.message}")
        raise
      end
      exit(1)
    else  # プロジェクト識別子が指定されている場合
      begin
        # プロジェクトインポート実行処理
        RedmineProjectImporter::ProjectImportService.import_project(project_id.to_i)
      rescue => e
        @logger.fatal("Error during project import: #{e.message}")
        raise
      end 
    end
  end
end
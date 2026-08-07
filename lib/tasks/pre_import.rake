namespace :redmine_project_importer do
  desc "Prepare the import process"
  task :pre_import => :environment do
    require File.expand_path('../../lib/redmine_project_importer/project_import_service', __dir__)
    plugin = Redmine::Plugin.find(:redmine_project_importer)
    @logger = RedmineProjectImporter.logger
    @logger.info "=================================================================="
    @logger.info "#{plugin.name}/#{plugin.version} Copyright(C)2025 H.Matsutani "
    @logger.info "        This software is released under the MIT License."
    @logger.info "=================================================================="
    @logger.debug "Environment: #{ENV['RAILS_ENV']}"

    # コマンドラインで入力されたコマンドをログファイルに記録
    command = "#{$0} #{ARGV.join(' ')}"
    @logger.debug("Executed command: #{command}")

    project_id = ENV['SOURCE_PROJECT_ID']

    if project_id.nil?    # プロジェクト識別子が指定されていない場合
      @logger.error "SOURCE_PROJECT_ID is not set. Please set it and try again." 
      begin
        # ソースDBからプロジェクトの一覧を表示する
        RedmineProjectImporter::ProjectImportService.list_projects
      rescue => e
        @logger.fatal("Error during listing source projects: #{e.message}")
        # raise
      end
      exit(0)
    else  # プロジェクト識別子が指定されている場合
      @logger.info("Prepare importing project with ID: #{project_id}")
      begin
        # プロジェクトインポート実行処理
        RedmineProjectImporter::ProjectImportService.pre_import_project(project_id.to_i)
      rescue => e
        @logger.fatal("Error during project import: #{e.message}")
        # raise
      end 
    end
  end
end

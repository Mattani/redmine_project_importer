Redmine::Plugin.register :redmine_project_importer do
  name 'Redmine Project Importer plugin'
  author 'H.Matsutani'
  description 'This plugin enables redmine managers to import projects from other redmine instances.'
  version '0.1.1'
  url 'https://github.com/Mattani/redmine_project_importer.git'
  author_url 'https://x.com/mattani'
end

module RedmineProjectImporter
  require 'logger'

  def self.logger
    @logger ||= begin
      # Rails.envが未設定の場合はENV['RAILS_ENV']を使用
      environment = ENV['RAILS_ENV']
      log_output = environment == 'production' ? File.join(Rails.root, 'log', 'redmine_project_importer.log') : STDERR
      logger = Logger.new(log_output)
      logger.level = ENV['REDMINE_PROJECT_IMPORTER_DEBUG'] ? Logger::DEBUG : Logger::INFO
      logger.formatter = proc do |severity, datetime, progname, msg|
        formatted_message = "[#{datetime}] #{severity}: #{msg}\n"

        if environment == 'production'
          # productionの場合、標準エラー出力にも色付きで出力
          case severity
          when "INFO"
            STDOUT.puts "#{msg}"  # 通常の出力
          when "WARN"
            STDERR.puts "\e[33m#{msg}\e[0m" # 黄色
          when "ERROR"
            STDERR.puts "\e[31m#{msg}\e[0m" # 赤色
          when "FATAL"
            STDERR.puts "\e[41m\e[37m#{msg}\e[0m" # 赤色反転（背景赤、文字白）
          end
        end
        formatted_message
      end
      logger
    end
  end
end
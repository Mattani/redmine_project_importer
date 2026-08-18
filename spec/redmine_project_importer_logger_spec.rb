require_relative 'rails_helper'

RSpec.describe 'RedmineProjectImporter.logger' do
  around do |example|
    original_env = ENV['REDMINE_PROJECT_IMPORTER_DEBUG']
    original_logger = RedmineProjectImporter.instance_variable_get(:@logger)

    example.run

    ENV['REDMINE_PROJECT_IMPORTER_DEBUG'] = original_env
    RedmineProjectImporter.instance_variable_set(:@logger, original_logger)
  end

  before do
    RedmineProjectImporter.instance_variable_set(:@logger, nil)
  end

  it 'defaults to INFO level when REDMINE_PROJECT_IMPORTER_DEBUG is not set' do
    ENV.delete('REDMINE_PROJECT_IMPORTER_DEBUG')

    expect(RedmineProjectImporter.logger.level).to eq(Logger::INFO)
  end

  it 'uses DEBUG level when REDMINE_PROJECT_IMPORTER_DEBUG is set' do
    ENV['REDMINE_PROJECT_IMPORTER_DEBUG'] = '1'

    expect(RedmineProjectImporter.logger.level).to eq(Logger::DEBUG)
  end
end

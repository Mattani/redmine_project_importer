require_relative '../../rails_helper'
require_relative '../../../lib/redmine_project_importer/result_file_manager'

require 'tmpdir'

RSpec.describe RedmineProjectImporter::ResultFileManager do
  let(:project_id) { 1 }
  let(:project_identifier) { 'test_project' }
  let(:output_dir) { Dir.mktmpdir }
  let(:context_mgr) { instance_double(RedmineProjectImporter::ContextManager, target_project: target_project) }
  let(:target_project) do
    double(
      'TargetProject',
      id: project_id,
      identifier: project_identifier
    )
  end
  let(:manager) { described_class.new(context_mgr) }

  before do
    ENV['REDMINE_PROJECT_IMPORTER_USER_FILE_PATH'] = output_dir
    allow(context_mgr).to receive(:summary).and_return({})
    allow(context_mgr).to receive(:headers).and_return({ tool_version: '1.0.0' })
    allow(context_mgr).to receive(:issue_id_map).and_return({})
    allow(context_mgr).to receive(:warnings).and_return([])
    allow(context_mgr).to receive(:errors).and_return([])
  end

  after do
    ENV.delete('REDMINE_PROJECT_IMPORTER_USER_FILE_PATH')
    FileUtils.remove_entry(output_dir) if Dir.exist?(output_dir)
  end

  describe '#create_result_file' do
    it 'creates the result file with headers, summary and issue mappings' do
      allow(context_mgr).to receive(:summary).and_return({ total_issues: 3 })
      allow(context_mgr).to receive(:issue_id_map).and_return({ 1 => 101, 2 => 102 })

      manager.create_result_file

      expect(File.exist?(manager.file_path)).to be true

      data = YAML.safe_load(File.read(manager.file_path), symbolize_names: true)
      expect(data[:headers]).to eq({ tool_version: '1.0.0' })
      expect(data[:import_summary]).to eq({ total_issues: 3 })
      expect(data[:issues_mapping]).to eq({ 1 => 101, 2 => 102 })
    end

    it 'preserves warning messages that contain a colon (regression for YAML syntax error on load)' do
      # role_mapper.rb が実際に生成するのと同じ形式（message の値自体にコロンを含む）
      allow(context_mgr).to receive(:warnings).and_return([
        { message: "No matching target role found for source role: ロール名（ID: 4）" }
      ])
      allow(context_mgr).to receive(:errors).and_return([
        { message: "Wiki redirect 'foo' points to another project's wiki (wiki_id: 3). Skipping." }
      ])

      manager.create_result_file

      raw = File.read(manager.file_path)
      data = nil
      expect { data = YAML.safe_load(raw, symbolize_names: true) }.not_to raise_error

      expect(data[:warnings]).to eq([
        { message: "No matching target role found for source role: ロール名（ID: 4）" }
      ])
      expect(data[:errors]).to eq([
        { message: "Wiki redirect 'foo' points to another project's wiki (wiki_id: 3). Skipping." }
      ])
    end
  end
end

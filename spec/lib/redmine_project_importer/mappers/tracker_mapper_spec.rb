require_relative '../../../rails_helper'

RSpec.describe RedmineProjectImporter::Mappers::TrackerMapper do
  let(:project_id) { 1 }
  let(:source_project) { double('SourceProject', id: project_id, name: 'Test Project') }
  let(:context_mgr) { RedmineProjectImporter::ContextManager.new(source_project) }

  let(:source_trackers) do
    [
      double('SourceTracker', id: 1, name: 'Bug'),
      double('SourceTracker', id: 2, name: 'Feature')
    ]
  end
  
  let(:target_trackers) do
    [
      Tracker.new(id: 101, name: 'Bug'),
      Tracker.new(id: 102, name: 'Support')
    ]
  end

  before do
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield

    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).with(
      env: Rails.env,
      config_path: File.expand_path('../../../../../config/database.yml', __dir__),
      namespace: :import_source
    ).and_yield

    allow(SourceProjectsTracker).to receive(:where).with(project_id: project_id).and_return(double(pluck: [1, 2]))
    allow(SourceTracker).to receive(:where).with(id: anything).and_return(
      double.tap { |d| allow(d).to receive(:to_a).and_return(source_trackers.map { |tracker| { id: tracker.id, name: tracker.name } }) }
    )
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).with(
      env: Rails.env,
      config_path: File.expand_path('../../../../../config/database.yml', __dir__),
      namespace: :primary
    ).and_yield

    allow(Tracker).to receive(:all).and_return(target_trackers)

    # SourceIssue のモックを追加
    allow(SourceIssue).to receive(:where).with(project_id: project_id).and_return(
      double(distinct: double(pluck: [1, 2]))
    )
  end

  describe '.generate' do
    it 'returns correct mappings and errors' do
      result = described_class.generate(context_mgr)

      expect(result[:mappings]).to eq({
        1 => { target_tracker_id: 101, target_tracker_name: 'Bug' }
      })

      expect(context_mgr.errors).to eq([
        { source_tracker_id: 2, message: 'No matching target tracker found for tracker:[Feature]. Issues for the tracker cannot be imported.' }
      ])
    end

    it 'returns empty mappings and errors if no source trackers' do
      # SourceProjectsTracker のモックを設定して空の配列を返す
      allow(SourceProjectsTracker).to receive(:where).with(project_id: project_id).and_return(
        double(pluck: [])
      )
      # SourceTracker.where(id: []).をモックして空の配列を返す
      allow(SourceTracker).to receive(:where).with(id: []).and_return([])

      result = described_class.generate(context_mgr)

      expect(result[:mappings]).to eq({})
      expect(context_mgr.errors).to eq([])
    end

    it 'returns empty mappings and errors if no target trackers' do
      allow(Tracker).to receive(:all).and_return([])

      result = described_class.generate(context_mgr)

      expect(result[:mappings]).to eq({})
      expect(context_mgr.errors).to eq([
        { source_tracker_id: 1, message: 'No matching target tracker found for tracker:[Bug]. Issues for the tracker cannot be imported.' },
        { source_tracker_id: 2, message: 'No matching target tracker found for tracker:[Feature]. Issues for the tracker cannot be imported.' }
      ])
    end
  end
end

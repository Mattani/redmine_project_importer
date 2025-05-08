require_relative '../../../rails_helper'

RSpec.describe RedmineProjectImporter::Mappers::StatusMapper do
  let(:context_mgr) { instance_double(RedmineProjectImporter::ContextManager, source_project: source_project, mappings: mappings) }
  let(:source_project) { double('SourceProject', id: 1, name: 'Test Project') }
  let(:mappings) { { trackers_mapping: { 1 => { target_tracker_id: 101 }, 2 => { target_tracker_id: 102 } } } }

  let(:source_workflows) do
    [
      double('SourceWorkflow', old_status_id: 1, new_status_id: 2),
      double('SourceWorkflow', old_status_id: 3, new_status_id: 4)
    ]
  end

  let(:source_statuses) do
    [
      double('SourceIssuesStatus', id: 1, name: 'Open'),
      double('SourceIssuesStatus', id: 2, name: 'In Progress'),
      double('SourceIssuesStatus', id: 3, name: 'Resolved'),
      double('SourceIssuesStatus', id: 4, name: 'Closed')
    ]
  end

  let(:target_statuses) do
    [
      double('IssueStatus', id: 101, name: 'Open'),
      double('IssueStatus', id: 102, name: 'In Progress'),
      double('IssueStatus', id: 103, name: 'Resolved')
    ]
  end

  before do
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield

    # Mock SourceWorkflow
    allow(SourceWorkflow).to receive(:where).with(tracker_id: [1, 2]).and_return(source_workflows)
    allow(source_workflows).to receive(:pluck).with(:old_status_id, :new_status_id).and_return([[1, 2], [3, 4]].flatten)

    # Mock SourceIssuesStatus
    allow(SourceIssuesStatus).to receive(:where).with(id: [1, 2, 3, 4]).and_return(source_statuses)

    # Mock IssueStatus
    allow(IssueStatus).to receive(:all).and_return(target_statuses)

    # Mock context_mgr.add_error
    allow(context_mgr).to receive(:add_error)
  end

  describe '.generate' do
    it 'maps source statuses to target statuses based on name' do
      result = described_class.generate(context_mgr)

      expect(result[:mappings]).to eq({
        1 => { target_status_id: 101, target_status_name: 'Open' },
        2 => { target_status_id: 102, target_status_name: 'In Progress' },
        3 => { target_status_id: 103, target_status_name: 'Resolved' }
      })
    end

    it 'adds an error to context_mgr if a source status has no matching target status' do
      allow(target_statuses).to receive(:find).and_return(nil) # Simulate no matches for all statuses

      expect(context_mgr).to receive(:add_error).exactly(4).times
      described_class.generate(context_mgr)
    end
  end
end
require_relative '../../../rails_helper'

RSpec.describe RedmineProjectImporter::Mappers::GroupMapper do
  let(:project_id) { 1 }
  let(:source_project) { double('SourceProject', id: project_id) }
  let(:context) { RedmineProjectImporter::ContextManager.new(source_project) }
  let(:source_groups) do
    [
      double('SourceGroup', id: 1, lastname: 'Group 1'),
      double('SourceGroup', id: 2, lastname: 'Group 2')
    ]
  end
  let(:target_groups) do
    [
      double('Group', id: 101, name: 'Group 1'),
      double('Group', id: 102, name: 'Group 3')
    ]
  end

  before do
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
    allow(SourceUser).to receive(:groups).and_return(source_groups)
    allow(Group).to receive(:all).and_return(target_groups)
  end

  describe '.generate' do
    it 'returns correct mappings with roles and warnings' do
      source_roles = {
        1 => [3, 5],
        2 => [4]
      }

      allow(described_class).to receive(:fetch_source_roles).with(source_groups, project_id).and_return(source_roles)

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({
        1 => { group_name: 'Group 1', target_group_id: 101, roles: [3, 5] }
      })

      expect(context.warnings).to eq([
        { source_group_id: 2, group_name: 'Group 2', message: 'No matching target group found' }
      ])
    end

    it 'returns empty mappings and warnings if no source groups' do
      allow(SourceUser).to receive(:groups).and_return([])

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({})
      expect(context.warnings).to eq([])
    end

    it 'returns warnings if no target groups' do
      allow(Group).to receive(:all).and_return([])

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({})
      expect(context.warnings).to eq([
        { source_group_id: 1, group_name: 'Group 1', message: 'No matching target group found' },
        { source_group_id: 2, group_name: 'Group 2', message: 'No matching target group found' }
      ])
    end

    it 'returns warning if group name mismatch' do
      allow(target_groups[0]).to receive(:name).and_return('Group X')

      result = described_class.generate(context)

      expect(result[:mappings]).to eq({})
      expect(context.warnings).to eq([
        { source_group_id: 1, group_name: 'Group 1', message: 'No matching target group found' },
        { source_group_id: 2, group_name: 'Group 2', message: 'No matching target group found' }
      ])
    end
  end
end
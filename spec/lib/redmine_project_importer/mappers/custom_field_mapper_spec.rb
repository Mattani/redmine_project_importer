require_relative '../../../rails_helper'

RSpec.describe RedmineProjectImporter::Mappers::CustomFieldMapper do
  let(:project_id) { 1 }
  let(:source_project) do
    double(
      'SourceProject',
      id: project_id,
      name: 'Test Project'
    )
  end
  let(:context_mgr) { RedmineProjectImporter::ContextManager.new(source_project) }
  let(:source_custom_fields) do
    [
      double('SourceCustomField', id: 1, name: 'Custom Field 1', field_format: 'string', is_for_all: false)
    ]
  end
  let(:target_custom_fields) do
    [
      double('CustomField', id: 101, name: 'Custom Field 1', field_format: 'string')
    ]
  end

  before do
    allow(RedmineProjectImporter::DatabaseConnector).to receive(:with_connection).and_yield
    allow(SourceCustomField).to receive(:joins).with(:custom_fields_projects).and_return(SourceCustomField)
    allow(SourceCustomField).to receive(:where).with('custom_fields_projects.project_id = ?', project_id).and_return(source_custom_fields)
    allow(SourceCustomField).to receive(:where).with(is_for_all: true).and_return([])
    allow(CustomField).to receive(:all).and_return(target_custom_fields)
  end

  describe '.generate' do
    context 'when source custom fields are found' do
      context 'when trackers are found' do
        before do
          allow(described_class).to receive(:fetch_trackers_for_custom_field).with(1).and_return(['Tracker A', 'Tracker B'])
        end

        context 'when target custom field matches and formats are the same' do
          it 'returns correct mappings and no warnings' do
            result = described_class.generate(context_mgr)

            expect(result[:mappings]).to eq({
              1 => { custom_field_name: 'Custom Field 1', trackers: ['Tracker A', 'Tracker B'], target_id: 101, is_for_all: false }
            })

            expect(context_mgr.warnings).to eq([])
          end
        end

        context 'when target custom field matches but formats are different' do
          before do
            allow(target_custom_fields[0]).to receive(:field_format).and_return('text')
          end

          it 'returns no mappings and adds warnings' do
            result = described_class.generate(context_mgr)

            expect(result[:mappings]).to eq({})
            expect(context_mgr.warnings).to eq([
              { source_custom_field_id: 1, custom_field_name: 'Custom Field 1', is_for_all: false, message: 'Custom field format mismatch' }
            ])
          end
        end
      end

      context 'when trackers are not found' do
        before do
          allow(described_class).to receive(:fetch_trackers_for_custom_field).with(1).and_return([])
        end

        it 'returns no mappings and adds warnings' do
          result = described_class.generate(context_mgr)

          expect(result[:mappings]).to eq({})
          expect(context_mgr.warnings).to eq([
            { source_custom_field_id: 1, custom_field_name: 'Custom Field 1', is_for_all: false, message: 'No trackers found for this custom field' }
          ])
        end
      end
    end

    context 'when no source custom fields are found' do
      before do
        allow(SourceCustomField).to receive(:where).with('custom_fields_projects.project_id = ?', project_id).and_return([])
        allow(SourceCustomField).to receive(:where).with(is_for_all: true).and_return([])
      end

      it 'returns no mappings and no warnings' do
        result = described_class.generate(context_mgr)

        expect(result[:mappings]).to eq({})
        expect(context_mgr.warnings).to eq([])
      end
    end
  end
end
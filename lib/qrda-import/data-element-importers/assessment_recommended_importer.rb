module QRDA
  module Cat1
    class AssessmentRecommendedImporter < SectionImporter
      def initialize(entry_finder = QRDA::Cat1::EntryFinder.new("./cda:entry/cda:observation[cda:templateId/@root = '2.16.840.1.113883.10.20.24.3.145']"))
        super(entry_finder)
        @id_xpath = './cda:id'
        @code_xpath = './cda:code'
        @author_datetime_xpath = "./cda:author/cda:time"
        @reason_xpath = "./cda:entryRelationship[@typeCode='RSON']/cda:observation[cda:templateId/@root='2.16.840.1.113883.10.20.24.3.88']/cda:value"
        @entry_class = QDM::AssessmentRecommended
      end

      def create_entry(entry_element, nrh = NarrativeReferenceHandler.new)
        assessment_recommended = super
        assessment_recommended.reason = extract_reason(entry_element)
        assessment_recommended.requester = extract_entity(entry_element, "./cda:participant[@typeCode='PRF']")
        assessment_recommended
      end

    end
  end
end
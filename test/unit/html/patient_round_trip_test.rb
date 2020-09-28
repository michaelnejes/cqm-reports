require_relative '../../test_helper'
require 'cqm/models'
require 'byebug'

module HTML
  class PatientRoundTripTest < MiniTest::Test
    # include QRDA::Cat1

    def setup
      create_test_measures_collection
      address = CQM::Address.new(
        use: 'HP',
        street: ['202 Burlington Rd.'],
        city: 'Bedford',
        state: 'MA',
        zip: '01730',
        country: 'US'
      )
      telecom = CQM::Telecom.new(
        use: 'HP',
        value: '555-555-2003'
      )
      @options = { start_time: Date.new(2012, 1, 1), end_time: Date.new(2012, 12, 31), patient_addresses: [address], patient_telecoms: [telecom] }
      # TODO: use address etc??

      generate_shell_patient('html') # builds @cqm_patient and @qdm_patient
    end

    def test_demographics
      @cqm_patient.qdmPatient = @qdm_patient
      html = QdmPatient.new(@cqm_patient, true).render
      %w[gender race ethnicity birthdate payer].each do |cat|
        assert html.include?(@qdm_patient.get_data_elements('patient_characteristic', cat).first.dataElementCodes.first[:code])
      end
    end

    def test_all_html_attributes
      qdm_types = YAML.safe_load(File.read(File.expand_path('../../../config/qdm_types.yml', __dir__)), [], [], true)
      qdm_types.each do |qt|
        dt = QDM::PatientGeneration.generate_loaded_datatype("QDM::#{qt}")
        # check custom generated datatype for negationRationale field
        check_loaded_patient(QDM::PatientGeneration.generate_loaded_datatype("QDM::#{qt}", true), "negationRationale", qt) if dt.typed_attributes.keys.include?("negationRationale")
        # iterate through all relevant attributes for each data type, except negationRationale (checked above)
        dt.typed_attributes.keys.each do |field|
          next if %w[_id dataElementCodes description codeListId id _type type qdmTitle hqmfOid qrdaOid qdmCategory qdmVersion qdmStatus negationRationale targetOutcome].include? field
          # TODO: test targetOutcome (in Care Goal, not currently exported)
          check_loaded_patient(dt, field, qt)
        end
      end
    end

    def check_loaded_patient(dt, field, qt)
      # create new qdm patient clone for dt/attribute combo
      qdm_patient = qdm_patient_for_attribute(dt, field, @qdm_patient)
      @cqm_patient.qdmPatient = qdm_patient

      html = QdmPatient.new(@cqm_patient, true).render
      assert html.include?(qt), "html should include QDM type #{qt}"
      assert dt.respond_to?(field), "datatype generation discrepancy, should contain field #{field}"
      check_for_type(html, dt, field)
    end

    def check_for_type(html, dt, field)
      attr = dt.send(field)
      if attr.respond_to?(:strftime)
        # timey object
        formatted_date = attr.localtime.strftime('%FT%T')
        assert html.include?(formatted_date), "html should include date/time value #{formatted_date}"
      elsif attr.is_a?(Array)
        # components, relatedTo (irrelevant), facilityLocations, diagnoses (all code or nested code)
        attr.each do |attr_elem|
          top_code = get_key_or_field(attr_elem, 'code')
          if top_code.is_a?(Hash)
            # nested code
            assert html.include?(top_code[:code]), "html should include nested code value #{top_code[:code]}"
          else
            # code
            assert html.include?(top_code), "html should include code value #{top_code}"
          end
        end
      elsif attr.is_a?(Integer) || attr.is_a?(String) || attr.is_a?(Float)
        assert html.include?(attr.to_s), "html should include text value #{attr}"
        # qrdaOid
      elsif key_or_field?(attr, :low)
        # interval (may or may not include high)
        formatted_date = attr.low.strftime('%FT%T')
        assert html.include?(formatted_date), "html should include low value #{formatted_date}"

      elsif key_or_field?(attr, :code)
        # must come after value to match result logic
        top_code = get_key_or_field(attr, :code)
        if top_code.is_a?(QDM::Code)
          # nested code
          assert html.include?(top_code.code), "html should include nested code value #{top_code.code}"
        else
          # code
          assert html.include?(top_code), "html should include code value #{top_code}"
        end
      elsif key_or_field?(attr, 'identifier')
        # entity
        assert html.include?(attr.identifier.value), "html should include identifier value #{attr.identifier.value}"
      elsif key_or_field?(attr, :value)
        value = get_key_or_field(attr, :value)
        # value for basic identifier, result, or quantity (may or may not include unit)
        # must come before code to match result logic
        assert html.include?(value.to_s), "html should include value #{value}"
      else
        # simple to_s, unlikely to get here
        assert html.include?(attr.to_s), "html should include text value #{attr}"
      end
    end

    def key_or_field?(object, keyfield)
      return true if object.is_a?(Hash) && object.key?(keyfield)
      object.respond_to?(keyfield)
    end

    def get_key_or_field(object, keyfield)
      object.is_a?(Hash) ? object[keyfield] : object.send(keyfield)
    end

    def qdm_patient_for_attribute(dt, field, src_qdm_patient)
      # dt.reason = nil if ta[7] && dt.respond_to?(:reason)
      reset_datatype_fields(dt, field)

      single_dt_qdm_patient = src_qdm_patient.clone
      single_dt_qdm_patient.dataElements << dt
      single_dt_qdm_patient
    end

    def reset_datatype_fields(dt, field)
      dt.prescriberId = QDM::Identifier.new(namingSystem: '1.2.3.4', value: '1234') if dt.respond_to?(:prescriberId)
      dt.dispenserId = QDM::Identifier.new(namingSystem: '1.2.3.4', value: '1234') if dt.respond_to?(:dispenserId)

      dt.relevantDatetime = nil if dt.respond_to?(:relevantDatetime) && dt.respond_to?(:relevantPeriod) && field == 'relevantPeriod'
      dt.relevantPeriod = nil if dt.respond_to?(:relevantDatetime) && dt.respond_to?(:relevantPeriod) && field == 'relevantDatetime'
    end

    def generate_shell_patient(type)
      @cqm_patient = QDM::BaseTypeGeneration.generate_cqm_patient(type)
      @qdm_patient = QDM::BaseTypeGeneration.generate_qdm_patient
      # Add patient characteristics
      sex = QDM::PatientGeneration.generate_loaded_datatype('QDM::PatientCharacteristicSex')
      race = QDM::PatientGeneration.generate_loaded_datatype('QDM::PatientCharacteristicRace')
      ethnicity = QDM::PatientGeneration.generate_loaded_datatype('QDM::PatientCharacteristicEthnicity')
      birthdate = QDM::PatientGeneration.generate_loaded_datatype('QDM::PatientCharacteristicBirthdate')
      payer = QDM::PatientGeneration.generate_loaded_datatype('QDM::PatientCharacteristicPayer')
      @qdm_patient.dataElements.push(sex)
      @qdm_patient.dataElements.push(race)
      @qdm_patient.dataElements.push(ethnicity)
      @qdm_patient.dataElements.push(birthdate)
      @qdm_patient.dataElements.push(payer)
    end

    def create_test_measures_collection
      # Delete all existing for atomicity
      CQM::Measure.delete_all
      @measure = CQM::Measure.new
      @measure.hqmf_id = 'b794a9c2-8e83-11e8-9eb6-529269fb1459'
      @measure.hqmf_set_id = 'bdfa0e38-8e83-11e8-9eb6-529269fb1459'
      @measure.description = 'Test Measure'
      @measure.cql_libraries = []
      @measure.save
    end

    # def test_display_codes
    #   perform_enqueued_jobs do
    #     @bundle = Cypress::CqlBundleImporter.import(retrieve_mini_bundle, Tracker.new, false)
    #   end
    #
    #   # use file with negation
    #   file = File.new(Rails.root.join('test', 'fixtures', 'qrda', 'cat_I', 'sample_patient_single_code.xml')).read
    #   doc = Nokogiri::XML(file)
    #   doc.root.add_namespace_definition('cda', 'urn:hl7-org:v3')
    #   doc.root.add_namespace_definition('sdtc', 'urn:hl7-org:sdtc')
    #
    #   # import and build code descriptions
    #   patient, _warnings, codes = QRDA::Cat1::PatientImporter.instance.parse_cat1(doc)
    #   Cypress::QRDAPostProcessor.build_code_descriptions(codes, patient, @bundle)
    #   patient['bundleId'] = @bundle.id
    #   patient.update(_type: CQM::BundlePatient, correlation_id: @bundle.id)
    #   Cypress::QRDAPostProcessor.replace_negated_codes(patient, @bundle)
    #   patient.save!
    #   saved_patient = Patient.find(patient.id)
    #
    #   # export to html
    #   formatter = Cypress::HTMLExporter.new([Measure.where(hqmf_id: 'BE65090C-EB1F-11E7-8C3F-9A214CF093AE').first], Date.new(2012, 1, 1), Date.new(2012, 12, 31))
    #   html = formatter.export(saved_patient)
    #
    #   # initial html
    #   assert html.include?('Male'), 'HTML should include gender code description'
    #   assert html.include?('American Indian or Alaska Native'), 'HTML should include race code description'
    #   assert html.include?('Not Hispanic or Latino'), 'HTML should include ethnicity code description'
    #   assert html.include?('MEDICARE'), 'HTML should include payer code description'
    #   assert html.include?('Procedure contraindicated (situation)'), 'HTML should include negation rationale code description'
    #   assert html.include?('carvedilol 6.25 MG Oral Tablet'), 'HTML should include medication code description'
    #   # Note: code="60" from sdtc:valueSet="1.3.4.5" is unknown (fake) and therefore appropriately omits a description
    #
    #   # randomize patient and re-export
    #   Cypress::DemographicsRandomizer.randomize(saved_patient, Random.new(Random.new_seed))
    #   Cypress::DemographicsRandomizer.update_demographic_codes(saved_patient)
    #   html = formatter.export(saved_patient)
    #
    #   # assertions
    #   # check if race and ethnicity updated
    #   race_same = saved_patient.qdmPatient.get_data_elements('patient_characteristic', 'race').first.dataElementCodes.first.code == '1002-5'
    #   assert_not html.include?('American Indian or Alaska Native'), 'HTML should include race code description' unless race_same
    #   ethnicity_same = saved_patient.qdmPatient.get_data_elements('patient_characteristic', 'ethnicity').first.dataElementCodes.first.code == '2186-5'
    #   assert_not html.include?('Not Hispanic or Latino'), 'HTML should include ethnicity code description' unless ethnicity_same
    #
    #   assert html.include?('Procedure contraindicated (situation)'), 'HTML should include negation rationale code description'
    #   assert html.include?('carvedilol 6.25 MG Oral Tablet'), 'HTML should include medication code description'
    # end

  end
end

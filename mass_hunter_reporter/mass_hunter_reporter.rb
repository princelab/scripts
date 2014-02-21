#!/usr/bin/env ruby

# author: John T. Prince
# 
# date: 2013-01-07
#
# purpose: written for JC Price lab to extract and report isotope information
#          from Mass Hunter files.
#
# license: CC0 1.0
#          (i.e., public domain)
#          http://creativecommons.org/publicdomain/zero/1.0/legalcode

raise "Need ruby >= 2.0" unless RUBY_VERSION >= "2.0"

require 'nokogiri'
require 'ostruct'
require 'csv'

###############################################
## Core extensions
###############################################

module Enumerable
  def index_by
    if block_given?
      Hash[map { |elem| [yield(elem), elem] }]
    else
      to_enum :index_by
    end
  end
end

class Module
  def alias_attr(new_attr, original)
    alias_method(new_attr, original) if method_defined? original
    new_writer = "#{new_attr}="
    orig_writer = "#{original}="
    alias_method(new_writer, orig_writer) if method_defined? orig_writer
  end
end

class String
  def split_camel
    camelize.gsub(/(.)([A-Z])/, '\1 \2')
  end

  def underscore
    self.gsub(/::/, '/').
      gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
      gsub(/([a-z\d])([A-Z])/,'\1_\2').
      tr("- ", "_").
      downcase
  end

  def camelize(first_letter_upcase = true)
    if first_letter_upcase
      self.gsub(/(^|_)(.)/) { $2.upcase }
    else
      self.first + camelize(self)[1..-1]
    end
  end
end

class Nokogiri::XML::Node
  def verify(name)
    raise "node should be #{name}" unless self.name == name
  end
end

###############################################
## Main objects
###############################################

module MassHunterReporter

  class ReportReader

    # returns a MassHunterReporter::Sample object
    def read(xml_filename)
      File.open(xml_filename) do |io|
        doc = Nokogiri::XML.parse(io) {|cfg| cfg.noblanks.strict }
        doc.remove_namespaces!

        info_table_n = doc.at_xpath('./Report/SampleInformationTable')
        sample = MHR::Sample.new.from_xml_node(info_table_n)
        sample.orig_filename = xml_filename

        compound_table_n = info_table_n.next_sibling
        compound_table_n.verify('CompoundTable')

        sample.compounds = compound_table_n.children.map do |compound_n|
          MHR::Compound.new.from_xml_node(compound_n)
        end

        id_to_compound = sample.compounds.index_by &:id

        compounds_n = compound_table_n.next_sibling
        compounds_n.verify('Compounds')

        compounds_n.children.each do |compound_details_n|
          compound_details_n.verify('CompoundDetails')

          item_id = compound_details_n.at_xpath('./ItemID').text
          compound = id_to_compound[item_id]

          ms_spectrum_n = compound_details_n
            .at_xpath('./CompoundSpectra/MSSpectrum')

          ms_spectrum = MHR::MSSpectrum.new.from_xml_node(ms_spectrum_n)
          compound.spectra << ms_spectrum

          spec_peaks = ms_spectrum_n
            .xpath('./MSPeakTable/SpecPeak').map do |spec_peak_n|
              MHR::SpecPeak.new.from_xml_node(spec_peak_n)
            end
          ms_spectrum.spec_peaks.push *spec_peaks
        end
        sample
      end
    end

  end

  class ReportWriter
    module Commented
      SAMPLE = {
        sample_name: :split_camel,
        position: :capitalize,
        acquired_time: :split_camel,
        instrument_name: :split_camel,
        acq_method_name: 'Acq Method',
        irm_status: 'IRM Calibration Status',
        comment: :capitalize,
        acq_sw_version: 'Acquisition SW Version',
        da_method: 'DA Method',
      }
    end

    module Column
      COMPOUND = {
        compound_label: :split_camel,
        name: :capitalize,
        mass: :capitalize,
        rt: :upcase, 
        tgt_rt_diff: 'TgtRtdiff',
        filename: :to_s,
        pos_aaseq_mods_st: 'AA+seq-mod',
        aaseq: 'Sequence',
        mod_st: 'Modifications',
        score_db: 'Score (DB)'
      }

      ISOTOPE_CLUSTER = {
        isotope_cluster: :split_camel,
        z: :to_s,
        ion: :capitalize,
      }

      SPEC_PEAKS = {
        mz: 'm/z',
        abundance: 'Abund',
      }
    end

    def initialize(sample)
      @sample = sample
    end

    def default_outfile
	  @sample.analysis_file_name + ".report.csv"
      #base = @sample.orig_filename.chomp(File.extname(@sample.orig_filename))
      #base + ".csv"
    end

    # creates a header given the attribute name and the transform or given
    # header
    def header(attr, header_or_transform)
      if header_or_transform.is_a?(String)
        header_or_transform
      else
        attr.to_s.send(header_or_transform)
      end
    end

    def write(outfile=nil)
      outfile ||= default_outfile
      CSV.open(outfile, 'wb') do |csv|
        Commented::SAMPLE.each do |attr,header_or_transform|
          csv << ['# ' + header(attr,header_or_transform), @sample[attr]]
        end

        csv << 
          Column::COMPOUND
          .merge(Column::ISOTOPE_CLUSTER)
          .merge(Column::SPEC_PEAKS)
          .map {|pair| header(*pair) }

        @sample.compounds.each do |compound|
          first_half = Column::COMPOUND.keys.map {|attr| compound[attr] }
          spec_peaks = compound.spectra.flat_map &:spec_peaks
          spec_peaks.group_by(&:isotope_cluster).each do |isotope_cluster, spec_peaks|
            isotope_cluster_data = Column::ISOTOPE_CLUSTER.keys.map {|attr| spec_peaks.first[attr] }
            peak_data = spec_peaks.flat_map do |spec_peak|
              Column::SPEC_PEAKS.keys.map {|attr| spec_peak[attr] }
            end
            csv << 
              first_half
              .dup.push(*isotope_cluster_data)
              .push(*peak_data)
          end
        end
      end
    end
  end

  class FromXML
    class << self
      attr_accessor :xml_names
      def set_xml_names(names)
        @xml_names = names
        @xml_names.each do |c_attr|
          attr_accessor c_attr.underscore.to_sym
        end
        @xml_names
      end

      def id(id_method)
        alias_attr :id, id_method
      end
    end

    def [](attr)
      send(attr)
    end

    def []=(attr, val)
      send((attr.to_s + "=").to_sym, val)
    end

    # depends on the class method xml_names giving an array of xml names to
    # retrieve
    def from_xml_node(node)
      retrieve = self.class.xml_names
      node.children.each do |child_n|
        name = child_n.name
        if retrieve.include?(name)
          self[name.underscore] = child_n.text
        end
      end
      if self.class.const_defined?('CAST')
        self.class.const_get('CAST').each do |attr, cast|
          if respond_to? attr
            self[attr] = self[attr].send(cast)
          else
            warn "no method corresponding to: #{setter}"
          end
        end
      end
      self
    end
  end

  class Sample < FromXML
    set_xml_names %w(
      SampleName 
      SamplePosition 
      AcquiredTime
      AcqMethodName
      IRMStatus
      Comment
      AcqSwVersion
      DAMethod
      AnalysisFileName
      InstrumentName
    )
    alias_attr :filename, :analysis_file_name
    attr_accessor :compounds
    attr_accessor :orig_filename
    alias_attr :position, :sample_position
  end

  class Compound < FromXML
    set_xml_names %w(
      Label
      CompoundName
      Mass
      RetentionTime
      TgtRetentionTimeDifference
      DataFileName
      Notes
      ItemID
      MergedIDOverallMatchScore
    )
    CAST = {
      mass: :to_f,
      rt: :to_f,
      tgt_rt_diff: :to_f,
    }
    id :item_id
    alias_attr :rt, :retention_time
    alias_attr :tgt_rt_diff, :tgt_retention_time_difference
    alias_attr :compound_label, :label
    alias_attr :name, :compound_name
    alias_attr :pos_aaseq_mods_st, :notes
    alias_attr :score_db, :merged_id_overall_match_score
    alias_attr :filename, :data_file_name

    attr_accessor :spectra

    def initialize
      @spectra = []
    end

    # Returns a triplet: position as an int, aaseq (string), and mods (string).  (Once we know
    # the delimiter we can set these as an array)
    def pos_aaseq_mods
      (pos_st, aaseq_plus_mods) = self.pos_aaseq_mods_st.split('+')
      @aaseq_start_position = pos_st.to_i

      (@aaseq, @mod_st) = aaseq_plus_mods.split('-',2)
      [@aaseq_start_position, @aaseq, @mod_st]
    end

    # the pos (position) from pos_aaseq_mods
    def aaseq_start_position
      @aaseq_start_position || pos_aaseq_mods.first
    end

    def aaseq
      @aaseq || pos_aaseq_mods[1]
    end

    def mod_st
      @mod_st || pos_aaseq_mods_st.last
    end

    alias_method :sequence, :aaseq
    alias_method :modifications, :mod_st
  end

  class MSSpectrum < FromXML 
    set_xml_names %w(MSSpectrumID) 
    id :ms_spectrum_id

    def initialize
      @spec_peaks = []
    end

    attr_accessor :spec_peaks
    alias_attr :peaks, :spec_peaks
  end

  class SpecPeak < FromXML
    # CenterX seems duplicated with LowestIsotopeMz
    # Height seems duplicated with MaxY
    set_xml_names %w(
      PeakID
      IsotopeCluster
      IonSpecies
      FormulaPlusIonSpecies
      CenterX
      ChargeState
      Height
    )
    id :peak_id
    alias_attr :ion, :ion_species
    alias_attr :mz, :center_x
    alias_attr :abundance, :height
    alias_attr :charge, :charge_state
    alias_attr :z, :charge_state
  end
end

MHR = MassHunterReporter

###############################################
## Script
###############################################

if ARGV.size == 0
  puts "usage: #{File.basename(__FILE__)} <file>.xml ..."
  puts "output: <file>.extracted.csv ..."
end

ARGV.each do |report_xml_file|
  sample = MHR::ReportReader.new.read(report_xml_file)
  writer = MHR::ReportWriter.new(sample)
  writer.write
  puts "wrote: #{writer.default_outfile}"
end

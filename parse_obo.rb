#!/usr/bin/env ruby

# JTP notes:
# An example of how to quickly parse an OBO file
# This should probably be compared for accuracy and performance against the
# obo gem and used to improve that gem, if necessary

require 'set'
require 'obo'

module Enumerable 
  def index_by
    return to_enum :index_by unless block_given?
    Hash[map { |elem| [yield(elem), elem] }]
  end
end

Term = Struct.new(:id, :name, :namespace, :def, :replaced_bys, :considers, :is_obsolete, :alt_ids, :subsets, :synonyms, :xrefs, :is_as, :intersections_of, :relationships, :parents, :children)

class Tree

  attr_accessor :terms
  attr_reader :terms_by_id

  def initialize(terms)
    @terms = terms
    @terms_by_id = terms.index_by(&:id) 
  end

  def self.link!
    terms_by_id ||= terms.index_by(&:id) 
    terms.each do |term|
      term.is_as.each do |parent_id|
        parent = terms_by_id[parent_id]
        term.parents << parent
        parent.children << term
      end
    end
    self
  end

  # leaf node if no children (defined for unlinked tree right now)
  def leaf?(term_or_go)
    go_id = as_term(term_or_go).id
    not_a_leaf = @terms.any? do |term| 
      term.is_as.any? do |is_a_id| 
        go_id == is_a_id
      end
    end
    !not_a_leaf
  end

  def as_term(term_or_go)
    term_or_go.is_a?(Term) ? term_or_go : @terms_by_id[term_or_go]
  end

end

class Term
  # doesn't include children since it's not a real obo key
  Multiples = members.select do |key| 
    key_s = key.to_s
    key_s.split('_').any? do |piece| 
      piece[-1] == 's' 
    end
  end
  MultiplesInSingularFormStrings = Multiples.map do |key| 
    pieces = key.to_s.split('_')
    pieces.map do |piece| 
      if piece[-1] == 's' && piece != 'is'
        piece[0...-1] 
      else
        piece
      end
    end.join("_")
  end

  SingleToMultipleForm = Hash[ MultiplesInSingularFormStrings.zip(Multiples).to_a ]
  MembersSet = Set.new(members.map(&:to_s))

  # returns an array of Term objects
  def self.read_obo(obo_file)
    chunks = []
    chunk = []
    IO.foreach(obo_file) do |line|
      line.chomp!
      if line.size == 0
        chunks << chunk
        chunk = []
      else
        chunk << line
      end
    end

    header = chunks.shift

    terms = []
    chunks.each do |chunk|
      if chunk.shift == '[Term]'
        term = Term.new
        chunk.each do |line|
          (key, value) = line.split(": ", 2)
          pieces = value.split(/\s+\!\s+/)
          pieces.pop if pieces.size > 1 # comment
          value = pieces.join(" ! ")
          if Term::MultiplesInSingularFormStrings.include?(key)
            term[Term::SingleToMultipleForm[key]] << value
          else
            if Term.key?(key)
              term[key.to_sym] = value
            end
          end
        end
        terms << term
      end
    end
    terms
  end

  def self.key?(arg)
    MembersSet.include?(arg)
  end

  def initialize(*args)
    super(*args)
    Multiples.each do |key|
      self[key] = []
    end
    self.children = []
  end
end


if ARGV.size < 2
  puts "usage: #{File.basename(__FILE__)} <file>.obo term ..."
  exit
end

obofile = ARGV.shift
go_ids = ARGV

terms = Term.read_obo(obofile)
tree = Tree.new(terms)

go_ids.each do |go_id|
  puts "#{go_id}: #{tree.leaf? go_id}"
end

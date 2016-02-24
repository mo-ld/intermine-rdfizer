#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
# author:  	maxime déraspe
# email:	maxime@deraspe.net
# date:    	2016-01-05
# version: 	1.0

require 'open-uri'
require 'nokogiri'
require 'rdf'
require 'rdf/nquads'
require 'sparql'
require "intermine/service"
require 'json'
require 'digest'
require 'shell-spinner'
require 'benchmark'


# CORE RDF URI
# @arg[:uri] = "http://purl.intermine.org"
RDF_TYPE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
RDF_VALUE = "http://www.w3.org/1999/02/22-rdf-syntax-ns#value"

@ontologies = {
  "skos" => "http://www.w3.org/2004/02/skos/core#",
  "rdf" => "http://www.w3.org/1999/02/22-rdf-syntax-ns#",
  "rdfs" => "http://www.w3.org/2000/01/rdf-schema#",
  "owl" => "http://www.w3.org/2002/07/owl#"
}

# which kind of literal
# return: integer, float, string
def get_literal value

  if value[0..6] == "http://"
    literal = RDF::URI(value)
  else
    literal = RDF::Literal(value)
    is_integer = (true if Integer(value) rescue false)
    is_float = (true if Float(value.gsub(",",".")) rescue false)

    if is_integer
      literal = RDF::Literal(value.to_i)
    elsif is_float
      literal = RDF::Literal(value.to_f)
    end
  end

  literal

end


# serialize quad
# IF extend == false   input: [s,p,o], false
# IF extend == true    input: [s,p,{type: "type", value: "value"}], true
def serialize_quad quad_ary, extend

  qd = RDF::Graph.new()
  graph_name = quad_ary[3].to_s

  if extend

    att_sbj = @arg[:uri] + "/mine_attribute:" + Digest::SHA256.hexdigest(quad_ary[2][:type].to_s+quad_ary[2][:value].to_s)[-20..-1]
    att_type = @arg[:uri] + "/mine_type:" + quad_ary[2][:type]
    att_value = "#{quad_ary[2][:value].to_s}"

    statements = []
    statements << RDF::Statement.new(RDF::URI("#{quad_ary[0]}"), RDF::URI("#{quad_ary[1]}"), RDF::URI("#{att_sbj}"))
    statements << RDF::Statement.new(RDF::URI("#{att_sbj}"), RDF::URI("#{RDF_TYPE}"), RDF::URI("#{att_type}"))
    statements << RDF::Statement.new(RDF::URI("#{att_sbj}"), RDF::URI("#{RDF_VALUE}"), get_literal("#{att_value}"))

    statements.each do |statement|
      if statement.valid?
        qd << statement
      else
        @arg[:log] << "BAD #{statement.to_ntriples}"
      end
    end

  else

    statement = RDF::Statement.new(RDF::URI("#{quad_ary[0]}"), RDF::URI("#{quad_ary[1]}"), get_literal("#{quad_ary[2]}"))

    if statement.valid?
      qd << statement
    else
      @arg[:log] << "BAD #{statement.to_ntriples}"
    end

  end

  qd

end


# db record to rdf
def record2rdf row, obj

  fout = File.open("#{@arg[:output]}/#{obj}.nq", "a")
  fields = row.to_s.chomp.gsub(/^#{obj}: /,"").split(",\t")
  fields.each { |f| f.strip! }
  id_index = nil
  id_index = fields.index { |x| x =~ /^id=/  }
  return if id_index == nil

  id = fields[id_index].split("=")[1]
  # id_sha256 = Digest::SHA256.hexdigest(id.split("=")[1])[-20..-1]

  datatype = @arg[:uri] + "/resource/#{@db_name}_" + obj
  subject = @arg[:uri] + "/#{@db_name}:#{id}"
  # if loosely coupled
  if @arg[:lcoupled] == 1
    subject = @arg[:uri] + "/#{@db_name}_#{obj}:#{id}"
  end

  # Object Table Ressource
  statement = RDF::Statement.new(RDF::URI("#{subject}"), RDF::URI(RDF_TYPE), RDF::URI(datatype))
  if statement.valid?
    qd = RDF::Graph.new()
    qd << statement
    fout.write(qd.dump(:nquads))
  end

  # interate over each col
  fields.each do |f|
    f_ary = f.split("=")

    if f_ary[1] and @all_obj[obj][:attributes].include? f_ary[0]

      qd = RDF::Graph.new()
      if f_ary[0].include? "name"
        p = "http://www.w3.org/2000/01/rdf-schema#label"
        qd = serialize_quad(["#{subject}", "#{p}", "#{f_ary[1]}"], false)
      elsif f_ary[0] == "id"
        next
      else
        type = f_ary[0]
        type[0] = f_ary[0][0].upcase
        p = @arg[:uri] + "/mine_vocabulary:has#{type}"
        qd = serialize_quad(["#{subject}", "#{p}", {type: f_ary[0], value: f_ary[1]}], true)
      end

      fout.write(qd.dump(:nquads))

    end

  end

end


# build a link between 2 obj records
def recordlink2rdf row, obj1, obj2, bothways

  fout = File.open("#{@arg[:output]}/#{obj1}.nq", "a")
  fields = row.to_s.chomp.gsub(/^.*: /,"").split(",\t")
  fields.each { |f| f.strip! }
  id1 = fields[0].split("=")[1]
  id2 = fields[1].split("=")[1]

  subject = @arg[:uri] + "/#{@db_name}:#{id1}"
  object = @arg[:uri] + "/#{@db_name}:#{id2}"

  # if loosely coupled change subject - object
  if @arg[:lcoupled] == 1
    subject = @arg[:uri] + "/#{@db_name}_#{obj1}:#{id1}"
    object = @arg[:uri] + "/#{@db_name}_#{obj2}:#{id2}"
  end

  qd = RDF::Graph.new()
  if bothways
    p = @arg[:uri] + "/mine_vocabulary:has#{obj1}"
    qd = serialize_quad(["#{object}", "#{p}", "#{subject}"], false)
    fout.write(qd.dump(:nquads))
    p = @arg[:uri] + "/mine_vocabulary:has#{obj2}"
    qd = serialize_quad(["#{subject}", "#{p}", "#{object}"], false)
    fout.write(qd.dump(:nquads))
  else
    p = @arg[:uri] + "/mine_vocabulary:has#{obj2}"
    qd = serialize_quad(["#{subject}", "#{p}", "#{object}"], false)
    fout.write(qd.dump(:nquads))
  end

end


# obj subclass of another obj
def subClassOf row, child_obj, parent_obj

  fields = row.to_s.chomp.gsub(/^#{child_obj}: /,"").split(",\t")
  fields.each { |f| f.strip! }
  id_index = nil
  id_index = fields.index { |x| x =~ /^id=/  }
  return if id_index == nil

  id = fields[id_index].split("=")[1]
  # id_sha256 = Digest::SHA256.hexdigest(id.split("=")[1])[-20..-1]

  # object inherit from parent object ??
  # TODO find another predicate here

  # if loosely coupled create link between objects
  if @arg[:lcoupled] == 1
    File.open("#{@arg[:output]}/#{parent_obj}.nq", "a") do |fout|
      qd = RDF::Graph.new()
      s = @arg[:uri] + "/#{@db_name}_#{child_obj.downcase}:#{id}"
      p = @ontologies["rdfs"]+"subClassOf"
      o = @arg[:uri] + "/#{@db_name}_#{parent_obj.downcase}:#{id}"
      qd = serialize_quad([s, p ,o], false)
      fout.write(qd.dump(:nquads))
    end
  end

  # class subClassOf parent class
  File.open("#{@arg[:output]}/Classes.nq", "a") do |fout|
    qd = RDF::Graph.new()
    s = @arg[:uri] + "/resource/#{@db_name}_#{child_obj}"
    p = @ontologies["rdfs"]+"subClassOf"
    o = @arg[:uri] + "/resource/#{@db_name}_#{parent_obj}"
    qd = serialize_quad([s, p ,o], false)
    fout.write(qd.dump(:nquads))
  end

end

# query intermine endpoint
def rdfize_data

  puts "\n# RDFizing intermine class objects #"

  # rdfizing all obj

  @all_obj.each_key do |obj|

    next if @all_obj[obj][:exist] == 0 or @all_obj[obj][:processed]

    if ! File.exists? ("#{@arg[:output]}/#{@all_obj[obj][:name]}.tsv")
      @arg[:log] << "File #{@arg[:output]}/#{@all_obj[obj][:name]}.tsv doesn't exists [--download first ?]"
      next
    end


    ShellSpinner "RDFizing #{@all_obj[obj][:name]} class" do

      # classes inheritance, just assigned rdfs:subClassOf to parent class
      if @all_obj[obj].has_key? :extends

        File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}.tsv") do |file|
          while l = file.gets
            @all_obj[obj][:extends].each do |parent|
              subClassOf(l,@all_obj[obj][:name], parent)
            end
          end
        end

      end

      File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}.tsv") do |file|

        # iterate over all the other records
        while l = file.gets
          record2rdf(l,@all_obj[obj][:name])
        end
      end

    end


    # rdfizing all obj references
    @all_obj[obj][:references].each do |reference|

      next if ! @all_obj.has_key? reference[:referenced_type]

      if ! File.exists? ("#{@arg[:output]}/#{@all_obj[obj][:name]}_reference_#{reference[:referenced_type]}.tsv")
        puts "Don't exist -> #{@arg[:output]}/#{@all_obj[obj][:name]}_reference_#{reference[:referenced_type]}.tsv"
        @arg[:log] << "File #{@arg[:output]}/#{@all_obj[obj][:name]}_reference_#{reference[:referenced_type]}.tsv doesn't exists [--download first ?]"
        next
      end

      ShellSpinner "_-> RDFizing reference #{@all_obj[obj][:name]} / #{reference[:referenced_type]}" do
        File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}_reference_#{reference[:referenced_type]}.tsv") do |file|
          while l = file.gets
            recordlink2rdf(l, @all_obj[obj][:name], reference[:referenced_type], false)
          end
        end
      end

    end


    # rdfizing all obj collections
    @all_obj[obj][:collections].each do |collection|

      next if ! @all_obj.has_key? collection[:referenced_type]

      if ! File.exists? ("#{@arg[:output]}/#{@all_obj[obj][:name]}_collection_#{collection[:referenced_type]}.tsv")
        puts "Don't exist -> #{@arg[:output]}/#{@all_obj[obj][:name]}_collection_#{collection[:referenced_type]}.tsv"
        @arg[:log] << "File #{@arg[:output]}/#{@all_obj[obj][:name]}_collection_#{collection[:referenced_type]}.tsv doesn't exists [--download first ?]"
        next
      end

      ShellSpinner "_-> RDFizing collection #{@all_obj[obj][:name]} / #{collection[:referenced_type]}" do
        File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}_collection_#{collection[:referenced_type]}.tsv") do |file|
          while l = file.gets
            recordlink2rdf(l, @all_obj[obj][:name], collection[:referenced_type], false)
          end
        end
      end

    end

    @all_obj[obj][:processed] = true

  end

end


# create linked data with other open ld sources
def dbxref

  dbxref_hash = {}
  File.open("#{@arg[:dbxref]}","r") do |f|
    while l = f.gets
      next if l[0] == "#"
      lA = l.chomp.split(",")
      lA.each { |x| x.strip! }
      if ! dbxref_hash.has_key? lA[1].downcase
        dbxref_hash[lA[1].downcase] = []
      end
      dbxref_hash[lA[1].downcase] << {type: lA[0].downcase, uri_base: lA[2], uri_rel: lA[3]}
    end
  end

  datasource_type = RDF::URI("#{@arg[:uri]}/resource/#{@db_name}_DataSource")
  ontology_type = RDF::URI("#{@arg[:uri]}/resource/#{@db_name}_Ontology")
  rdfs_label = RDF::URI(@ontologies["rdfs"] + "label")

  # Get DataSource Labels
  datasource_uri = {}
  if File.exists? ("./#{@arg[:output]}/DataSource.nq")
    graph = RDF::Graph.load("./#{@arg[:output]}/DataSource.nq")
    query = RDF::Query.new({
                             datasource: {
                               RDF.type => datasource_type,
                               rdfs_label => :label
                             }
                           })
    query.execute(graph).each do |solution|
      # datasource_uri["#{solution.label}"] = "#{solution.datasource}"
      datasource_uri["#{solution.datasource}"] = "#{solution.label.to_s.downcase}"
    end
  end

  # Get Ontology Labels
  # ontology_uri = {}
  if File.exists? ("./#{@arg[:output]}/Ontology.nq")
    graph = RDF::Graph.load("./#{@arg[:output]}/Ontology.nq")
    query = RDF::Query.new({
                             ontology: {
                               RDF.type => ontology_type,
                               rdfs_label => :label
                             }
                           })
    query.execute(graph).each do |solution|
      # ontology_uri["#{solution.label}"] = "#{solution.ontology}"
      datasource_uri["#{solution.ontology}"] = "#{solution.label.to_s.downcase}"
    end
  end

  fout = File.open("#{@arg[:output]}/_dbxref.nq", "w")

  # Processing CrossReference ..
  if File.exists? "./#{@arg[:output]}/CrossReference.nq"
    graph = RDF::Graph.load("./#{@arg[:output]}/CrossReference.nq")
    crossreference_type = RDF::URI("#{@arg[:uri]}/resource/#{@db_name}_CrossReference")
    hasDatasource = RDF::URI("#{@arg[:uri]}" + "/mine_vocabulary:hasDataSource")
    hasIdentifier = RDF::URI("#{@arg[:uri]}" + "/mine_vocabulary:hasIdentifier")
    hasValue = RDF::URI(@ontologies["rdf"]+"value")
    query = RDF::Query.new do
      pattern [:uri, RDF.type, crossreference_type]
      pattern [:uri, hasIdentifier, :attribute]
      pattern [:uri, hasDatasource, :datasource]
      pattern [:attribute, hasValue, :id]
    end
    query.execute(graph).each do |solution|
      # ontology_uri["#{solution.label}"] = "#{solution.ontology}"
      # puts "#{solution.uri} #{solution.datasource} #{solution.id}"
      db_label = datasource_uri["#{solution.datasource}"]
      next if ! dbxref_hash.has_key? db_label
      dbxref_hash[db_label].each do |db|
        graph_out = RDF::Graph.new()
        s = RDF::URI("#{solution.uri}")
        relation = db[:uri_rel]
        p = RDF::URI(relation)
        if relation[0..6] != "http://"
          relA = relation.split(":")
          next if ! @ontologies.has_key? relA[0]
          p = RDF::URI(@ontologies[relA[0]]+"#{relA[1]}")
        end
        o = RDF::URI("#{db[:uri_base]}#{solution.id}")
        statement = RDF::Statement.new(s,p,o)
        if statement.valid?
          graph_out << statement
          fout.write(graph_out.dump(:nquads))
        end
      end
    end
  end

  fout.close

  puts "Printing .."
  p datasource_uri
  puts ""
  p dbxref_hash
  puts "Finish"

end

# download intermine data
def download_data

  service = Service.new("#{@arg[:endpoint]}")

  File.open("output.json", "w") do |fout|
    fout.write(JSON.pretty_generate(@all_obj))
  end

  # look for active object
  puts "\n# Looking for Intermine Data Table via the API #"
  @all_obj.each_key do |obj|
    begin
      service.new_query(obj).
        select(["*"]).
        limit(1).
        each_row { |r| @all_obj[obj][:exist] = 1 }
      puts "[#{obj}] Y"
    rescue
      @all_obj[obj][:exist] = 0
      puts "[#{obj}] N"
    end
  end

  # download data to table
  puts "\n# Fetching all mine object classes (with the API) #"
  @all_obj.each_key do |obj|

    # downloading object table
    next if @all_obj[obj][:exist] == 0 or @all_obj[obj][:downloaded]
    ShellSpinner "Querying #{@all_obj[obj][:name]}" do
      retry_it = 0
      fout = File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}.tsv", "a")
      begin
        service.new_query(@all_obj[obj][:name]).
          select(["*"]).
          each_row { |r| fout.write("#{r}\n") }
      rescue Exception => e
        print "\n#{e.message}\n"
        retry_it += 1
        sleep (retry_it*20)
        retry if retry_it < 7
        print "Giving up after 5 attempts"
        @arg[:log] << "Problem downloading #{obj} class"
        @all_obj[obj][:downloaded] = true
      end
      fout.close
    end

    # downloading object reference
    @all_obj[obj][:references].each do |reference|
      fout = File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}_reference_#{reference[:referenced_type]}.tsv", "a")
      if @all_obj.has_key? reference[:referenced_type]
        if @all_obj[reference[:referenced_type]][:exist] == 1
          ShellSpinner "_-> Now querying reference #{@all_obj[obj][:name]} / #{reference[:referenced_type]}" do
            retry_it = 0
            iterator = 0
            begin
              service.new_query(@all_obj[obj][:name]).
                select(["id", "#{reference[:name]}.id" ]).
                each_row { |r| fout.write("#{r}\n") }
            rescue Exception => e
              print "\n#{e.message}\n"
              retry_it += 1
              sleep (retry_it*20)
              retry if retry_it < 7
              print "Giving up after 5 attempts"
              @arg[:log] << "Problem downloading #{obj} reference #{reference[:referenced_type]}"
            end
          end
        end
      end
      fout.close
    end

    # downloading object collections
    @all_obj[obj][:collections].each do |collection|
      fout = File.open("#{@arg[:output]}/#{@all_obj[obj][:name]}_collection_#{collection[:referenced_type]}.tsv", "a")
      if @all_obj.has_key? collection[:referenced_type]
        if @all_obj[collection[:referenced_type]][:exist] == 1
          ShellSpinner "_-> Now querying collection #{@all_obj[obj][:name]} / #{collection[:referenced_type]}" do
            retry_it = 0
            iterator = 0
            begin
              service.new_query(@all_obj[obj][:name]).
                select(["id", "#{collection[:name]}.id" ]).
                each_row { |r| fout.write("#{r}\n") }
            rescue Exception => e
              print "\n#{e.message}\n"
              retry_it += 1
              sleep (retry_it*20)
              retry if retry_it < 7
              print "Giving up after 5 attempts"
              @arg[:log] << "Problem downloading #{obj} collection #{collection[:referenced_type]}"
            end
          end
        end
      end
      fout.close
    end

    @all_obj[obj][:downloaded] = true

  end

end


# get classes from config
def get_classes

  doc = File.open(@arg[:conf]) { |f| Nokogiri::XML(f) }

  doc.xpath("//class").each do |c|

    obj_table = {}
    obj_table[:collections] = []
    obj_table[:attributes] = []
    obj_table[:references] = []

    # get attributes of object
    c.attribute_nodes.each do |att|
      key = att.name.to_s.gsub("-","_")
      if key == "extends"
        obj_table[key.to_sym] = []
        att.value.to_s.split(" ").each do |c|
          obj_table[key.to_sym] << c
        end
      else
        obj_table[key.to_sym] = att.value.to_s
      end
    end

    obj_table[:processed] = false

    # get collections for object
    c.children.each do |elem|

      if elem.name == "collection"
        collection = {}
        elem.attribute_nodes.each do |att|
          key = att.name.to_s.gsub("-","_")
          collection[key.to_sym] = att.value
        end
        obj_table[:collections] << collection if (! collection.empty? and obj_table[:name] != collection[:referenced_type])
      elsif elem.name == "attribute"
        elem.attribute_nodes.each do |att|
          if att.name == "name"
            obj_table[:attributes] << att.value
          end
        end
      elsif elem.name == "reference"
        reference = {}
        elem.attribute_nodes.each do |att|
          key = att.name.to_s.gsub("-","_")
          reference[key.to_sym] = att.value
        end
        obj_table[:references] << reference
      end

    end

    # get reference for object, what is a reference ??
    # adding object to all objects
    if ! @all_obj.has_key? obj_table[:name]
      @all_obj[obj_table[:name]] = obj_table
    else
      obj_table[:collections].each do |collection_it|
        have_collection = false
        have_collection = @all_obj[obj_table[:name]][:collections].any? { |h| h[:name] == collection_it[:name]}
        if ! have_collection
          @all_obj[obj_table[:name]][:collections] << collection_it
        end
      end

    end

  end

end


# set config
def set_configuration

  Dir.mkdir("#{@arg[:output]}") if ! Dir.exists? "#{@arg[:output]}"

  @arg[:conf] = "#{@arg[:output]}/model.xml"
  open(@arg[:conf], 'wb') do |file|
    file << open("#{@arg[:endpoint]}/service/model").read
  end

  @db_name = ""
  @arg[:endpoint].split("/").reverse.each do |n|
    if n != ""
      @db_name = n
      break
    end
  end

  if @arg[:uri] == ""
    @arg[:uri] = "http://#{@db_name}.intermine.org"
  elsif @arg[:uri][-1] == "/"
    @arg[:uri][-1] = @arg[:uri][0..-2]
  end

  # will set @all_obj
  @all_obj = {}
  get_classes

  conf_json = "#{@arg[:output]}/model.json"
  File.open(conf_json,"w") do |f|
    f.write(JSON.pretty_generate(@all_obj))
  end

end


#################### end of RDFIZER




############### MAIN ###############


@usage = "
# This script will query an intermine endpoint via their API and transform the data 
# into RDF nquads files based on the instance's xml object model file :
# http://examplemine.example.org/mymine/service/model

intermine-rdfizer.rb --endpoint [URL] --output [dirname]

	[COMMANDS]  omit all will run --download and --rdfize ; --dbxref can be run afterward

        	--download	will ONLY download table TSV files
		--rdfize	will ONLY RDFize TSV files in output/*.tsv

		--dbxref <file>	mapping for dbxref [ontology / crossreference] tables in a CSV file...
				Need the core.xml object tables Ontology and/or CrossReference and
				the NQuads files, generated with --rdfize
				Columns :
				Type[Ontology|CrossReference], DB/Ontology name, URI-Prefix, URI-relation
				Example :
				CrossReference,Uniprot,http://purl.uniprot.org/uniprot/,skos:exactMatch
				CrossReference,NCBIgene,http://bio2rdf.org/ncbigene:,skos:exactMatch
				Ontology,GO,http://bio2rdf.org/go:,skos:exactMatch
				Ontology,SO,http://purl.obolibrary.org/obo/SO_,owl:sameAs

	[OPTIONS]
		--uri <baseuri> specify a base url for the URI (ex: purl.yeastgenome.org)
				DEFAULT mymine.intermine.org

		--lcoupled	loosely coupled, when pass with --rdfize it will makes different
				resources for a same record based on the table the info is extracted.
				for example : the same gene, cds, orf won't be merged into a single
				resource but kept appart and linked together.
				By default it will be merged into a single resource and get different types.

"

if ARGV.length < 4
  abort @usage
end

# default opt
job = ARGV[0].downcase
@arg = {}
@arg[:log] = []
@arg[:download] = 0
@arg[:rdfize] = 0
@arg[:dbxref] = ""
@arg[:lcoupled] = 0
@arg[:dbxref] = ""
@arg[:conf] = ""
@arg[:uri] = ""


# reading opts
for i in 0..ARGV.length-1
  next if ARGV[i][0] != "-"
  key = ARGV[i].gsub("-","")
  if key == "download"
    @arg[:download] = 1
  elsif key == "rdfize"
    @arg[:rdfize] = 1
  elsif key == "lcoupled"
    @arg[:lcoupled] = 1
  else
    @arg[key.to_sym] = ARGV[i+1]
  end
end


# default options do both download and rdfize
if (@arg[:download] + @arg[:rdfize]) == 0 and @arg[:dbxref] == ""
  @arg[:download] = 1
  @arg[:rdfize] = 1
end

nb_of_opt = 0
mandatory_keys = [:endpoint, :uri, :conf, :output, :download, :rdfize, :log, :lcoupled, :dbxref]

@arg.each_key do |k|
  nb_of_opt += 1
  if ! mandatory_keys.include? k
    puts "Option #{k} not recognized !"
    abort @usage
  end
end

abort @usage if nb_of_opt != 9

# set all configurations
ShellSpinner "# Setting configuration" do
  set_configuration
end

# downloading data
time_download = Benchmark.measure do
  download_data if @arg[:download] == 1
end

# rdfizing data
time_rdfize = Benchmark.measure do
  if @arg[:rdfize] == 1
    rdfize_data
  end
end

# rdfizing data
time_dbxref = Benchmark.measure do
  if @arg[:dbxref] != ""
    ShellSpinner "# Creating Cross References" do
      dbxref
    end
  end
end

# LOGS output
puts ""
puts "## LOGS of the processing ## "
flog = File.open("intermine-rdfizer.log","w")
@arg[:log].each do |l|
  puts "#{l}"
  flog.write("#{l}\n")
end
flog.close
puts ""
puts "Time to download :"
puts time_download
puts "Time to rdfize :"
puts time_rdfize
puts "Time to interlink :"
puts time_dbxref

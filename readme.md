## Intermine RFDizer

This CLI (command line interface) provides a generic RDFizer for any Intermine's endpoint
See http://intermine.org/


### Installation

You can install all the dependencies with the gem bundle

```bash
gem install bundle
bundle install
ruby intermine-rdfizer.rb -h
```

### Usage

**2 mandatory arguments**: -- *endpoint* and --*output*

#### Download and RDFize

**No arguments** will do **both** download and rdfize
```bash
ruby intermine-rdfizer.rb --endpoint http://flymine.org/flymine --output flymine-data
```

**Download** only
```bash
ruby intermine-rdfizer.rb --endpoint http://flymine.org/flymine --output flymine-data --download
```

**RDFize** only
```bash
ruby intermine-rdfizer.rb --endpoint http://flymine.org/flymine --output flymine-data --rdfize
```

#### Create Linked Data

To create Linked Data - database cross references - you need to provide a CSV file with these fields :

* Type (Ontology or CrossReference) (need those tables in the object model see https://github.com/intermine/intermine/blob/master/bio/core/core.xml)
* DB/Ontology name
* URI-Prefix (for the target ontology/database)
* URI-relation (predicate)

Example of a CSV files :
```bash
CrossReference,Uniprot,http://purl.uniprot.org/uniprot/,skos:exactMatch
CrossReference,NCBIgene,http://bio2rdf.org/ncbigene:,skos:exactMatch
Ontology,GO,http://bio2rdf.org/go:,skos:exactMatch
Ontology,SO,http://purl.obolibrary.org/obo/SO_,owl:sameAs
```

To launch the creation of the dbxref triples creation use the options --dbxref <csv file>.
The output directory needs to contains the *.nq files generated with --rdfize, but can be use at the same time

```bash
ruby intermine-rdfizer.rb --endpoint http://flymine.org/flymine --output flymine-data --rdfize --dbxref mapping.csv
```



#### Other options

```bash
ruby intermine-rdfizer.rb
```

```
# This script will query an intermine endpoint via their API and transform the data
# into RDF nquads files based on the instance's xml object model file :
# http://examplemine.example.org/mymine/service/model

intermine-rdfizer.rb --endpoint [URL] --output [dirname]

        [COMMANDS]  omit all will run --download and --rdfize ; --dbxref can be run afterward

                --download      will ONLY download table TSV files
                --rdfize        will ONLY RDFize TSV files in output/*.tsv

                --dbxref <file> mapping for dbxref [ontology / crossreference] tables in a CSV file...
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

                --lcoupled      loosely coupled, when pass with --rdfize it will makes different
                                resources for a same record based on the table the info is extracted from.
                                Example : the same gene, cds, orf won't be merged into a single
                                resource but kept appart and linked together.
                                By default --lcoupled is off and the information from the tables will
                                be merged into a single resource that'd be typed accordingly.

```

=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::RegisterHALFile_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::RegisterHALFile_conf -mlss_id <mlss_id> -species_name_mapping "{134 => 'C57B6J', ... }"

=head1 DESCRIPTION  

Mini-pipeline to load the species-tree and the chromosome-name mapping from a HAL file

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::RegisterHALFile_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;
use Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf;   # For INPUT_PLUS

use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

sub default_options {
    my ($self) = @_;
    return {
        %{$self->SUPER::default_options},

        #Connection parameters for production database (the rest is defined in the base class)
        'host' => 'compara1',

        'halStats_exe'  => $ENV{'PROGRESSIVE_CACTUS_DIR'} . '/submodules/hal/bin/halStats',
        'master_db' => 'mysql://ensro@compara1/mm14_ensembl_compara_master',

        'staging_loc1' => {
            -host   => 'ens-staging1',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
            -db_version => $self->o('ensembl_release'),
        },
        'staging_loc2' => {
            -host   => 'ens-staging2',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
            -db_version => $self->o('ensembl_release'),
        },  
        'livemirror_loc' => {
            -host   => 'ens-livemirror',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
            -db_version => $self->o('ensembl_release'),
        },

        'curr_core_sources_locs'    => [ $self->o('staging_loc1'), $self->o('staging_loc2'), ],
        #'curr_core_sources_locs'    => [ $self->o('livemirror_loc') ],

    };
}


sub pipeline_wide_parameters {  # these parameter values are visible to all analyses, can be overridden by parameters{} and input_id{}
    my ($self) = @_;

    return {
        %{$self->SUPER::pipeline_wide_parameters},          # here we inherit anything from the base class
        'master_db'     => $self->o('master_db'),
        'halStats_exe'  => $self->o('halStats_exe'),
    };
}

sub resource_classes {
    my ($self) = @_;

    return {
         %{$self->SUPER::resource_classes},  # inherit 'default' from the parent class
	 '1Gb'  => { 'LSF' => '-C0 -M1000 -R"select[mem>1000] rusage[mem=1000]"' },
    };
}

sub pipeline_analyses {
    my ($self) = @_;

    return [
        {   -logic_name => 'copy_mlss',
	    -module     => 'Bio::EnsEMBL::Compara::RunnableDB::CopyDataWithFK',
            -parameters => {
                'db_conn'                       => '#master_db#',
                'method_link_species_set_id'    => '#mlss_id#',
            },
            -flow_into => [ 'set_mlss_tag' ],
            -input_ids => [ {
                'mlss_id'   => $self->o('mlss_id'),
                'species_name_mapping'  => $self->o('species_name_mapping'),
            } ],
        },

        {   -logic_name => 'set_mlss_tag',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => {
                'sql' => [ 'INSERT IGNORE INTO method_link_species_set_tag (method_link_species_set_id, tag, value) VALUES (#mlss_id#, "HAL_mapping", "#species_name_mapping#")' ],
            },
            -flow_into  => [ 'load_species_tree', 'species_factory' ],
        },

        {   -logic_name => 'load_species_tree',
	    -module     => 'Bio::EnsEMBL::Compara::RunnableDB::HAL::LoadSpeciesTree',
        },

        {   -logic_name => 'species_factory',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::GenomeDBFactory',
            -flow_into  => {
                '2->A' => { 'get_synonyms' => INPUT_PLUS() },
		'A->1' => [ 'aggregate_synonyms' ],
            },
	},

        {   -logic_name => 'get_synonyms',
            -module     => 'Bio::EnsEMBL::Compara::RunnableDB::HAL::LoadSynonyms',
            -parameters => {
                'registry_dbs'  => $self->o('curr_core_sources_locs'),
                'db_version'    => $self->o('ensembl_release'),
                'compara_db'    => '#master_db#',   # Where the DnaFrags are
            },
            -flow_into  => {
                2 => [ '?accu_name=e2u_synonyms&accu_input_variable=synonym&accu_address={genome_db_id}{name}' ],
            },
	    -rc_name    => '1Gb',
        },

        {   -logic_name => 'aggregate_synonyms',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::SqlCmd',
            -parameters => {
                'sql' => [ q/REPLACE INTO method_link_species_set_tag (method_link_species_set_id, tag, value) VALUES (#mlss_id#, "alt_synonyms", '#expr(stringify(#e2u_synonyms#))expr#')/ ],
            },
	    -rc_name    => '1Gb',
        },

     ];
}

1;

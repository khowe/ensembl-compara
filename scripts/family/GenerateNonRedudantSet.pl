#!/usr/local/ensembl/bin/perl -w

use strict;
use Getopt::Long;

# to work you have to get the pmatch output from /nfs/disk5/ms2/bin/pmatch
# EXIT STATUS
# 1 The input FASTA file $fasta contains duplicated id entries
# 2 Query id and target id have been stored in 2 different indices.

$| = 1;
my $usage = "\nUsage:

$0 fastafile fastafile.index fasta_nr_filename redundant_ids_filename

This script takes as as input a FASTA file with potential redundant entries and 
generates another FASTA file in which redundancy have been removed. It also generates a file
containing the redundant ids (one redundancy per line)

[-h|--help] print out this help message

fastafile              FASTA file with redundancy
fastafile.index        FASTA file index generated by fastaindex
fasta_nr_filename      new FASTA file without redundancy
redundant_ids_filename file containing the redundant ids
\n";

#" makes emacs colr formatting happier...

my $pmatch_executable = "/usr/local/ensembl/bin/pmatch";
my $fastafetch_executable = "/usr/local/ensembl/bin/fastafetch";


unless (-e $fastafetch_executable) {
  $fastafetch_executable = "/nfs/acari/abel/bin/alpha-dec-osf4.0/fastafetch.old";
  if (-e "/proc/version") {
    # it is a linux machine
    $fastafetch_executable = "/nfs/acari/abel/bin/i386/fastafetch.old";
  }
}

my $help = 0;

GetOptions('h' => \$help,
           'help' => \$help);

if ($help) {
  print $usage;
  exit 0;
}

unless (scalar @ARGV == 4) {
  warn "This script needs 4 arguments\n";
  print $usage;
  exit 0;
}

my ($fasta,$fastaindex,$fasta_nr,$redundant_file) = @ARGV;

print STDERR "Reading redundant fasta file...";
open FASTA, $fasta ||
  die "Could not open $fasta, $!\n";

my @all_ids;
my %ids_already_seen;

while (my $line = <FASTA>) {
  if ($line =~ /^>(\S+)\s*.*$/) {
    my $id = $1;
    if ($ids_already_seen{$id}) {
      warn "The input FASTA file $fasta contains duplicated id entries, e.g. $id
Make sure that is not the case.
EXIT 1;"
    }
    push @all_ids, $id;
    $ids_already_seen{$id} = 1;
  }
}

undef %ids_already_seen;

close FASTA;
print STDERR "Done\n";

print STDERR "Running and parsing pmatch ouput...\n";
open PM, "$pmatch_executable $fasta $fasta|" ||
  die "Can not open a filehandle in the pmatch output, $!\n";

my @redundancies;
my %stored_at_index;

# The whole process that results are sorted by $qid and $tid which is basically what pmatch
# output does. If the result appears in a randon way (no reason for that though) the process may break
# with exit code 1

while (my $line = <PM>) {
  chomp $line;
  my ($length, $qid, $qstart, $qend, $qperc, $tid, $tstart, $tend, $tperc, $qlen, $tlen) = split /\s+/,$line;
  next if ($qid eq $tid);
 
  next unless ($length == $qlen && $length == $tlen);
  if (defined $stored_at_index{$qid} && defined $stored_at_index{$tid}) {
    if ($stored_at_index{$qid} != $stored_at_index{$tid}) {
      warn "Query $qid and target $tid have been stored in 2 different indices.
$line
EXIT 2";
      exit 2;
    }
  } elsif (defined $stored_at_index{$qid}) {
    my $idx = $stored_at_index{$qid};
    push @{$redundancies[$idx]}, $tid;
    $stored_at_index{$tid} = $idx;
  } elsif (defined $stored_at_index{$tid}) {
    my $idx = $stored_at_index{$tid};
    push @{$redundancies[$idx]}, $qid;
    $stored_at_index{$qid} = $idx;
  } else {
    my $idx = scalar @redundancies;
    push @{$redundancies[$idx]}, $qid;
    $stored_at_index{$qid} = $idx;
    push @{$redundancies[$idx]}, $tid;
    $stored_at_index{$tid} = $idx;
  }
}

print STDERR "pmatch Done\n";

print STDERR "Generating the non redundant fasta file and the redundant ids file...";
my $rand = time().rand(1000);
my $ids_file = "/tmp/ids.$rand";
open ID, ">$ids_file";

foreach my $id (@all_ids) {
  next if (defined $stored_at_index{$id});
  print ID $id,"\n";
}

open NR, ">$redundant_file";

foreach my $redundancy (@redundancies) {
  print NR join " ", @{$redundancy},"\n";
  print ID $redundancy->[0],"\n";
}

close NR;
close ID;

print STDERR "Done\n";

my $new_fasta_file = "/tmp/fasta.$rand";

unless(system("$fastafetch_executable $fasta $fastaindex $ids_file |grep -v \"^Message\"> $new_fasta_file") == 0) {
  unlink glob("/tmp/*$rand*");
  die "error in $fastafetch_executable, $!\n";
}

unless (system("cp $new_fasta_file $fasta_nr") == 0) {
  unlink glob("/tmp/*$rand*");
  die "error in cp $new_fasta_file $fasta_nr, $!\n";
}

unlink glob("/tmp/*$rand*");

exit 0;


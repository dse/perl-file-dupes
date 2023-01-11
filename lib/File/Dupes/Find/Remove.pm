package File::Dupes::Find::Remove;
use warnings;
use strict;

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(remove_callback);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

use lib "../../../../lib";
use File::Dupes::Find::Confirm qw(confirm_duplicates confirm_hard_links);

sub remove_callback {
    my (%args) = @_;
    my $verbose = $args{verbose};
    my $test    = $args{test};
    my $dry_run = $args{dry_run};

    my @filenames = @{$args{filenames}};
    my %hard_link_groups = %{$args{hard_link_groups}};
    if ($verbose >= 2) {
        printf("found a set of duplicate filenames\n");
        foreach my $filename (@filenames) {
            print("-   $filename\n");
            my @links = @{$hard_link_groups{$filename}};
            shift(@links);
            foreach my $link (@links) {
                print("    hard-linked as $link\n");
            }
        }
    }
    if ($test) {
        confirm_duplicates(@filenames);
        if ($verbose) {
            warn("duplicate file check passed: ", join("\n                             ", @filenames), "\n");
        }
        foreach my $filename (@filenames) {
            my @links = @{$hard_link_groups{$filename}};
            confirm_hard_links(@links);
            if ($verbose) {
                warn("hard links check passed: ", join("\n                         ", @links), "\n");
            }
        }
    }
    my ($main_filename, @other_filenames) = @filenames;
    foreach my $filename (@other_filenames) {
        my @links = @{$hard_link_groups{$filename}};
        foreach my $link (@links) {
            if ($dry_run) {
                warn("DRY RUN: rm $link\n");
            } else {
                if (unlink($link)) {
                    if ($verbose) {
                        warn("removed $link\n");
                    }
                } else {
                    warn("$link: $!\n");
                }
            }
        }
    }
}

1;

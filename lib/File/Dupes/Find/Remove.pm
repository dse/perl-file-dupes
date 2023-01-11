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
    my $verify    = $args{verify};
    my $dry_run = $args{dry_run};
    my $no_delete_dir = $args{no_delete_dir};

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
    if ($verify) {
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
    @other_filenames = grep { $_ !~ m{^\Q$no_delete_dir\E/} } @other_filenames; # never delete files here
    foreach my $filename (@other_filenames) {
        my @links = @{$hard_link_groups{$filename}};
        my $index = 0;
        my $count = scalar @links;
        foreach my $link (@links) {
            my $bytes = -s $links[0];
            ++$index;
            my $suffix = sprintf("(%d/%d - %d bytes)", $index, $count, $bytes);
            if (scalar @links == 1) {
                $suffix = sprintf("(%d bytes)", $bytes);
            }
            if ($dry_run) {
                warn("DRY RUN: rm $link $suffix\n");
            } else {
                if (unlink($link)) {
                    if ($verbose) {
                        warn("removed $link $suffix\n");
                    }
                } else {
                    warn("$link: $!\n");
                }
            }
        }
    }
}

1;

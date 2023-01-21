package File::Dupes;
use warnings;
use strict;

use Symbol;

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(group_hard_links
                    check_for_dupes);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

sub group_hard_links {
    my (@filenames) = @_;

    # group hard links together.
    my %hard_links;
    foreach my $filename (@filenames) {
        my @lstat = lstat($filename);
        my ($dev, $ino) = @lstat;
        next if !defined $dev || !defined $ino;
        push(@{$hard_links{$dev,$ino}}, $filename);
    }
    my @groups = values %hard_links;

    # in order of initial appearance in list
    my %index_of = indexed(@filenames);
    @groups = sort { $index_of{$a->[0]} <=> $index_of{$b->[0]} } @groups;

    return @groups if wantarray;
    return [@groups];
}

sub indexed {
    my (@filenames) = @_;
    my %index_of;
    for (my $i = 0; $i < scalar @filenames; $i += 1) {
        $index_of{$filenames[$i]} //= $i;
    }
    return %index_of if wantarray;
    return {%index_of} if defined wantarray;
}

our $BYTES;
our $MAXOPEN;
BEGIN {
    $BYTES = 4096;
    $MAXOPEN = 16;
}

use Fcntl qw(SEEK_SET);

sub check_for_dupes {
    my (@filenames) = @_;

    # exclude hard links from duplicate checking.
    my @hard_link_groups = group_hard_links(@filenames);
    @filenames = map { $_->[0] } @hard_link_groups;

    return if scalar @filenames < 2; # sanity check

    my %fh;
    my %done;
    my $touch_counter = 0;
    my %touched = map { ($_ => 0) } @filenames;

    my $offset = 0;
    my @results;    # collect groups of files having the same content.
    my @groups = ([@filenames]); # initialize with one group
  iter:
    while (1) {
        my @newgroups; # collect groups for next iteration of this loop
      group:
        foreach my $group (@groups) {
            # all files in here have the same content thus far.
            my @done; # collect files we finished reading last iteration
            my %group; # yes, we're using 4096-byte chunks as hash keys :-D
          file:
            foreach my $filename (@$group) {
                my $data;

                my $fh = $fh{$filename};
                if (!defined $fh) {
                    while (scalar keys %fh >= $MAXOPEN) {
                        my @touched = sort { $touched{$a} <=> $touched{$b} } keys %fh;
                        my $oldest = $touched[0];
                        $fh = $fh{$oldest};
                        close($fh);
                        delete $fh{$oldest};
                    }
                    if (!open($fh, '<:raw', $filename)) {
                        warn("$filename: $!\n");
                        next file;
                    }
                    if ($offset) {
                        my $real_offset = sysseek($fh, $offset, SEEK_SET);
                        if ($real_offset != $offset) {
                            close($fh);
                            next file;
                        }
                    }
                    $fh{$filename} = $fh;
                }

                my $bytes = sysread($fh, $data, $BYTES);
                $touched{$filename} = ++$touch_counter;
                if (!defined $bytes) {
                    close($fh);
                    delete $fh{$filename};
                } elsif (!$bytes) {
                    close($fh{$filename});
                    delete $fh{$filename};
                    push(@done, $filename);
                } else {
                    push(@{$group{$data}}, $filename) if defined $data;
                }
            }
            if (scalar @done >= 2) {
                # we have a group of files ready to return
                push(@results, [@done]);
            }
            foreach my $key (keys %group) {
                my $group = $group{$key};
                if (scalar @$group >= 2) {
                    # we have a group of files ready for next loop iteration
                    push(@newgroups, $group);
                }
            }
        }
        if (!scalar @newgroups) {
            return @results if wantarray;
            return [@results];
        }
        @groups = @newgroups;
        $offset += $BYTES;
    }
}

1;

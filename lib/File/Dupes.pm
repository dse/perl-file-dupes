package File::Dupes;
use warnings;
use strict;

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(group_hard_links
                    check_for_dupes);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

sub group_hard_links {
    my (@filenames) = @_;
    my %hard_links;
    foreach my $filename (@filenames) {
        my @lstat = lstat($filename);
        next unless scalar @lstat;
        my ($dev, $ino) = @lstat;
        push(@{$hard_links{$dev,$ino}}, $filename);
    }
    my @groups;
    foreach my $key (keys %hard_links) {
        push(@groups, $hard_links{$key});
    }
    return @groups if wantarray;
    return [@groups];
}

sub check_for_dupes {
    my (@filenames) = @_;
    my @objects = map { { filename => $_ } } @filenames;
    foreach my $object (@objects) {
        my $fh;
        if (!open($fh, '<:raw', $object->{filename})) {
            $object->{error} = $!;
        } else {
            $object->{fh} = $fh;
        }
    }
    @objects = grep { !$_->{error} } @objects;
    return if scalar @objects < 2;

    my @results;

    my @groups = ( [@objects] );
    while (1) {
        my @newgroups;
        foreach my $group (@groups) {
            my @done;
            my %group;
            foreach my $obj (@$group) {
                my $data;
                my $bytes = sysread($obj->{fh}, $data, 4096);
                if (!defined $bytes) {
                    close($obj->{fh});
                    delete $obj->{fh};
                } elsif (!$bytes) {
                    close($obj->{fh});
                    delete $obj->{fh};
                    push(@done, $obj);
                } else {
                    push(@{$group{$data}}, $obj) if defined $data;
                }
            }
            if (scalar @done >= 2) {
                push(@results, [@done]);
            }
            foreach my $key (keys %group) {
                my $group = $group{$key};
                if (scalar @$group >= 2) {
                    push(@newgroups, $group);
                }
            }
        }
        if (!scalar @newgroups) {
            return @results if wantarray;
            return [@results];
        }
        @groups = @newgroups;
    }
}

1;

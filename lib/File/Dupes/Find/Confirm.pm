package File::Dupes::Find::Confirm;
use warnings;
use strict;

use Digest::SHA;

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(confirm_duplicates
                    confirm_hard_links);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

sub confirm_duplicates {
    my @filenames = @_;
    my %sum;
    my %bysum;
    foreach my $filename (@filenames) {
        my $sha = Digest::SHA->new('1');
        $sha->addfile($filename);
        my $sum = $sha->hexdigest;
        $sum{$filename} = $sum;
        push(@{$bysum{$sum}}, $filename);
    }
    if (scalar keys %bysum < 2) {
        return 1;
    }
    warn("failed duplicates check\n");
    foreach my $filename (@filenames) {
        warn(sprintf("    %s  %s\n", $sum{$filename}, $filename));
    }
    die();
}

sub confirm_hard_links {
    my @filenames = @_;
    my %devino;
    my %bydevino;
    foreach my $filename (@filenames) {
        my @lstat = lstat($filename);
        next if !scalar @lstat;
        my ($dev, $ino) = @lstat;
        push(@{$bydevino{$dev,$ino}}, $filename);
        $devino{$filename} = [$dev,$ino];
    }
    if (scalar keys %bydevino < 2) {
        return 1;
    }
    warn("failed hard links check\n");
    foreach my $filename (@filenames) {
        warn(sprintf("    %s,%s  %s\n", @{$devino{$filename}}, $filename));
    }
    die();
}

1;

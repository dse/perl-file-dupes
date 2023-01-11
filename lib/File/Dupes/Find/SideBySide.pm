package File::Dupes::Find::SideBySide;
use warnings;
use strict;
use feature qw(state);

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(find_side_by_side);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

our $DEFAULT_MIN_SIZE = 1048576;
our $PROGRESS_EVERY = 233;

use File::Find qw();
use Digest::SHA qw();
use Scalar::Util qw(looks_like_number);
use File::Spec::Functions qw(abs2rel);
use Getopt::Long;
use List::Util qw(uniq);
use Data::Dumper qw(Dumper);

use lib "../../..";
use File::Dupes qw(check_for_dupes
                   group_hard_links);

sub find_side_by_side {
    my @dirs;
    my %options;
    foreach my $arg (@_) {
        next if !defined $arg;
        if (ref $arg eq 'ARRAY') {
            push(@dirs, @$arg);
        } elsif (ref $arg eq 'HASH') {
            %options = (%options, %$arg);
        } elsif (ref $arg eq '') {
            push(@dirs, $arg);
        }
    }
    $options{done_hash} = {};
    my @results;
    while (scalar @dirs >= 2) {
        push(@results, find_side_by_side_1({%options}, @dirs));
        shift(@dirs);
    }
    return @results if wantarray;
    return [@results];
}

sub find_side_by_side_1 {
    my ($options, @dirs) = @_;
    my %options = %$options;
    my $min_size = $options{min_size} // $DEFAULT_MIN_SIZE;
    my $callback = $options{callback};
    my $done_hash = $options{done_hash};

    my $verbose  = $options{verbose};
    my $dry_run  = $options{dry_run};
    my $verify   = $options{verify};
    my $progress = $options{progress};

    my ($dir, @other_dirs) = @dirs;
    my $count;
    my @results;
    my $wanted = sub {
        my $filename = $_;
        my $first_filename = $_;

        if ($progress) {
            $count += 1;
            progress("%8d %s", $count, $filename) if $count % $PROGRESS_EVERY == 0;
        }

        my @lstat = lstat($filename);
        return if (!scalar @lstat);
        return if (-d _) || (!-f _) || (-s _ < $min_size);

        my $rel = abs2rel($filename, $dir);
        return if $done_hash->{$rel};
        $done_hash->{$rel} = 1;

        my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = @lstat;
        my @other_filenames = map { "$_/$rel" } @other_dirs;
        @other_filenames = grep { -f $_ && -s $_ == $size } @other_filenames;
        return unless scalar @other_filenames;
        my @filenames = ($filename, @other_filenames);
        my @hard_link_groups = group_hard_links(@filenames);
        return if scalar @hard_link_groups < 2;
        my @main_filenames = map { $_->[0] } @hard_link_groups;
        my %hard_link_groups;
        foreach my $hard_link_group (@hard_link_groups) {
            my $filename = $hard_link_group->[0];
            $hard_link_groups{$filename} = $hard_link_group;
        }
        my @file_groups = check_for_dupes(@main_filenames);
        foreach my $file_group (@file_groups) {
            my @group_filenames = @$file_group;
            push(@results, [@group_filenames]) if defined wantarray;
            if ($callback && ref $callback eq 'CODE') {
                progress() if $progress;
                my %args = (
                    filenames => \@group_filenames,
                    hard_link_groups => \%hard_link_groups,
                    verbose => $verbose,
                    dry_run => $dry_run,
                    verify => $verify,
                    progress => $progress,
                );
                &$callback(%args);
            }
        }
    };
    progress() if $progress;
    File::Find::find({ wanted => $wanted, no_chdir => 1 }, $dir);
    progress() if $progress;
    return @results if wantarray;
    return [@results] if defined wantarray;
}

sub progress {
    state $ready = 1;
    return unless -t 2;
    my ($format, @args) = @_;
    if (!defined $format) {
        return if $ready;
        print STDERR "\r\e[K";
        $ready = 1;
        return;
    }
    $ready = 0;
    my $string = sprintf($format, @args);
    print STDERR "\r" . $string . "\e[K";
}

1;

package File::Dupes::Find::Everywhere;
use warnings;
use strict;
use feature qw(state);

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(find_everywhere);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

our $DEFAULT_MIN_SIZE = 1048576;
our $PROGRESS_EVERY = 233;

use File::Find;

use lib "../../..";
use File::Dupes qw(check_for_dupes
                   group_hard_links);

sub find_everywhere {
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
    my $min_size = $options{min_size} // $DEFAULT_MIN_SIZE;
    my $callback = $options{callback};

    my $verbose  = $options{verbose};
    my $dry_run  = $options{dry_run};
    my $verify   = $options{verify};
    my $progress = $options{progress};

    my %by_size;
    my %by_dev_ino;
    my %dev_ino;
    my %hard_link_groups;

    foreach my $dir (@dirs) {
        if ($verbose) {
            warn("Finding files in ${dir} ...\n");
        }
        my $count = 0;
        my $wanted = sub {
            my $basename = $_;
            my $filename = $File::Find::name;

            if ($progress) {
                $count += 1;
                progress("%8d %s", $count, $filename) if $count % $PROGRESS_EVERY == 0;
            }

            my @lstat = lstat($_);
            return if (!scalar @lstat);
            return if (-d _) || (!-f _) || (-s _ < $min_size);

            my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = @lstat;
            if (!$by_dev_ino{$dev,$ino}) {
                push(@{$by_size{$size}}, $filename);
                $dev_ino{$filename} = [$dev, $ino];
                $hard_link_groups{$filename} = $by_dev_ino{$dev,$ino} = [];
            }
            push(@{$by_dev_ino{$dev,$ino}}, $filename);
        };
        progress() if $progress;
        File::Find::find({ wanted => $wanted }, $dir);
        progress() if $progress;
        if ($verbose) {
            printf STDERR ("%d files found\n", $count);
        }
    }
    my $first_dir = $dirs[0];
    my @results;
    foreach my $size (sort { $b <=> $a } keys %by_size) {
        my @filenames = @{$by_size{$size}};
        next if scalar @filenames < 2;
        my @filenames_other_dirs = grep { ! m{^\Q${first_dir}\E/} } @filenames;
        if (!scalar @filenames_other_dirs) {
            # we're not deleting any files in the first directory
            next;
        }
        my @file_groups = check_for_dupes(@filenames);
        foreach my $file_group (@file_groups) {
            my @filenames = @{$file_group};
            my @filenames_other_dirs = grep { ! m{^\Q${first_dir}\E/} } @filenames;
            if (!scalar @filenames_other_dirs) {
                # we're not deleting any files in the first directory
                next;
            }
            push(@results, [@filenames]) if defined wantarray;
            if ($callback && ref $callback eq 'CODE') {
                my %args = (
                    filenames => \@filenames,
                    hard_link_groups => \%hard_link_groups,
                    verbose => $verbose,
                    dry_run => $dry_run,
                    verify => $verify,
                    progress => $progress,
                    no_delete_dir => $dirs[0],
                );
                &$callback(%args);
            }
        }
    }
    progress();
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

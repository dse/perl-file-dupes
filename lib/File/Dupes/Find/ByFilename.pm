package File::Dupes::Find::ByFilename;
use warnings;
use strict;
use feature qw(state);

use base 'Exporter';

our @EXPORT = ();
our @EXPORT_OK = qw(find_by_filename);
our %EXPORT_TAGS = (
    all => [@EXPORT_OK],
);

our $DEFAULT_MIN_SIZE = 1048576;
our $PROGRESS_EVERY = 233;

use File::Find;

use lib "../../..";
use File::Dupes qw(check_for_dupes
                   group_hard_links);

sub find_by_filename {
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

    my %filenames_by_basename;
    my %devino;
    my %size;
    foreach my $dir (@dirs) {
        if ($verbose) {
            warn("Finding files in ${dir} ...\n");
        }
        my $count = 0;
        my $wanted = sub {
            if ($progress) {
                $count += 1;
                progress("%8d %s", $File::Find::name) if $count % $PROGRESS_EVERY == 0;
            }
            my $basename = $_;
            my $filename = $File::Find::name;

            my @lstat = lstat($_);
            return if (!scalar @lstat);
            return if (-d _) || (!-f _) || (-s _ < $min_size);

            my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size, $atime, $mtime, $ctime, $blksize, $blocks) = @lstat;
            push(@{$filenames_by_basename{$basename}}, $filename);
            $devino{$filename} = [$dev,$ino];
            $size{$filename} = $size;
        };
        progress() if $progress;
        File::Find::find({ wanted => $wanted }, $dir);
        progress() if $progress;
        if ($verbose) {
            printf STDERR ("%d files found\n", $count);
        }
    }
    my @results;
    my $total = scalar keys %filenames_by_basename;
    if ($verbose) {
        progress();
        printf STDERR ("%d unique base filenames found\n");
    }
    my $count = 0;
    foreach my $basename (keys %filenames_by_basename) {
        if ($progress) {
            $count += 1;
            progress("%d/%d", $count, $total) if $count % $PROGRESS_EVERY == 0;
        }
        my @filenames = @{$filenames_by_basename{$basename}};
        my %index = map { ($filenames[$_] => $_) } (0 .. $#filenames);
        next if scalar @filenames < 2;
        my $first_filename = $filenames[0];
        my %filenames_by_dev_ino;
        foreach my $filename (@filenames) {
            my ($dev, $ino) = @{$devino{$filename}};
            push(@{$filenames_by_dev_ino{$dev,$ino}}, $filename);
        }
        my %hardlinks_by_main_filename;
        foreach my $key (keys %filenames_by_dev_ino) {
            my @filenames = @{$filenames_by_dev_ino{$key}};
            my $main_filename = $filenames[0];
            $hardlinks_by_main_filename{$main_filename} = $filenames_by_dev_ino{$key};
        }
        my @main_filenames = sort { $index{$a} <=> $index{$b} } keys %hardlinks_by_main_filename; # for good measure
        my %main_filenames_by_size;
        foreach my $main_filename (@main_filenames) {
            my $size = $size{$main_filename};
            push(@{$main_filenames_by_size{$size}}, $main_filename);
        }
        foreach my $size (keys %main_filenames_by_size) {
            my @main_filenames = @{$main_filenames_by_size{$size}};
            next if scalar @main_filenames < 2;
            @main_filenames = sort { $index{$a} <=> $index{$b} } @main_filenames; # for good measure
            my %hard_link_groups;
            foreach my $main_filename (@main_filenames) {
                $hard_link_groups{$main_filename} = $hardlinks_by_main_filename{$main_filename};
            }
            my @file_groups = check_for_dupes(@main_filenames);
            foreach my $file_group (@file_groups) {
                my @group_filenames = @$file_group;
                @group_filenames = sort { $index{$a} <=> $index{$b} } @group_filenames; # for good measure
                push(@results, [@group_filenames]) if defined wantarray;
                if ($callback && ref $callback eq 'CODE') {
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
